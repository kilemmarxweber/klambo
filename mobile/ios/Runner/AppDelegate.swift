import AudioToolbox
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "klambo/sounds",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "startRingtone":
        SystemRingtone.shared.start()
        result(true)
      case "stopRingtone":
        SystemRingtone.shared.stop()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// Sonnerie d’appel = alerte système (iOS n’expose pas le fichier de sonnerie choisi).
private final class SystemRingtone {
  static let shared = SystemRingtone()
  private var timer: Timer?
  private let soundId: SystemSoundID = 1007

  func start() {
    stop()
    AudioServicesPlayAlertSound(soundId)
    timer = Timer.scheduledTimer(withTimeInterval: 2.8, repeats: true) { [soundId] _ in
      AudioServicesPlayAlertSound(soundId)
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }
}
