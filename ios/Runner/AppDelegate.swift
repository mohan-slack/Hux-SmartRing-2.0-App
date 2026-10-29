import Flutter
import UIKit
import UserNotifications

// UIScene lifecycle (required when built with the iOS 27 SDK): plugins are
// registered on the implicit engine, not in didFinishLaunching.
// See https://docs.flutter.dev/release/breaking-changes/uiscenedelegate
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications: lets HUX nudges show and be tapped.
    // Must be set before launch finishes, so it stays here.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
