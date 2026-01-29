import 'pattern.dart';

Pattern _speak(dynamic lang, dynamic voice, Pattern pat) {
  throw UnsupportedError(
    'speak() is not supported in the Dart/Flutter port. Use a platform TTS '
    'integration if you need speech output.',
  );
}

Pattern speak(dynamic lang, dynamic voice, Pattern pat) =>
    _speak(lang, voice, pat);

extension PatternSpeakExtension<T> on Pattern<T> {
  Pattern<T> speak(dynamic lang, [dynamic voice]) {
    return _speak(lang, voice, this).cast<T>();
  }
}
