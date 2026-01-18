import 'package:fraction/fraction.dart' as f;
import 'timespan.dart';

class Hap<T> {
  final TimeSpan? whole;
  final TimeSpan part;
  final T value;
  final Map<String, dynamic> context;
  final bool stateful;

  final DateTime? scheduledTime;

  Hap(
    this.whole,
    this.part,
    this.value, {
    this.context = const {},
    this.stateful = false,
    this.scheduledTime,
  });

  f.Fraction get duration {
    // In Strudel, value can have a duration property.
    // In Dart, we might need a more type-safe way to handle this,
    // but for now, we'll stick to a simple implementation.
    return whole != null
        ? (whole!.end - whole!.begin)
        : (part.end - part.begin);
  }

  f.Fraction get endClipped {
    return (whole?.begin ?? part.begin) + duration;
  }

  TimeSpan wholeOrPart() => whole ?? part;

  Hap<T> withSpan(TimeSpan Function(TimeSpan) func) {
    final newWhole = whole != null ? func(whole!) : null;
    return Hap(
      newWhole,
      func(part),
      value,
      context: context,
      stateful: stateful,
      scheduledTime: scheduledTime,
    );
  }

  Hap<R> withValue<R>(R Function(T) func) {
    return Hap(
      whole,
      part,
      func(value),
      context: context,
      stateful: stateful,
      scheduledTime: scheduledTime,
    );
  }

  bool hasOnset() {
    return whole != null && whole!.begin == part.begin;
  }

  Hap<T> setContext(Map<String, dynamic> newContext) {
    return Hap(whole, part, value, context: newContext, stateful: stateful);
  }

  Map<String, dynamic> combineContext(Hap other) {
    final List<dynamic> locations = [
      ...(context['locations'] as List<dynamic>? ?? []),
      ...(other.context['locations'] as List<dynamic>? ?? []),
    ];
    return {...context, ...other.context, 'locations': locations};
  }

  @override
  String toString() {
    return '[ ${whole ?? 'cont'} | $part | $value ]';
  }
}
