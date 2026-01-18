import 'package:fraction/fraction.dart' as f;

extension StrudelFraction on f.Fraction {
  /// Returns the start of the cycle (floor).
  f.Fraction sam() => f.Fraction(numerator ~/ denominator);

  /// Returns the start of the next cycle.
  f.Fraction nextSam() => sam() + f.Fraction(1);

  /// The position of a time value relative to the start of its cycle.
  f.Fraction cyclePos() => this - sam();

  bool lt(f.Fraction other) => this < other;
  bool gt(f.Fraction other) => this > other;
  bool lte(f.Fraction other) => this <= other;
  bool gte(f.Fraction other) => this >= other;
  bool eq(f.Fraction other) => this == other;
  bool ne(f.Fraction other) => this != other;

  f.Fraction max(f.Fraction other) => this > other ? this : other;
  f.Fraction min(f.Fraction other) => this < other ? this : other;

  f.Fraction? mulMaybe(f.Fraction? other) =>
      other != null ? this * other : null;
  f.Fraction? divMaybe(f.Fraction? other) =>
      other != null ? this / other : null;
  f.Fraction? addMaybe(f.Fraction? other) =>
      other != null ? this + other : null;
  f.Fraction? subMaybe(f.Fraction? other) =>
      other != null ? this - other : null;

  String show() => '${isNegative ? '-' : ''}$numerator/$denominator';
}

f.Fraction lcm(f.Fraction a, f.Fraction b) {
  // LCM(a/b, c/d) = LCM(ac, bc) / GCD(ad, bd) ??? No.
  // Standard formula: LCM(a/b, c/d) = LCM(a, c) / GCD(b, d)
  final n = (a.numerator * b.numerator) ~/ a.numerator.gcd(b.numerator);
  final d = a.denominator.gcd(b.denominator);
  return f.Fraction(n, d);
}

f.Fraction? lcmMany(Iterable<f.Fraction?> fractions) {
  final valid = fractions.whereType<f.Fraction>();
  if (valid.isEmpty) return null;
  return valid.reduce(lcm);
}

f.Fraction fraction(dynamic n) {
  if (n is f.Fraction) return n;
  if (n is int) return f.Fraction(n);
  if (n is double) return f.Fraction.fromDouble(n);
  if (n is String) return f.Fraction.fromString(n);
  throw ArgumentError('Cannot convert $n to Fraction');
}
