import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    
    let channel = FlutterMethodChannel(name: "com.darianmavgo.sqliter/file_open", binaryMessenger: flutterViewController.engine.binaryMessenger)
    if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
        appDelegate.methodChannel = channel
        
        channel.setMethodCallHandler({ (call, result) in
            if call.method == "getPendingFile" {
                result(appDelegate.pendingOpenFile)
                appDelegate.pendingOpenFile = nil
            } else {
                result(FlutterMethodNotImplemented)
            }
        })
    }

    super.awakeFromNib()
  }
}
