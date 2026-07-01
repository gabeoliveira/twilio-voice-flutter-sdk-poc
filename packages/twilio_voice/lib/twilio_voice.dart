import 'package:flutter/services.dart';

/// High-level state of an outbound call, surfaced to Dart from the native SDKs.
enum CallState {
  connecting,
  ringing,
  connected,
  reconnecting,
  disconnected,
  error,
}

/// A single call lifecycle event emitted by the native Twilio Voice SDK.
class CallEvent {
  const CallEvent(this.state, {this.message, this.callSid});

  final CallState state;
  final String? message;
  final String? callSid;

  factory CallEvent.fromMap(Map<dynamic, dynamic> map) {
    final state = CallState.values.firstWhere(
      (s) => s.name == map['state'],
      orElse: () => CallState.error,
    );
    return CallEvent(
      state,
      message: map['message'] as String?,
      callSid: map['callSid'] as String?,
    );
  }

  @override
  String toString() =>
      'CallEvent(${state.name}${message != null ? ', $message' : ''})';
}

/// Thin Flutter wrapper over the native Twilio Voice SDKs
/// (`com.twilio:voice-android` / `TwilioVoice` xcframework).
///
/// Outbound-only for now; the native layer and event model are structured so an
/// inbound (incoming-call) flow can be layered on later without changing this API.
class TwilioVoice {
  TwilioVoice._();
  static final TwilioVoice instance = TwilioVoice._();

  static const MethodChannel _methods = MethodChannel('twilio_voice');
  static const EventChannel _events = EventChannel('twilio_voice/events');

  Stream<CallEvent>? _eventStream;

  /// Broadcast stream of call lifecycle events from the native SDK.
  Stream<CallEvent> get onCallEvent {
    _eventStream ??= _events
        .receiveBroadcastStream()
        .map((e) => CallEvent.fromMap(e as Map<dynamic, dynamic>));
    return _eventStream!;
  }

  /// Requests microphone permission natively. Returns true if granted.
  Future<bool> requestMicrophonePermission() async {
    final granted = await _methods.invokeMethod<bool>('requestMicPermission');
    return granted ?? false;
  }

  /// Places an outbound call.
  ///
  /// [accessToken] is a Twilio Access Token (minted by the token server) with a
  /// Voice grant. [to] is forwarded to the TwiML App as the `To` parameter, where
  /// the `<Dial>` verb decides what actually gets dialed (a PSTN number here).
  Future<void> connect({
    required String accessToken,
    required String to,
  }) {
    return _methods.invokeMethod<void>('connect', {
      'accessToken': accessToken,
      'to': to,
    });
  }

  /// Ends the active call.
  Future<void> disconnect() => _methods.invokeMethod<void>('disconnect');

  /// Mutes or unmutes the local microphone on the active call.
  Future<void> setMuted(bool muted) =>
      _methods.invokeMethod<void>('setMuted', {'muted': muted});

  /// Toggles the speaker on/off for the active call.
  Future<void> setSpeaker(bool on) =>
      _methods.invokeMethod<void>('setSpeaker', {'on': on});

  /// Sends DTMF digits on the active call.
  Future<void> sendDigits(String digits) =>
      _methods.invokeMethod<void>('sendDigits', {'digits': digits});
}
