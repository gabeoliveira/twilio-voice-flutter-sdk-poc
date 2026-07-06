import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:twilio_voice/twilio_voice.dart';

import 'webview_dialer_screen.dart';

void main() => runApp(const DialerApp());

/// Where the token server runs. For a physical iOS device, set this to your
/// Mac's LAN IP (e.g. http://192.168.0.10:3000), not localhost.
const String kTokenServerBaseUrl =
    String.fromEnvironment('TOKEN_SERVER', defaultValue: 'http://localhost:3000');

/// The client identity to mint a token for (must match the TwiML App routing).
const String kIdentity = 'flutter-demo-user';

class DialerApp extends StatelessWidget {
  const DialerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Twilio Voice Wrapper Demo',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const DialerScreen(),
    );
  }
}

class DialerScreen extends StatefulWidget {
  const DialerScreen({super.key});

  @override
  State<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends State<DialerScreen> {
  final _twilio = TwilioVoice.instance;
  final _toController = TextEditingController(text: '+1');
  StreamSubscription<CallEvent>? _sub;

  CallState? _state;
  String _status = 'Idle';
  bool _muted = false;
  bool _speaker = false;

  // --- Call-setup timing instrumentation (native path) ---
  // Measures the deterministic pipeline after mic permission is granted:
  //   tap → token fetched → connect() invoked → `ringing` → `connected`.
  // The mic-permission prompt (user-gated, one-time) is intentionally excluded.
  final Stopwatch _sw = Stopwatch();
  int? _tTokenMs; // token fetch round-trip
  int? _tConnectMs; // connect() returned (native connect invoked)
  int? _tRingingMs; // `ringing` event
  int? _tConnectedMs; // `connected` event (media established)

  bool get _inCall =>
      _state != null &&
      _state != CallState.disconnected &&
      _state != CallState.error;

  @override
  void initState() {
    super.initState();
    _sub = _twilio.onCallEvent.listen((e) {
      if (_sw.isRunning) {
        if (e.state == CallState.ringing && _tRingingMs == null) {
          _tRingingMs = _sw.elapsedMilliseconds;
        }
        if (e.state == CallState.connected && _tConnectedMs == null) {
          _tConnectedMs = _sw.elapsedMilliseconds;
          _sw.stop();
          _logTimings('connected');
        }
      }
      setState(() {
        _state = e.state;
        _status = e.message == null ? e.state.name : '${e.state.name} — ${e.message}';
        if (!_inCall) {
          _muted = false;
          _speaker = false;
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _toController.dispose();
    super.dispose();
  }

  /// Emits one machine-parseable line per call so timings can be scraped from
  /// `flutter run` logs and averaged across runs.
  void _logTimings(String phase) {
    final connectToRinging =
        (_tRingingMs != null && _tConnectMs != null) ? _tRingingMs! - _tConnectMs! : null;
    final ringingToConnected =
        (_tConnectedMs != null && _tRingingMs != null) ? _tConnectedMs! - _tRingingMs! : null;
    debugPrint('[timing] phase=$phase '
        'token=${_tTokenMs}ms connectInvoked=${_tConnectMs}ms '
        'ringing=${_tRingingMs}ms connected=${_tConnectedMs}ms '
        'connect->ringing=${connectToRinging}ms ringing->connected=${ringingToConnected}ms '
        'total=${_tConnectedMs}ms');
  }

  Future<String> _fetchToken() async {
    final uri = Uri.parse('$kTokenServerBaseUrl/token?identity=$kIdentity');
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('Token server ${res.statusCode}: ${res.body}');
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['token'] as String;
  }

  Future<void> _call() async {
    try {
      final granted = await _twilio.requestMicrophonePermission();
      if (!granted) {
        setState(() => _status = 'Microphone permission denied');
        return;
      }
      // Reset timing marks and start the clock AFTER permission (excludes the
      // user-gated prompt, so runs are comparable).
      setState(() {
        _tTokenMs = _tConnectMs = _tRingingMs = _tConnectedMs = null;
        _status = 'Fetching token…';
      });
      _sw
        ..reset()
        ..start();

      final token = await _fetchToken();
      _tTokenMs = _sw.elapsedMilliseconds;

      await _twilio.connect(accessToken: token, to: _toController.text.trim());
      _tConnectMs = _sw.elapsedMilliseconds;
      _logTimings('connect-invoked');
    } catch (e) {
      _sw.stop();
      setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _hangUp() => _twilio.disconnect();

  Widget? _timingsPanel() {
    if (_tTokenMs == null) return null;
    final connectToRinging =
        (_tRingingMs != null && _tConnectMs != null) ? _tRingingMs! - _tConnectMs! : null;
    final ringingToConnected =
        (_tConnectedMs != null && _tRingingMs != null) ? _tConnectedMs! - _tRingingMs! : null;
    String ms(int? v) => v == null ? '…' : '$v ms';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Call-setup timing', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _timingRow('Token fetch', ms(_tTokenMs)),
            _timingRow('Connect → Ringing', ms(connectToRinging)),
            _timingRow('Ringing → Connected', ms(ringingToConnected)),
            const Divider(),
            _timingRow('Total (token → connected)', ms(_tConnectedMs), bold: true),
          ],
        ),
      ),
    );
  }

  Widget _timingRow(String label, String value, {bool bold = false}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timings = _timingsPanel();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Twilio Voice Wrapper'),
        actions: [
          IconButton(
            tooltip: 'WebView + JS SDK timing',
            icon: const Icon(Icons.public),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WebViewDialerScreen()),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _toController,
              enabled: !_inCall,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Number to call (E.164)',
                hintText: '+15551234567',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: Icon(_inCall ? Icons.call : Icons.call_end,
                    color: _inCall ? Colors.green : Colors.grey),
                title: Text('Status: $_status'),
              ),
            ),
            if (timings != null) ...[const SizedBox(height: 12), timings],
            const SizedBox(height: 24),
            if (!_inCall)
              FilledButton.icon(
                onPressed: _call,
                icon: const Icon(Icons.call),
                label: const Text('Call'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: Colors.green,
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _twilio.setMuted(!_muted);
                        setState(() => _muted = !_muted);
                      },
                      icon: Icon(_muted ? Icons.mic_off : Icons.mic),
                      label: Text(_muted ? 'Unmute' : 'Mute'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _twilio.setSpeaker(!_speaker);
                        setState(() => _speaker = !_speaker);
                      },
                      icon: Icon(_speaker ? Icons.volume_up : Icons.volume_down),
                      label: Text(_speaker ? 'Speaker On' : 'Speaker Off'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _hangUp,
                icon: const Icon(Icons.call_end),
                label: const Text('Hang Up'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: Colors.red,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
