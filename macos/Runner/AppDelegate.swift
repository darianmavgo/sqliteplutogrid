import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var methodChannel: FlutterMethodChannel?
  var pendingOpenFile: String?

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    if let channel = methodChannel {
      channel.invokeMethod("onFileOpened", arguments: filename)
    } else {
      pendingOpenFile = filename
    }
    return true
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
