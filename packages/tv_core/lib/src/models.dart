import 'dart:convert';

/// 贴在照片上的标签。所有"分类"（旅行 / 相册 / 人物 / 地点 / 关键词）
/// 都是同一种东西，多维度共存且不产生任何文件副本。
class Tag implements Comparable<Tag> {
  final String kind;
  final String value;

  const Tag(this.kind, this.value);

  factory Tag.fromJson(Map<String, dynamic> j) =>
      Tag(j['kind'] as String, j['value'] as String);

  Map<String, dynamic> toJson() => {'kind': kind, 'value': value};

  @override
  int compareTo(Tag other) {
    final k = kind.compareTo(other.kind);
    return k != 0 ? k : value.compareTo(other.value);
  }

  @override
  bool operator ==(Object other) =>
      other is Tag && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => '$kind:$value';
}

/// 一张照片的元数据。`id` 是内容哈希，与文件名和路径无关 —— 这是自愈能力的基础。
class PhotoRecord {
  final String id;
  final DateTime takenAt;
  final int bytes;
  final String origFilename;

  final double? lat;
  final double? lon;
  final int? width;
  final int? height;
  final String? mime;
  final String? device;

  /// Live Photo 动态部分的 id。丢了它就丢了实况。
  final String? liveVideoId;

  /// iOS 编辑后的版本指向原片的 id；UI 上折叠成一张。
  final String? editOf;

  final bool isScreenshot;

  // ---- 自动精选用的信号（导入时由原生层一次算出，存进 sidecar）----

  /// 清晰度: 缩略图的拉普拉斯方差，越大越锐利。模糊和手抖的照片会很低。
  final double? sharpness;

  /// 亮度均值 0..1。过曝或欠曝的照片会靠近两端。
  final double? brightness;

  /// 感知哈希（dHash, 16 位十六进制）。用汉明距离判断"是不是同一张"，
  /// 这是去掉连拍和同一景物重复拍摄的关键。
  final String? phash;

  /// 人脸数量。有人的照片通常更值得放进回顾。
  final int? faceCount;

  final List<Tag> tags;

  PhotoRecord({
    required this.id,
    required this.takenAt,
    required this.bytes,
    required this.origFilename,
    this.lat,
    this.lon,
    this.width,
    this.height,
    this.mime,
    this.device,
    this.liveVideoId,
    this.editOf,
    this.isScreenshot = false,
    this.sharpness,
    this.brightness,
    this.phash,
    this.faceCount,
    List<Tag>? tags,
  }) : tags = List.unmodifiable((tags ?? const <Tag>[]).toList()..sort());

  bool get hasLocation => lat != null && lon != null;

  bool get isPortrait => (width ?? 0) > 0 && (height ?? 0) > (width ?? 0);
  bool get isLandscape => (width ?? 0) > (height ?? 0);
  int get pixels => (width ?? 0) * (height ?? 0);

  PhotoRecord copyWith({List<Tag>? tags, String? liveVideoId, String? editOf}) =>
      PhotoRecord(
        id: id,
        takenAt: takenAt,
        bytes: bytes,
        origFilename: origFilename,
        lat: lat,
        lon: lon,
        width: width,
        height: height,
        mime: mime,
        device: device,
        liveVideoId: liveVideoId ?? this.liveVideoId,
        editOf: editOf ?? this.editOf,
        isScreenshot: isScreenshot,
        sharpness: sharpness,
        brightness: brightness,
        phash: phash,
        faceCount: faceCount,
        tags: tags ?? this.tags,
      );

  /// 合并同一张照片的两份记录（例如重新导入时补上了 GPS）。
  /// 规则: 非空覆盖空，tag 取并集 —— 永不丢信息。
  PhotoRecord mergeWith(PhotoRecord other) {
    assert(other.id == id, 'mergeWith 只能合并同一个 id');
    final merged = <Tag>{...tags, ...other.tags}.toList()..sort();
    return PhotoRecord(
      id: id,
      takenAt: takenAt,
      bytes: bytes,
      origFilename: origFilename,
      lat: lat ?? other.lat,
      lon: lon ?? other.lon,
      width: width ?? other.width,
      height: height ?? other.height,
      mime: mime ?? other.mime,
      device: device ?? other.device,
      liveVideoId: liveVideoId ?? other.liveVideoId,
      editOf: editOf ?? other.editOf,
      isScreenshot: isScreenshot || other.isScreenshot,
      sharpness: sharpness ?? other.sharpness,
      brightness: brightness ?? other.brightness,
      phash: phash ?? other.phash,
      faceCount: faceCount ?? other.faceCount,
      tags: merged,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'taken_at': takenAt.toUtc().toIso8601String(),
      'bytes': bytes,
      'orig_filename': origFilename,
    };
    void put(String k, Object? v) {
      if (v != null) m[k] = v;
    }

    put('lat', lat);
    put('lon', lon);
    put('width', width);
    put('height', height);
    put('mime', mime);
    put('device', device);
    put('live_video_id', liveVideoId);
    put('edit_of', editOf);
    put('sharpness', sharpness);
    put('brightness', brightness);
    put('phash', phash);
    put('face_count', faceCount);
    if (isScreenshot) m['is_screenshot'] = true;
    if (tags.isNotEmpty) m['tags'] = tags.map((t) => t.toJson()).toList();
    return m;
  }

  factory PhotoRecord.fromJson(Map<String, dynamic> j) => PhotoRecord(
        id: j['id'] as String,
        takenAt: DateTime.parse(j['taken_at'] as String).toLocal(),
        bytes: (j['bytes'] as num).toInt(),
        origFilename: j['orig_filename'] as String,
        lat: (j['lat'] as num?)?.toDouble(),
        lon: (j['lon'] as num?)?.toDouble(),
        width: (j['width'] as num?)?.toInt(),
        height: (j['height'] as num?)?.toInt(),
        mime: j['mime'] as String?,
        device: j['device'] as String?,
        liveVideoId: j['live_video_id'] as String?,
        editOf: j['edit_of'] as String?,
        isScreenshot: j['is_screenshot'] as bool? ?? false,
        sharpness: (j['sharpness'] as num?)?.toDouble(),
        brightness: (j['brightness'] as num?)?.toDouble(),
        phash: j['phash'] as String?,
        faceCount: (j['face_count'] as num?)?.toInt(),
        tags: (j['tags'] as List?)
            ?.map((e) => Tag.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  @override
  String toString() => 'PhotoRecord($id, $origFilename, $takenAt)';
}

String prettyJson(Object? o) =>
    const JsonEncoder.withIndent('  ').convert(o);
