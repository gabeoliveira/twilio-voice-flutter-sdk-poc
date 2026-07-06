import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:twilio_voice/twilio_voice.dart';

/// Same token server as the native dialer (set via --dart-define=TOKEN_SERVER).
const String kTokenServerBaseUrl =
    String.fromEnvironment('TOKEN_SERVER', defaultValue: 'http://localhost:3000');
const String kIdentity = 'flutter-demo-user';

/// WebView + Twilio JS SDK dialer, instrumented to compare call-setup "load"
/// speed against the native path:
///  - **warm**: WebView + Device already alive → connect only.
///  - **cold**: reload the WebView (fresh JS parse + Device init + token) → connect.
/// The cold−warm gap is the "does loading the SDK each time hurt?" cost.
class WebViewDialerScreen extends StatefulWidget {
  const WebViewDialerScreen({super.key});

  @override
  State<WebViewDialerScreen> createState() => _WebViewDialerScreenState();
}

class _WebViewDialerScreenState extends State<WebViewDialerScreen> {
  InAppWebViewController? _controller;
  final _toController = TextEditingController(text: '+1');

  String _status = 'loading WebView…';
  bool _deviceReady = false;

  // Cold-path orchestration.
  final Stopwatch _coldSw = Stopwatch();
  bool _coldReloadPending = false;
  bool _awaitingReadyForCold = false;
  int? _webviewLoadMs;

  // Latest results (front-end = everything before the answer/media leg).
  String? _warmResult;
  String? _coldResult;

  @override
  void initState() {
    super.initState();
    // Prompt the OS-level mic permission up front; WKWebView getUserMedia needs it.
    TwilioVoice.instance.requestMicrophonePermission();
  }

  @override
  void dispose() {
    _toController.dispose();
    super.dispose();
  }

  String get _to => _toController.text.trim();

  void _registerHandlers(InAppWebViewController c) {
    c.addJavaScriptHandler(
      handlerName: 'ready',
      callback: (args) {
        final m = (args.isNotEmpty ? args.first : {}) as Map;
        if (m['ok'] == true) {
          _deviceReady = true;
          setState(() => _status = 'device ready');
          if (_awaitingReadyForCold) {
            _awaitingReadyForCold = false;
            c.evaluateJavascript(source: "placeCall('$_to','cold')");
          }
        } else {
          setState(() => _status = 'boot error: ${m['error']}');
        }
        return null;
      },
    );
    c.addJavaScriptHandler(
      handlerName: 'timing',
      callback: (args) {
        final m = Map<String, dynamic>.from((args.first as Map));
        _onTiming(m);
        return null;
      },
    );
  }

  int? _asInt(dynamic v) => v is num ? v.round() : null;

  void _onTiming(Map<String, dynamic> m) {
    final mode = m['mode'] as String? ?? '?';
    final token = _asInt(m['tokenMs']);
    final deviceInit = _asInt(m['deviceInitMs']);
    final ctr = _asInt(m['connectToRinging']);
    final rtc = _asInt(m['ringingToConnected']);
    final total = _asInt(m['total']);

    // Front-end = the SDK-controlled setup before the answer/media leg.
    int? frontEnd;
    if (mode == 'warm') {
      frontEnd = ctr; // Device + token reused; only signaling remains.
    } else {
      // cold = WebView load (Flutter) + token + Device init + connect→ringing.
      frontEnd = [_webviewLoadMs, token, deviceInit, ctr]
          .whereType<int>()
          .fold<int>(0, (a, b) => a + b);
    }

    final line = '[timing-webview-combined] mode=$mode '
        'webviewLoad=${_webviewLoadMs}ms token=${token}ms deviceInit=${deviceInit}ms '
        'connect->ringing=${ctr}ms frontEnd=${frontEnd}ms '
        'ringing->connected=${rtc}ms total=${total}ms';
    debugPrint(line);

    final summary = mode == 'warm'
        ? 'warm front-end: ${frontEnd ?? '…'} ms  (connect→ringing $ctr ms)'
        : 'cold front-end: ${frontEnd ?? '…'} ms  '
            '(webview $_webviewLoadMs + token $token + deviceInit $deviceInit + sig $ctr)';
    setState(() {
      _status = 'connected';
      if (mode == 'warm') {
        _warmResult = summary;
      } else {
        _coldResult = summary;
      }
    });
  }

  Future<void> _warmCall() async {
    if (!_deviceReady) {
      setState(() => _status = 'device not ready yet');
      return;
    }
    setState(() => _status = 'warm call…');
    await _controller?.evaluateJavascript(source: "placeCall('$_to','warm')");
  }

  Future<void> _coldCall() async {
    // Force a fresh WebView load → fresh JS parse + Device init + token.
    setState(() => _status = 'cold: reloading WebView…');
    _deviceReady = false;
    _coldReloadPending = true;
    _webviewLoadMs = null;
    _coldSw
      ..reset()
      ..start();
    await _controller?.reload();
  }

  Future<void> _hangUp() async =>
      _controller?.evaluateJavascript(source: 'hangup()');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebView + JS SDK (timing)')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _toController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Number to call (E.164)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Status: $_status'),
                if (_warmResult != null) Text('✔ $_warmResult'),
                if (_coldResult != null) Text('✔ $_coldResult'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _warmCall,
                        child: const Text('Call (warm)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: _coldCall,
                        child: const Text('Call (cold)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(onPressed: _hangUp, child: const Text('Hang up')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialFile: 'assets/webview_dialer.html',
              initialSettings: InAppWebViewSettings(
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                javaScriptEnabled: true,
              ),
              onWebViewCreated: (c) {
                _controller = c;
                _registerHandlers(c);
              },
              onPermissionRequest: (c, request) async {
                // Grant mic to the WebRTC getUserMedia request.
                return PermissionResponse(
                  resources: request.resources,
                  action: PermissionResponseAction.GRANT,
                );
              },
              onLoadStop: (c, url) async {
                if (_coldReloadPending) {
                  _coldReloadPending = false;
                  _webviewLoadMs = _coldSw.elapsedMilliseconds;
                  _awaitingReadyForCold = true;
                  await c.evaluateJavascript(
                      source: "boot('$kTokenServerBaseUrl','$kIdentity')");
                } else {
                  // Initial load → pre-warm the Device for the warm path.
                  await c.evaluateJavascript(
                      source: "boot('$kTokenServerBaseUrl','$kIdentity')");
                }
              },
              onConsoleMessage: (c, msg) => debugPrint('[webview] ${msg.message}'),
            ),
          ),
        ],
      ),
    );
  }
}
