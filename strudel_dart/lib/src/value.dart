import 'logger.dart';

Map<String, dynamic> unionWithObj(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
  dynamic Function(dynamic, dynamic) func,
) {
  if (b.containsKey('value') && b.length == 1) {
    logger('[warn]: Can\'t do arithmetic on control pattern.');
    return a;
  }
  final commonKeys = a.keys.where(b.containsKey);
  final merged = <String, dynamic>{...a, ...b};
  for (final key in commonKeys) {
    merged[key] = func(a[key], b[key]);
  }
  return merged;
}

dynamic Function(dynamic) mul(dynamic a) =>
    (dynamic b) => a * b;

Value valued(dynamic value) => value is Value ? value : Value.of(value);

class Value {
  final dynamic value;

  Value(this.value);

  static Value of(dynamic x) => Value(x);

  bool get isNothing => value == null;

  Value map(dynamic Function(dynamic) func) {
    if (isNothing) {
      return this;
    }
    return Value.of(func(value));
  }

  Value mul(dynamic n) {
    return map(mul).ap(n);
  }

  Value ap(dynamic other) {
    final fn = value;
    if (fn is! Function) {
      throw StateError('Value.ap expected a function value');
    }
    return valued(other).map((v) => Function.apply(fn, [v]));
  }

  Value unionWith(dynamic other, dynamic Function(dynamic, dynamic) func) {
    final otherVal = valued(other);
    if (value.runtimeType != otherVal.value.runtimeType) {
      throw StateError('unionWith: both Values must have same type');
    }
    if (value is! Map || otherVal.value is! Map) {
      throw StateError('unionWith: expected objects');
    }
    return map(
      (v) => unionWithObj(
        Map<String, dynamic>.from(v as Map),
        Map<String, dynamic>.from(otherVal.value as Map),
        func,
      ),
    );
  }
}

dynamic mapValue(dynamic Function(dynamic) f, dynamic anyFunctor) {
  return anyFunctor.map(f);
}
