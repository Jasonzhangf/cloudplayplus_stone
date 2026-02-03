import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var loopbackMode = false
  
  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Check for loopback mode via environment variable
    if let loopbackEnv = ProcessInfo.processInfo.environment["LOOPBACK_MODE"],
       loopbackEnv == "host" || loopbackEnv == "controller" {
      loopbackMode = true
      // Make app run in background without appearing in Dock
      NSApp.setActivationPolicy(.accessory)
      
      // Hide all windows immediately
      if let window = NSApp.windows.first {
        window.setIsVisible(false)
        window.orderOut(nil)
      }
    }
    // Allow multiple loopback roles (host/controller) to run side-by-side.
    // Only applies in loopback mode so regular app keeps single-instance behavior.
    if loopbackMode {
      _allowMultipleInstances()
    }
    super.applicationDidFinishLaunching(notification)
  }

  private func _allowMultipleInstances() {
    // Also set in Info.plist, but we set it here to be safe for debug runs.
    UserDefaults.standard.set(false, forKey: "LSMultipleInstancesProhibited")
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // In loopback mode, don't terminate when window closes (since we hide it)
    return !loopbackMode
  }
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
