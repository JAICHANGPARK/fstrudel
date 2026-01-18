const String logKey = 'strudel.log';

int _debounceMs = 1000;
String? _lastMessage;
int _lastTimeMs = 0;

void errorLogger(Object error, {String origin = 'cyclist'}) {
  const bool isRelease = bool.fromEnvironment('dart.vm.product');
  if (!isRelease) {
    // Mirror JS behavior in dev: surface raw errors to the console.
    // ignore: avoid_print
    print(error);
  }
  logger('[$origin] error: $error');
}

void logger(String message, {String? type, Map<String, dynamic>? data}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  if (_lastMessage == message && now - _lastTimeMs < _debounceMs) {
    return;
  }
  _lastMessage = message;
  _lastTimeMs = now;
  // ignore: avoid_print
  print(message);
}
