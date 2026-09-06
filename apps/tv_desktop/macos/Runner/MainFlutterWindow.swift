import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // 默认窗口给足。这是一个同时要放照片网格、地图和一条工具栏的界面，
    // Flutter 模板默认的 800x600 一打开就挤，工具栏直接溢出。
    // 屏幕小的时候按可用面积收缩，不要开出一个比屏幕还大的窗口。
    let desired = NSSize(width: 1500, height: 980)
    let visible = self.screen?.visibleFrame.size
      ?? NSScreen.main?.visibleFrame.size
      ?? desired
    let size = NSSize(
      width: min(desired.width, visible.width - 40),
      height: min(desired.height, visible.height - 40))
    self.setContentSize(size)
    self.contentMinSize = NSSize(width: 1100, height: 720)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    PhoneBridge.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
