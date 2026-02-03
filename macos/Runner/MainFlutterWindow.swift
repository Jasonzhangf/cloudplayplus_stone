import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let isLoopback: Bool = {
      if let loopbackEnv = ProcessInfo.processInfo.environment["LOOPBACK_MODE"] {
        return loopbackEnv == "host" || loopbackEnv == "controller"
      }
      return false
    }()

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    if isLoopback {
      // Keep window fully hidden while still initializing Flutter engine/plugins.
      self.isOpaque = false
      self.hasShadow = false
      self.alphaValue = 0.0
      self.ignoresMouseEvents = true
      self.orderOut(nil)
    }
  }
}
