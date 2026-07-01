import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:twilio_voice/twilio_voice.dart';

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

  bool get _inCall =>
      _state != null &&
      _state != CallState.disconnected &&
      _state != CallState.error;

  @override
  void initState() {
    super.initState();
    _sub = _twilio.onCallEvent.listen((e) {
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
      setState(() => _status = 'Fetching token…');
      final token = await _fetchToken();
      await _twilio.connect(accessToken: token, to: _toController.text.trim());
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _hangUp() => _twilio.disconnect();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Twilio Voice Wrapper')),
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
