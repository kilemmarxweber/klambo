import AudioToolbox
import CallKit
import CryptoKit
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

    let callKit = FlutterMethodChannel(
      name: "klambo/callkit",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    CallKitBridge.shared.bind(callKit)
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

/// Sonnerie système iOS quand l'app est en mémoire. Le push VoIP reste hors de ce dépôt.
private final class CallKitBridge: NSObject, CXProviderDelegate {
  static let shared = CallKitBridge()
  private let provider: CXProvider
  private var channel: FlutterMethodChannel?
  private var callIds: [UUID: String] = [:]

  private override init() {
    let config = CXProviderConfiguration()
    config.supportsVideo = true
    config.maximumCallsPerCallGroup = 1
    config.supportedHandleTypes = [.generic]
    config.includesCallsInRecents = false
    provider = CXProvider(configuration: config)
    super.init()
    provider.setDelegate(self, queue: nil)
  }

  func bind(_ channel: FlutterMethodChannel) {
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any]
      let callId = args?["callId"] as? String ?? ""
      switch call.method {
      case "reportIncoming":
        let name = args?["name"] as? String ?? "Klambo"
        let video = args?["video"] as? Bool ?? false
        self.reportIncoming(callId: callId, name: name, video: video)
        result(true)
      case "end":
        self.end(callId: callId)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func reportIncoming(callId: String, name: String, video: Bool) {
    let uuid = uuidFrom(callId)
    callIds[uuid] = callId
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: name)
    update.localizedCallerName = name
    update.hasVideo = video
    provider.reportNewIncomingCall(with: uuid, update: update) { error in
      if let error {
        NSLog("[callkit] report failed %@", error.localizedDescription)
      }
    }
  }

  func end(callId: String) {
    let uuid = uuidFrom(callId)
    provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
    callIds.removeValue(forKey: uuid)
  }

  func providerDidReset(_ provider: CXProvider) {
    callIds.removeAll()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    let callId = callIds[action.callUUID] ?? ""
    channel?.invokeMethod("answered", arguments: ["callId": callId])
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    let callId = callIds[action.callUUID] ?? ""
    channel?.invokeMethod("ended", arguments: ["callId": callId])
    callIds.removeValue(forKey: action.callUUID)
    action.fulfill()
  }

  private func uuidFrom(_ callId: String) -> UUID {
    let digest = Array(SHA256.hash(data: Data(callId.utf8)).prefix(16))
    var bytes = digest
    if bytes.count == 16 {
      bytes[6] = (bytes[6] & 0x0F) | 0x40
      bytes[8] = (bytes[8] & 0x3F) | 0x80
    }
    let hex = bytes.map { String(format: "%02x", $0) }.joined()
    let formatted = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
    return UUID(uuidString: formatted) ?? UUID()
  }
}
