List<List<T>> splitAt<T>(int n, List<T> list) {
  if (n >= list.length) return [list, []];
  return [list.sublist(0, n), list.sublist(n)];
}

// Returns [n, x]
List<dynamic> _left(List<int> n, List<List<List<int>>> x) {
  // n is [ons, offs]
  // x is [xs, ys] where xs, ys are List<List<int>> (sequences)

  final ons = n[0];
  final offs = n[1];
  final xs = x[0];
  final ys = x[1];

  // xs is List<List<int>>
  final split = splitAt(offs, xs);
  final _xs = split[0];
  final __xs = split[1];

  final zipped = <List<int>>[];
  // zipWith concat
  for (var i = 0; i < _xs.length && i < ys.length; i++) {
    zipped.add([..._xs[i], ...ys[i]]);
  }

  // Returns [ [new_n], [new_xs, new_ys] ]
  return [
    [offs, ons - offs],
    [zipped, __xs],
  ];
}

List<dynamic> _right(List<int> n, List<List<List<int>>> x) {
  final ons = n[0];
  final offs = n[1];
  final xs = x[0];
  final ys = x[1];

  final split = splitAt(ons, ys);
  final _ys = split[0];
  final __ys = split[1];

  final zipped = <List<int>>[];
  for (var i = 0; i < xs.length && i < _ys.length; i++) {
    zipped.add([...xs[i], ..._ys[i]]);
  }

  return [
    [ons, offs - ons],
    [zipped, __ys],
  ];
}

List<dynamic> _bjorklundRecursive(List<int> n, List<List<List<int>>> x) {
  final ons = n[0];
  final offs = n[1];

  if (ons <= 1 || offs <= 1) {
    // Same as JS Math.min
    // Actually checking if MIN(ons, offs) <= 1.
    // Wait, JS: Math.min(ons, offs) <= 1 check.
    if ((ons < offs ? ons : offs) <= 1) {
      return [n, x];
    }
  }

  if (ons > offs) {
    final res = _left(n, x);
    return _bjorklundRecursive(
      res[0] as List<int>,
      res[1] as List<List<List<int>>>,
    );
  } else {
    final res = _right(n, x);
    return _bjorklundRecursive(
      res[0] as List<int>,
      res[1] as List<List<List<int>>>,
    );
  }
}

List<int> bjorklund(int onsets, int steps) {
  if (steps == 0) return [];
  if (onsets == 0) return List.filled(steps, 0);

  final inverted = onsets < 0;
  final absOns = onsets.abs();
  final offs = steps - absOns;

  final ones = List.generate(absOns, (_) => [1]);
  final zeros = List.generate(offs, (_) => [0]);

  // x is [ones, zeros]
  final x = [ones, zeros];
  final n = [absOns, offs];

  final result = _bjorklundRecursive(n, x);
  // result is [n, x]
  final resultX = result[1] as List<List<List<int>>>;
  final resultLists = resultX; // [xs, ys]

  final pattern = [
    ...resultLists[0].expand((x) => x),
    ...resultLists[1].expand((x) => x),
  ];

  if (inverted) {
    return pattern.map((x) => 1 - x).toList();
  }
  return pattern;
}
