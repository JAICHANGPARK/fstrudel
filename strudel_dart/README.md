# strudel_dart

Dart port of Strudel core logic (patterns, mini notation parsing, and synth
helpers). This library powers the Flutter client in `flutter_strudel/`.

- Porting status: see `PORTING.md`.
- Web docs reference: https://strudel.cc/learn (not all features are ported).

## Supported Commands

```sh
dart pub get
dart run
dart test
dart format .
```

## Usage

```dart
import 'package:strudel_dart/strudel_dart.dart';

final repl = StrudelREPL();
final pattern = repl.evaluate('s("bd sd")');
```
