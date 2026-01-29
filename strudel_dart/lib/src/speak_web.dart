import 'dart:html' as html;
import 'pattern.dart';

void _triggerSpeech(String words, String lang, dynamic voice) {
  final synth = html.window.speechSynthesis;
  if (synth == null) {
    throw UnsupportedError('SpeechSynthesis is not available in this browser.');
  }
  synth.cancel();
  final utterance = html.SpeechSynthesisUtterance(words)..lang = lang;
  final voices = synth
      .getVoices()
      .where((v) => (v.lang ?? '').contains(lang))
      .toList();
  if (voice is num && voices.isNotEmpty) {
    utterance.voice = voices[voice.toInt() % voices.length];
  } else if (voice is String) {
    final match = voices.where((v) => v.name == voice).toList();
    if (match.isNotEmpty) {
      utterance.voice = match.first;
    }
  }
  synth.speak(utterance);
}

Pattern _speak(dynamic lang, dynamic voice, Pattern pat) {
  final language = (lang ?? 'en').toString();
  return pat.onTrigger((hap, _now, _cps, _targetTime) {
    final words = hap.value.toString();
    _triggerSpeech(words, language, voice);
  }, false);
}

Pattern speak(dynamic lang, dynamic voice, Pattern pat) =>
    _speak(lang, voice, pat);

extension PatternSpeakExtension<T> on Pattern<T> {
  Pattern<T> speak(dynamic lang, [dynamic voice]) {
    return _speak(lang, voice, this).cast<T>();
  }
}
