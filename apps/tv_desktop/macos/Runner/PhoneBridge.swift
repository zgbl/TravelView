import Cocoa
import FlutterMacOS
import ImageCaptureCore
import ImageIO
import CoreLocation
import AVFoundation
import Vision
import Accelerate

/// iPhone / 相机直读桥。
///
/// **只读保证**: 这个文件里不存在任何写入或删除手机内容的调用。
/// ImageCaptureCore 的删除接口是 `requestDeleteFiles` 与下载选项
/// `ICDownloadOption.deleteAfterSuccessfulDownload` —— 两者都不允许出现在本项目里，
/// tools/ 下的 pre-commit 钩子会拦截。
///
/// 走的是 PTP 协议（macOS「图像捕捉」用的同一套）。能拿到 DCIM 里的原件和完整 EXIF；
/// 拿不到相册结构，也拿不到被 iCloud「优化存储」抽走的原图（那需要装在手机上的 App）。
class PhoneBridge: NSObject {

  /// 图像解码专用队列。并发数由 Dart 侧限流，这里只保证不碰主线程。
  static let work = DispatchQueue(
    label: "com.travelview.imagework",
    qos: .userInitiated,
    attributes: .concurrent)

  /// 后台预热专用。qos 更低，系统会在前台忙时自动给它让路 ——
  /// 这是"后面慢一点可以等"能真正成立的关键。
  static let bgWork = DispatchQueue(
    label: "com.travelview.imagework.bg",
    qos: .utility,
    attributes: .concurrent)

  private let channel: FlutterMethodChannel
  private let browser = ICDeviceBrowser()
  private var cameras: [String: ICCameraDevice] = [:]

  private var openResult: FlutterResult?
  private var openDeviceId: String?

