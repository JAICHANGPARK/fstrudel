# fstrudel

Workspace for Strudel and related ports.

## Projects

- `strudel/`: JS/TS monorepo with the REPL/web app and packages.
- `strudel_dart/`: Dart core port used by the Flutter client.
- `flutter_strudel/`: Flutter client app.
- `tidal/`, `tidal_dart/`: Additional Tidal-related experiments/tools.

## Supported Commands

### `strudel/`

```sh
pnpm i
pnpm dev
pnpm build
pnpm test
pnpm test-ui
pnpm lint
pnpm codeformat
pnpm check
```

### `strudel_dart/`

```sh
dart pub get
dart run
dart test
dart format .
```

### `flutter_strudel/`

```sh
flutter pub get
flutter run
flutter test
dart format .
```

## Notes

- Node.js >= 18 and pnpm are required for `strudel/`.
- `flutter_strudel/` depends on `strudel_dart/` via a path dependency.
- Upstream lives on Codeberg; follow the repo's CONTRIBUTING policy.
