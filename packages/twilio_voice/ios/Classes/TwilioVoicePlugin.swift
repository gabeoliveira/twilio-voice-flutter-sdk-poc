import Flutter
import UIKit
import AVFoundation
import TwilioVoice

/**
 * iOS side of the Twilio Voice Flutter wrapper.
 *
 * Outbound-only. `CallDelegate` is where incoming-call handling (CallKit +
 * pushRegistry) would later hook in, without changing the Dart channel contract.
 */
public class TwilioVoicePlugin: NSObject, FlutterPlugin, FlutterStreamHandler, CallDelegate {

  private var eventSink: FlutterEventSink?
  private var activeCall: Call?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = TwilioVoicePlugin()
    let methodChannel = FlutterMethodChannel(name: "twilio_voice", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    let eventChannel = FlutterEventChannel(name: "twilio_voice/events", binaryMessenger: registrar.messenger())
    eventChannel.setStreamHandler(instance)
  }

  // MARK: - FlutterStreamHandler
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func emit(_ state: String, message: String? = nil, callSid: String? = nil) {
    DispatchQueue.main.async {
      self.eventSink?(["state": state, "message": message as Any, "callSid": callSid as Any])
    }
  }

  // MARK: - MethodChannel
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestMicPermission":
      requestMicPermission(result)
    case "connect":
      connect(call.arguments as? [String: Any], result: result)
    case "disconnect":
      activeCall?.disconnect()
      result(nil)
    case "setMuted":
      let muted = (call.arguments as? [String: Any])?["muted"] as? Bool ?? false
      activeCall?.isMuted = muted
      result(nil)
    case "setSpeaker":
      let on = (call.arguments as? [String: Any])?["on"] as? Bool ?? false
      setSpeaker(on)
      result(nil)
    case "sendDigits":
      let digits = (call.arguments as? [String: Any])?["digits"] as? String ?? ""
      activeCall?.sendDigits(digits)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func connect(_ args: [String: Any]?, result: @escaping FlutterResult) {
    guard let token = args?["accessToken"] as? String, !token.isEmpty else {
      result(FlutterError(code: "NO_TOKEN", message: "accessToken is required", details: nil))
      return
    }
    let to = args?["to"] as? String ?? ""

    // Route audio for a voice call.
    try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat)

    let connectOptions = ConnectOptions(accessToken: token) { builder in
      // Forwarded to the TwiML App as call parameters; <Dial> uses `To`.
      builder.params = ["To": to]
    }
    emit("connecting")
    activeCall = TwilioVoiceSDK.connect(options: connectOptions, delegate: self)
    result(nil)
  }

  private func setSpeaker(_ on: Bool) {
    let session = AVAudioSession.sharedInstance()
    try? session.overrideOutputAudioPort(on ? .speaker : .none)
  }

  private func requestMicPermission(_ result: @escaping FlutterResult) {
    switch AVAudioSession.sharedInstance().recordPermission {
    case .granted:
      result(true)
    case .denied:
      result(false)
    case .undetermined:
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        DispatchQueue.main.async { result(granted) }
      }
    @unknown default:
      result(false)
    }
  }

  // MARK: - CallDelegate
  public func callDidStartRinging(call: Call) {
    emit("ringing", callSid: call.sid)
  }

  public func callDidConnect(call: Call) {
    activeCall = call
    emit("connected", callSid: call.sid)
  }

  public func call(call: Call, isReconnectingWithError error: Error) {
    emit("reconnecting", message: error.localizedDescription, callSid: call.sid)
  }

  public func callDidReconnect(call: Call) {
    emit("connected", callSid: call.sid)
  }

  public func callDidFailToConnect(call: Call, error: Error) {
    activeCall = nil
    emit("error", message: error.localizedDescription, callSid: call.sid)
  }

  public func callDidDisconnect(call: Call, error: Error?) {
    activeCall = nil
    emit("disconnected", message: error?.localizedDescription, callSid: call.sid)
  }
}
