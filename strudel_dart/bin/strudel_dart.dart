import 'package:strudel_dart/strudel_dart.dart';

void main() {
  final pat = pure('bd').map((v) => 'instrument: $v');
  final haps = pat.queryArc(0, 1);
  for (final hap in haps) {
    // ignore: avoid_print
    print(hap);
  }
}
