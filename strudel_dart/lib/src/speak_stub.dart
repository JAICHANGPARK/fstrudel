import 'pattern.dart';

Pattern speak(dynamic lang, dynamic voice, Pattern pat) {
  throw UnsupportedError(
    'speak() is not supported in the Dart/Flutter port. Use a platform TTS '
    'integration if you need speech output.',
  );
}

extension PatternSpeakExtension<T> on Pattern<T> {
  Pattern<T> speak(dynamic lang, [dynamic voice]) {
    return speak(lang, voice, this).cast<T>();
  }
}
