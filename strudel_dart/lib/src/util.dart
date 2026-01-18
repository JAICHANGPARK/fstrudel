import 'package:fraction/fraction.dart' as f;

/// Modulo that works with negative numbers e.g. _mod(-1, 3) = 2.
num mod(num n, num m) => ((n % m) + m) % m;

/// rational version of mod
f.Fraction modFraction(f.Fraction n, f.Fraction m) {
  final div = n / m;
  final floor = f.Fraction(div.numerator ~/ div.denominator);
  final res = n - (m * floor);
  return res.isNegative ? res + m : res;
}

List<T> flatten<T>(Iterable<Iterable<T>> list) =>
    list.expand((element) => element).toList();