  private var pendingDownloads: [ICCameraFile] = []
  private var downloadDestination: URL?
  private var downloadedFiles: [[String: String]] = []
  private var downloadResult: FlutterResult?
  private var downloadTotal = 0

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "travelview/phone", binaryMessenger: messenger)
    let instance = PhoneBridge(channel: channel)
    channel.setMethodCallHandler { call, result in
      instance.handle(call, result: result)
    }
  }

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    browser.delegate = self
    if let mask = ICDeviceTypeMask(
      rawValue: ICDeviceTypeMask.camera.rawValue
        | ICDeviceLocationTypeMask.local.rawValue) {
      browser.browsedDeviceTypeMask = mask
    }
    browser.start()
  }

  // MARK: - 方法分发

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "listDevices":
      result(deviceList())

    case "openDevice":
      guard let id = args["deviceId"] as? String, let cam = cameras[id] else {
        result(err("NO_DEVICE", "找不到设备，请重新插拔数据线")); return
      }
      if cam.hasOpenSession {
        result(["ready": true, "itemCount": cam.mediaFiles?.count ?? 0])
      } else {
        openResult = result
        openDeviceId = id
        cam.delegate = self
        cam.requestOpenSession()
      }

    case "listItems":
      guard let id = args["deviceId"] as? String, let cam = cameras[id] else {
        result(err("NO_DEVICE", "找不到设备")); return
      }
      result(itemList(cam))

    case "downloadItems":
      guard let id = args["deviceId"] as? String, let cam = cameras[id],
            let names = args["names"] as? [String],
            let dest = args["destDir"] as? String else {
        result(err("BAD_ARGS", "参数不完整")); return
      }
      startDownload(cam, names: names, destDir: dest, result: result)

    case "closeDevice":
      if let id = args["deviceId"] as? String, let cam = cameras[id],
         cam.hasOpenSession {
        cam.requestCloseSession()
      }
      result(true)

    case "readMetadata":
      guard let path = args["path"] as? String else {
        result(err("BAD_ARGS", "缺少 path")); return
      }
      // 解码/读元数据一律不能占用主线程 —— MethodChannel 的 handler
      // 默认就跑在主线程上，几千张 HEIC 会把整个 UI 卡死。
      PhoneBridge.work.async {
        let m = PhoneBridge.readMetadata(path: path)
        DispatchQueue.main.async { result(m) }
      }

    case "makeThumbnail":
      guard let src = args["path"] as? String,
            let dst = args["destPath"] as? String else {
        result(err("BAD_ARGS", "缺少 path/destPath")); return
      }
      let maxPx = args["maxPixels"] as? Int ?? 480
      let background = args["background"] as? Bool ?? false
      let queue = background ? PhoneBridge.bgWork : PhoneBridge.work
      queue.async {
        let ok = PhoneBridge.makeThumbnail(src: src, dst: dst, maxPixels: maxPx)
        DispatchQueue.main.async { result(ok) }
      }

    case "analyze":
      guard let path = args["path"] as? String else {
        result(err("BAD_ARGS", "缺少 path")); return
      }
      PhoneBridge.bgWork.async {
        let m = PhoneBridge.analyze(path: path)
        DispatchQueue.main.async { result(m) }
      }

    case "exportWeb":
      guard let src = args["path"] as? String,
            let dst = args["destPath"] as? String else {
        result(err("BAD_ARGS", "缺少 path/destPath")); return
      }
      let maxPx = args["maxPixels"] as? Int ?? 1600
      let quality = args["quality"] as? Double ?? 0.82
      let forceJpeg = args["forceJpeg"] as? Bool ?? false
      PhoneBridge.bgWork.async {
        let m = PhoneBridge.exportWeb(
          src: src, dst: dst, maxPixels: maxPx, quality: quality,
          forceJpeg: forceJpeg)
        DispatchQueue.main.async { result(m) }
      }

    case "rotate":
      guard let path = args["path"] as? String else {
        result(err("BAD_ARGS", "缺少 path")); return
      }
      let cw = args["clockwise"] as? Bool ?? true
      PhoneBridge.work.async {
        let ok = PhoneBridge.rotate(path: path, clockwise: cw)
        DispatchQueue.main.async { result(ok) }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func err(_ code: String, _ msg: String) -> FlutterError {
    FlutterError(code: code, message: msg, details: nil)
  }

  // MARK: - 设备与文件枚举

  private func deviceList() -> [[String: Any]] {
    cameras.map { id, cam in
      [
        "id": id,
        "name": cam.name ?? "未知设备",
        "open": cam.hasOpenSession,
        "itemCount": cam.mediaFiles?.count ?? 0,
      ]
    }
  }

  /// 文件的唯一标识 = 所在文件夹路径 + 文件名。
  /// 只用文件名是不够的: iPhone 的 DCIM 分成 100APPLE / 101APPLE 等多个文件夹，
  /// 计数器到 IMG_9999 后绕回 IMG_0001，不同年份的照片会重名。
  private func itemKey(_ item: ICCameraItem) -> String {
    var parts: [String] = [item.name ?? ""]
    var folder = item.parentFolder
    while let f = folder {
      if let n = f.name, !n.isEmpty { parts.insert(n, at: 0) }
      folder = f.parentFolder
    }
    return parts.joined(separator: "/")
  }

  private func itemList(_ cam: ICCameraDevice) -> [[String: Any]] {
    guard let files = cam.mediaFiles else { return [] }
    return files.compactMap { item in
      guard let f = item as? ICCameraFile else { return nil }
      var m: [String: Any] = [
        "key": itemKey(f),
        "name": f.name ?? "",
        "size": f.fileSize,
      ]
      if let created = f.creationDate {
        m["created"] = Int(created.timeIntervalSince1970 * 1000)
      }
      if let uti = f.uti { m["uti"] = uti }
      return m
    }
  }

  // MARK: - 下载（只读: 从不传 deleteAfterSuccessfulDownload）

  private func startDownload(
    _ cam: ICCameraDevice, names: [String], destDir: String,
    result: @escaping FlutterResult
  ) {
    guard let files = cam.mediaFiles else {
      result(err("NO_ITEMS", "设备上没有可读取的文件")); return
    }
    // names 里传的是 itemKey（文件夹路径+文件名），不是裸文件名
    let wanted = Set(names)
    pendingDownloads = files.compactMap { $0 as? ICCameraFile }
      .filter { wanted.contains(itemKey($0)) }

    if pendingDownloads.isEmpty {
      result([String]()); return
    }

    let url = URL(fileURLWithPath: destDir, isDirectory: true)
    try? FileManager.default.createDirectory(
      at: url, withIntermediateDirectories: true)

    downloadDestination = url
    downloadedFiles = []
    downloadResult = result
    downloadTotal = pendingDownloads.count
    downloadNext(cam)
  }

  private func downloadNext(_ cam: ICCameraDevice) {
    guard let dest = downloadDestination else { return }
    guard let file = pendingDownloads.first else {
      let out = downloadedFiles
      downloadResult?(out)
      downloadResult = nil
      downloadDestination = nil
      return
    }
    pendingDownloads.removeFirst()

    // 中转文件名必须唯一 —— 同名文件同时下载会互相冲突。
    // 原始文件名通过 didDownloadFile 单独回传，入库时仍用真名。
    let staged = stagedName(for: file)
    let options: [ICDownloadOption: Any] = [
      .downloadsDirectoryURL: dest,
      .saveAsFilename: staged,
      .overwrite: false,
      // 绝不加 .deleteAfterSuccessfulDownload —— 手机上的照片只读
    ]
    cam.requestDownloadFile(
      file,
      options: options,
      downloadDelegate: self,
      didDownloadSelector: #selector(
        didDownloadFile(_:error:options:contextInfo:)),
      contextInfo: nil)
  }

  /// 中转文件名: 由 itemKey 唯一决定（不能依赖计数器，
  /// 否则下载前和回调时算出来的名字对不上）
  private func stagedName(for file: ICCameraFile) -> String {
    return itemKey(file).replacingOccurrences(of: "/", with: "_")
  }

  @objc func didDownloadFile(
    _ file: ICCameraFile, error: Error?,
    options: [String: Any], contextInfo: UnsafeMutableRawPointer?
  ) {
    if error == nil, let dest = downloadDestination {
      let staged = stagedName(for: file)
      downloadedFiles.append([
        "path": dest.appendingPathComponent(staged).path,
        "name": file.name ?? staged,
      ])
    }
    let done = downloadTotal - pendingDownloads.count
    channel.invokeMethod("onDownloadProgress", arguments: [
      "done": done,
      "total": downloadTotal,
      "name": file.name ?? "",
      "error": error?.localizedDescription as Any,
    ])
    if let cam = file.device {
      downloadNext(cam)
    }
  }

  // MARK: - EXIF / 缩略图（ImageIO，原生支持 HEIC）

  static func readMetadata(path: String) -> [String: Any] {
    var out: [String: Any] = [:]
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil)
            as? [CFString: Any] else {
      return out
    }
    if let w = props[kCGImagePropertyPixelWidth] as? Int { out["width"] = w }
    if let h = props[kCGImagePropertyPixelHeight] as? Int { out["height"] = h }

    if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
      if let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
        out["takenAt"] = s   // "2025:09:12 14:30:22"
      }
    }
    if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
      let make = tiff[kCGImagePropertyTIFFMake] as? String ?? ""
      let model = tiff[kCGImagePropertyTIFFModel] as? String ?? ""
      let device = "\(make) \(model)".trimmingCharacters(in: .whitespaces)
      if !device.isEmpty { out["device"] = device }
    }
    if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
      if let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
         let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
        let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
        let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
        out["lat"] = latRef == "S" ? -lat : lat
        out["lon"] = lonRef == "W" ? -lon : lon
      }
    }
    return out
  }

  private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi"]

  /// 把任意格式转成一张 JPEG 缩略图。
  /// 图片走 ImageIO（原生支持 HEIC），视频走 AVFoundation 取第一帧。
  /// 解决 Flutter 既不认 HEIC 也不能把视频当图片显示的问题。
  static func makeThumbnail(src: String, dst: String, maxPixels: Int) -> Bool {
    let srcURL = URL(fileURLWithPath: src)
    let dstURL = URL(fileURLWithPath: dst)

    if videoExtensions.contains(srcURL.pathExtension.lowercased()) {
      return makeVideoThumbnail(srcURL: srcURL, dstURL: dstURL, maxPixels: maxPixels)
    }

    guard let source = CGImageSourceCreateWithURL(srcURL as CFURL, nil) else {
      return false
    }
    let opts: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    guard let thumb = CGImageSourceCreateThumbnailAtIndex(
      source, 0, opts as CFDictionary) else { return false }

    try? FileManager.default.createDirectory(
      at: dstURL.deletingLastPathComponent(),
      withIntermediateDirectories: true)

    guard let out = CGImageDestinationCreateWithURL(
      dstURL as CFURL, "public.jpeg" as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(out, thumb, [
      kCGImageDestinationLossyCompressionQuality: 0.82,
    ] as CFDictionary)
    return CGImageDestinationFinalize(out)
  }
}

