import 'dart:async';
import 'dart:js' as js;
import 'package:strudel_dart/strudel_dart.dart';
import 'control_support.dart';

class AudioEngine {
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await _callBridge('init');
    _initialized = true;
  }

  Future<void> play(Hap hap) async {
    // Web playback is handled by the JS Strudel engine.
  }

  Future<void> evalCode(String code) async {
    await _callBridge('eval', [code]);
  }

  Future<void> stopAll() async {
    await _callBridge('hush');
  }

  void setControlGateMode(ControlGateMode mode) {}

  void dispose() {}
}

Future<void> _callBridge(String method, [List<Object?> args = const []]) async {
  final bridge = await _waitForBridge();
  final jsBridge = _asJsObject(bridge);
  final result = jsBridge.callMethod(method, args);
  await _awaitMaybePromise(result);
}

Future<Object> _waitForBridge({
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final bridge = js.context['strudelBridge'];
    if (bridge != null) return bridge;
    await Future.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('strudelBridge is not available.');
}

js.JsObject _asJsObject(Object value) {
  if (value is js.JsObject) return value;
  return js.JsObject.fromBrowserObject(value);
}

Future<void> _awaitMaybePromise(Object? result) async {
  if (result is! js.JsObject) return;
  if (!result.hasProperty('then')) return;
  // Fire-and-forget; avoid interop helpers that aren't available in this SDK.
  return;
}
