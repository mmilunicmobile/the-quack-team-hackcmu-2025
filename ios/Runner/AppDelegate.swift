import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private var eventSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    let controller = window?.rootViewController as! FlutterViewController
    let eventChannel = FlutterEventChannel(name: "screen_events", binaryMessenger: controller.binaryMessenger)

    eventChannel.setStreamHandler(self)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

extension AppDelegate: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events

    NotificationCenter.default.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailable, object: nil, queue: .main) { _ in
        self.eventSink?("locked")
    }

    NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailable, object: nil, queue: .main) { _ in
        self.eventSink?("unlocked")
    }

    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NotificationCenter.default.removeObserver(self)
    eventSink = nil
    return nil
  }
}
