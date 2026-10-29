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

    // hux/storage: a database folder that is EXCLUDED from iCloud
    // backup (health data must not go to iCloud — App Store 5.1.3).
    // Used by lib/core/storage/db_location.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HuxStorage") {
      let channel = FlutterMethodChannel(name: "hux/storage", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "privateDbDir" else {
          result(FlutterMethodNotImplemented)
          return
        }
        do {
          let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
          var dir = base.appendingPathComponent("hux-db", isDirectory: true)
          try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          try dir.setResourceValues(values)
          result(dir.path)
        } catch {
          result(FlutterError(code: "dir", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}