extension PhoneBridge {

  /// 视频首帧。Live Photo 的 MOV 和真视频都走这里。
  static func makeVideoThumbnail(srcURL: URL, dstURL: URL, maxPixels: Int) -> Bool {
    let asset = AVURLAsset(url: srcURL)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: maxPixels, height: maxPixels)
    // 取第 0.1 秒，避开某些视频全黑的首帧
    let time = CMTime(seconds: 0.1, preferredTimescale: 600)
    guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else {
      return false
    }
    return writeJPEG(cg, to: dstURL)
  }

  /// 导出网页用的派生图。
  ///
  /// 三件事一次做完:
  ///   1. 解码（HEIC 也行）并缩到长边 maxPixels
  ///   2. **烤进方向** —— 用 ThumbnailWithTransform，网页端不用再管 EXIF Orientation
  ///   3. **不写任何元数据** —— GPS、时间、设备型号全部不进派生图
  ///
  /// 优先写 WebP（体积比 JPEG 小 25-35%）；系统不支持时自动退回 JPEG，
  /// 返回值里带上实际格式，调用方据此决定文件后缀。
  /// [forceJpeg] 为 true 时直接写 JPEG，不尝试 WebP ——
  /// 分享预览图必须是 JPEG，社交平台的抓取器（和 next/og）都不解 WebP。
  static func exportWeb(src: String, dst: String, maxPixels: Int,
                        quality: Double,
                        forceJpeg: Bool = false) -> [String: Any] {
    let srcURL = URL(fileURLWithPath: src)
    guard let source = CGImageSourceCreateWithURL(srcURL as CFURL, nil) else {
      return ["ok": false, "error": "无法读取源文件"]
    }
    let opts: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    guard let img = CGImageSourceCreateThumbnailAtIndex(
      source, 0, opts as CFDictionary) else {
      return ["ok": false, "error": "解码失败"]
    }

    var dstURL = URL(fileURLWithPath: dst)
    try? FileManager.default.createDirectory(
      at: dstURL.deletingLastPathComponent(),
      withIntermediateDirectories: true)

    // 只写图像本身，properties 里不放任何 EXIF/GPS
    let props: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: quality,
    ]

    var format = "webp"
    var out: CGImageDestination? = nil
    if !forceJpeg {
      out = CGImageDestinationCreateWithURL(
        dstURL as CFURL, "org.webmproject.webp" as CFString, 1, nil)
    }
    if out == nil {
      // 要么调用方指定了 JPEG，要么系统不支持写 WebP
      format = "jpeg"
      dstURL = dstURL.deletingPathExtension().appendingPathExtension("jpg")
      out = CGImageDestinationCreateWithURL(
        dstURL as CFURL, "public.jpeg" as CFString, 1, nil)
    }
    guard let dest = out else {
      return ["ok": false, "error": "无法创建输出文件"]
    }
    CGImageDestinationAddImage(dest, img, props as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
      return ["ok": false, "error": "写入失败"]
    }

    let size = (try? FileManager.default
      .attributesOfItem(atPath: dstURL.path)[.size] as? Int) ?? 0
    return [
      "ok": true,
      "path": dstURL.path,
      "format": format,
      "width": img.width,
      "height": img.height,
      "bytes": size ?? 0,
    ]
  }

  /// 分析一张图，算出自动精选需要的几个信号。
  ///
  /// **输入的是已经生成好的缩略图**，不是原图 —— 480px 足够算这些指标，
  /// 而且省掉一次 HEIC 全尺寸解码，快一个数量级。
  ///
  /// 全部在本地算完，不联网、不上传。
  static func analyze(path: String) -> [String: Any] {
    var out: [String: Any] = [:]
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
      return out
    }

    // 统一缩到 64x64 灰度，后面几个指标都基于它算
    let n = 64
    var gray = [Float](repeating: 0, count: n * n)
    guard let ctx = CGContext(
      data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGImageAlphaInfo.none.rawValue),
      let buf = ctx.data else { return out }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
    let px = buf.bindMemory(to: UInt8.self, capacity: n * n)
    for i in 0..<(n * n) { gray[i] = Float(px[i]) / 255.0 }

    // 亮度: 均值。过曝或欠曝会靠近 0 或 1
    out["brightness"] = Double(gray.reduce(0, +) / Float(n * n))

    // 清晰度: 拉普拉斯算子的方差。模糊和手抖的照片这个值很低
    var lap = [Float]()
    lap.reserveCapacity((n - 2) * (n - 2))
    for y in 1..<(n - 1) {
      for x in 1..<(n - 1) {
        let v = 4 * gray[y * n + x]
          - gray[(y - 1) * n + x] - gray[(y + 1) * n + x]
          - gray[y * n + x - 1] - gray[y * n + x + 1]
        lap.append(v)
      }
    }
    if !lap.isEmpty {
      let mean = lap.reduce(0, +) / Float(lap.count)
      let variance = lap.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) }
        / Float(lap.count)
      // 乘个大系数只是为了让数值好读，比较时用的是相对排名
      out["sharpness"] = Double(variance * 10000)
    }

    // 感知哈希 dHash: 缩到 9x8，比较左右相邻像素，得到 64 位
    out["phash"] = dHash(cg)

    // 人脸数: Vision 框架，完全本地
    let req = VNDetectFaceRectanglesRequest()
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    try? handler.perform([req])
    out["faceCount"] = req.results?.count ?? 0

    return out
  }

  /// dHash: 9x8 灰度，逐行比较相邻像素的明暗，共 64 位，输出 16 位十六进制。
  /// 对缩放、轻微调色都稳定，正适合判断"是不是同一张"。
  private static func dHash(_ image: CGImage) -> String {
    let w = 9, h = 8
    guard let ctx = CGContext(
      data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGImageAlphaInfo.none.rawValue),
      let buf = ctx.data else { return "" }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let px = buf.bindMemory(to: UInt8.self, capacity: w * h)

    var bits: UInt64 = 0
    var i = 0
    for y in 0..<h {
      for x in 0..<(w - 1) {
        if px[y * w + x] > px[y * w + x + 1] { bits |= (1 << UInt64(63 - i)) }
        i += 1
      }
    }
    return String(format: "%016llx", bits)
  }

  /// EXIF 方向值的旋转表。1..8 覆盖了正常与镜像两条链。
  /// 顺时针 90 度: 1->6->3->8->1（正常）, 2->7->4->5->2（镜像）
  private static let cwTable: [UInt32: UInt32] =
    [1: 6, 2: 7, 3: 8, 4: 5, 5: 2, 6: 3, 7: 4, 8: 1]
  private static let ccwTable: [UInt32: UInt32] =
    [1: 8, 8: 3, 3: 6, 6: 1, 2: 5, 5: 4, 4: 7, 7: 2]

  /// 旋转照片 90 度并写回原文件。
  ///
  /// 关键: **不重新编码像素**。只改 EXIF 的方向标记，
  /// 用 CGImageDestinationAddImageFromSource 把原始压缩数据原样拷过去 ——
  /// 所以画质零损失、速度极快，HEIC 和 JPEG 都适用。
  ///
  /// 拍摄时间不受影响: EXIF 属性整体复制，只覆盖方向；
  /// 文件修改时间在写完后恢复成原值。
  static func rotate(path: String, clockwise: Bool) -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    let fm = FileManager.default

    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let uti = CGImageSourceGetType(src) else {
      return ["ok": false, "error": "无法读取这个文件"]
    }
    // 视频不能这样旋转
    if (uti as String).hasPrefix("public.movie")
        || (uti as String).contains("quicktime") {
      return ["ok": false, "error": "视频暂不支持旋转"]
    }

    var props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil)
      as? [CFString: Any]) ?? [:]
    let cur = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
    let next = (clockwise ? cwTable[cur] : ccwTable[cur]) ?? 1
    props[kCGImagePropertyOrientation] = next

    let mtime = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date

    let tmp = url.deletingLastPathComponent()
      .appendingPathComponent(".tv_rot_" + url.lastPathComponent)
    guard let dest = CGImageDestinationCreateWithURL(
      tmp as CFURL, uti, 1, nil) else {
      return ["ok": false, "error": "无法写入临时文件"]
    }
    CGImageDestinationAddImageFromSource(dest, src, 0, props as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
      try? fm.removeItem(at: tmp)
      return ["ok": false, "error": "写入失败"]
    }

    do {
      _ = try fm.replaceItemAt(url, withItemAt: tmp)
    } catch {
      try? fm.removeItem(at: tmp)
      return ["ok": false, "error": "替换原文件失败: \(error.localizedDescription)"]
    }
    // 恢复文件修改时间 —— 库里按拍摄时间排序依赖它
    if let m = mtime {
      try? fm.setAttributes([.modificationDate: m], ofItemAtPath: path)
    }
    return ["ok": true, "orientation": Int(next)]
  }

  static func writeJPEG(_ image: CGImage, to dstURL: URL) -> Bool {
    try? FileManager.default.createDirectory(
      at: dstURL.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    guard let out = CGImageDestinationCreateWithURL(
      dstURL as CFURL, "public.jpeg" as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(out, image, [
      kCGImageDestinationLossyCompressionQuality: 0.82,
    ] as CFDictionary)
    return CGImageDestinationFinalize(out)
  }
}

// MARK: - ICDeviceBrowserDelegate

extension PhoneBridge: ICDeviceBrowserDelegate {
  func deviceBrowser(
    _ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool
  ) {
    guard let cam = device as? ICCameraDevice else { return }
    let id = cam.uuidString ?? cam.name ?? UUID().uuidString
    cameras[id] = cam
    channel.invokeMethod("onDevicesChanged", arguments: deviceList())
  }

  func deviceBrowser(
    _ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool
  ) {
    if let cam = device as? ICCameraDevice {
      let id = cam.uuidString ?? cam.name ?? ""
      cameras.removeValue(forKey: id)
    }
    channel.invokeMethod("onDevicesChanged", arguments: deviceList())
  }
}

// MARK: - ICDeviceDelegate / ICCameraDeviceDelegate

extension PhoneBridge: ICCameraDeviceDelegate {
  func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
    guard let result = openResult else { return }
    openResult = nil
    if let error = error {
      result(FlutterError(
        code: "OPEN_FAILED",
        message: "打开设备失败: \(error.localizedDescription)。请在 iPhone 上点「信任此电脑」并解锁屏幕。",
        details: nil))
      return
    }
    let cam = device as? ICCameraDevice
    result(["ready": true, "itemCount": cam?.mediaFiles?.count ?? 0])
  }

  func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}

  func didRemove(_ device: ICDevice) {
    if let cam = device as? ICCameraDevice {
      cameras.removeValue(forKey: cam.uuidString ?? cam.name ?? "")
    }
  }

  /// ICDeviceDelegate 的（可选）就绪回调
  func deviceDidBecomeReady(_ device: ICDevice) {
    channel.invokeMethod("onDevicesChanged", arguments: deviceList())
  }

  /// ICCameraDeviceDelegate 的**必需**方法 —— 内容目录读完才是真的可以列文件了。
  /// 注意这个和上面那个同名但不同协议，之前就是漏了这个导致不满足协议。
  func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
    channel.invokeMethod("onDevicesChanged", arguments: deviceList())
  }

  func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {}
  func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
  func cameraDevice(
    _ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?,
    for item: ICCameraItem, error: Error?) {}
  func cameraDevice(
    _ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?,
    for item: ICCameraItem, error: Error?) {}
  func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
  func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
  func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
  func cameraDevice(_ camera: ICCameraDevice, didCompleteDeleteFilesWithError error: Error?) {}
  func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}
  func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}
}

// MARK: - 下载委托

extension PhoneBridge: ICCameraDeviceDownloadDelegate {}
