import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class SampleBank {
  final List<String>? urls;
  final Map<String, List<String>>? pitched;

  const SampleBank.list(this.urls) : pitched = null;
  const SampleBank.pitched(this.pitched) : urls = null;

  bool get isPitched => pitched != null;
}

class SampleMapDefinition {
  final String url;
  final String? baseUrl;

  const SampleMapDefinition(this.url, {this.baseUrl});
}

class SampleManager {
  static const String _baseCdn = 'https://strudel.b-cdn.net';

  static const List<SampleMapDefinition> _defaultSampleMaps = [
    SampleMapDefinition(
      '$_baseCdn/tidal-drum-machines.json',
      baseUrl: '$_baseCdn/tidal-drum-machines/machines/',
    ),
    SampleMapDefinition(
      'https://raw.githubusercontent.com/felixroos/dough-samples/main/'
          'piano.json',
    ),
    SampleMapDefinition(
      'https://raw.githubusercontent.com/felixroos/dough-samples/main/'
          'Dirt-Samples.json',
    ),
    SampleMapDefinition(
      'https://raw.githubusercontent.com/felixroos/dough-samples/main/'
          'vcsl.json',
    ),
    SampleMapDefinition(
      'https://raw.githubusercontent.com/felixroos/dough-samples/main/'
          'mridangam.json',
    ),
    SampleMapDefinition(
      '$_baseCdn/uzu-drumkit.json',
      baseUrl: '$_baseCdn/uzu-drumkit/',
    ),
    SampleMapDefinition(
      '$_baseCdn/uzu-wavetables.json',
      baseUrl: '$_baseCdn/uzu-wavetables/',
    ),
  ];

  static const String _defaultAliasBankUrl =
      '$_baseCdn/tidal-drum-machines-alias.json';

  static const String _drumMachinesBaseUrl =
      '$_baseCdn/tidal-drum-machines/machines/';
  static const String _dirtSamplesBaseUrl =
      '$_baseCdn/Dirt-Samples/';

  // Fallback mappings for common banks and sounds.
  // Format: {bank_sound: path_suffix}
  static const Map<String, List<String>> _legacySampleMap = {
    // Default mappings (fallbacks for no bank) - using RolandTR909 as base per documentation
    'bd': ['RolandTR909/rolandtr909-bd/Bassdrum-01.wav'],
    'kick': ['RolandTR909/rolandtr909-bd/Bassdrum-01.wav'],
    'sd': ['RolandTR909/rolandtr909-sd/naredrum.wav'],
    'hh': ['RolandTR909/rolandtr909-hh/hh01.wav'], // Reverted to TR909
    'oh': ['RolandTR909/rolandtr909-oh/Hat Open.wav'],
    'cp': ['RolandTR909/rolandtr909-cp/Clap.wav'],
    'rim': ['RolandTR909/rolandtr909-rim/Rimhot.wav'],
    'cr': ['RolandTR909/rolandtr909-cr/Crash.wav'],
    'rd': ['RolandTR909/rolandtr909-rd/Ride.wav'],
    'ht': ['RolandTR909/rolandtr909-ht/Tom H.wav'],
    'mt': ['RolandTR909/rolandtr909-mt/Tom M.wav'],
    'lt': ['RolandTR909/rolandtr909-lt/Tom L.wav'],
    'sh': ['RolandTR808/rolandtr808-sh/MA.WAV'],
    'cb': ['RolandTR808/rolandtr808-cb/CB.WAV'],
    'cl': ['RolandTR808/rolandtr808-cl/CL.WAV'], // Claves
    'hc': ['RolandTR808/rolandtr808-hc/HC00.WAV'], // Conga High
    'mc': ['RolandTR808/rolandtr808-mc/MC00.WAV'],
    'lc': ['RolandTR808/rolandtr808-lc/LC00.WAV'],
    // Additional percussion from Dirt-Samples
    'tb': ['tabla/000_1.wav'], // Tambourine / Tabla
    'perc': ['perc/000_perc1.wav'],
    'fx': ['future/000_1.wav'], // Effects

    'RolandTR909_bd': ['RolandTR909/rolandtr909-bd/Bassdrum-01.wav'],
    'RolandTR909_sd': ['RolandTR909/rolandtr909-sd/naredrum.wav'],
    'RolandTR909_hh': ['RolandTR909/rolandtr909-hh/hh01.wav'],
    'RolandTR909_oh': ['RolandTR909/rolandtr909-oh/Hat Open.wav'],
    'RolandTR909_cp': ['RolandTR909/rolandtr909-cp/Clap.wav'],
    'RolandTR909_rim': ['RolandTR909/rolandtr909-rim/Rimhot.wav'],
    'RolandTR909_cr': ['RolandTR909/rolandtr909-cr/Crash.wav'],
    'RolandTR909_ht': ['RolandTR909/rolandtr909-ht/Tom H.wav'],
    'RolandTR909_mt': ['RolandTR909/rolandtr909-mt/Tom M.wav'],
    'RolandTR909_lt': ['RolandTR909/rolandtr909-lt/Tom L.wav'],
    'RolandTR909_rd': ['RolandTR909/rolandtr909-rd/Ride.wav'],

    'RolandTR808_bd': ['RolandTR808/rolandtr808-bd/BD0000.WAV'],
    'RolandTR808_sd': ['RolandTR808/rolandtr808-sd/SD0000.WAV'],
    'RolandTR808_hh': ['RolandTR808/rolandtr808-hh/CH.WAV'],
    'RolandTR808_oh': ['RolandTR808/rolandtr808-oh/OH00.WAV'],
    'RolandTR808_cp': ['RolandTR808/rolandtr808-cp/cp0.wav'],
    'RolandTR808_cb': ['RolandTR808/rolandtr808-cb/CB.WAV'],
    'RolandTR808_ht': ['RolandTR808/rolandtr808-ht/HT00.WAV'],
    'RolandTR808_mt': ['RolandTR808/rolandtr808-mt/MT00.WAV'],
    'RolandTR808_lt': ['RolandTR808/rolandtr808-lt/LT00.WAV'],
    'RolandTR808_rim': ['RolandTR808/rolandtr808-rim/RS.WAV'],
    'RolandTR808_sh': ['RolandTR808/rolandtr808-sh/MA.WAV'],

    // Jazz kit from Dirt-Samples
    'jazz_bd': ['jazz/000_BD.wav'],
    'jazz_sd': ['jazz/007_SN.wav'],
    'jazz_hh': ['jazz/003_HH.wav'],
    'jazz_oh': ['jazz/004_OH.wav'],
    'jazz': [
      'jazz/000_BD.wav',
      'jazz/001_CB.wav',
      'jazz/002_FX.wav',
      'jazz/003_HH.wav',
      'jazz/004_OH.wav',
      'jazz/005_P1.wav',
      'jazz/006_P2.wav',
      'jazz/007_SN.wav',
    ],
    // Other common Dirt-Samples
    'casio': ['casio/high.wav', 'casio/low.wav', 'casio/noise.wav'],
    'metal': [
      'metal/000_0.wav',
      'metal/001_1.wav',
      'metal/002_2.wav',
      'metal/003_3.wav',
      'metal/004_4.wav',
      'metal/005_5.wav',
      'metal/006_6.wav',
      'metal/007_7.wav',
      'metal/008_8.wav',
      'metal/009_9.wav',
    ],
    'crow': [
      'crow/000_crow.wav',
      'crow/001_crow2.wav',
      'crow/002_crow3.wav',
      'crow/003_crow4.wav',
    ],
    'insect': [
      'insect/000_everglades_conehead.wav',
      'insect/001_robust_shieldback.wav',
      'insect/002_seashore_meadow_katydid.wav',
    ],
    'wind': [
      'wind/000_wind1.wav',
      'wind/001_wind10.wav',
      'wind/002_wind2.wav',
      'wind/003_wind3.wav',
      'wind/004_wind4.wav',
      'wind/005_wind5.wav',
      'wind/006_wind6.wav',
      'wind/007_wind7.wav',
      'wind/008_wind8.wav',
      'wind/009_wind9.wav',
    ],
    'misc': ['misc/000_misc.wav'],
  };

  final Map<String, SampleBank> _banks = {};
  final Map<String, String> _aliasToBank = {};
  final Map<String, List<String>> _bankAliases = {};
  final Map<String, String> _cache = {};
  Future<void>? _initFuture;

  Future<void> initializeDefaults() {
    _initFuture ??= _initializeDefaults();
    return _initFuture!;
  }

  Future<void> _initializeDefaults() async {
    for (final map in _defaultSampleMaps) {
      await _addSampleMapFromUrl(
        map.url,
        baseOverride: map.baseUrl,
      );
    }
    await _loadAliasBankMap(_defaultAliasBankUrl);
    _applyBankAliases();
  }

  Future<void> addSampleMap(
    dynamic sampleMap, {
    String? baseUrl,
  }) async {
    await initializeDefaults();
    if (sampleMap is String) {
      final resolvedUrl = _resolveSampleMapUrl(sampleMap);
      final baseOverride =
          baseUrl != null ? _resolveSampleBase(baseUrl) : null;
      await _addSampleMapFromUrl(
        resolvedUrl,
        baseOverride: baseOverride,
      );
      _applyBankAliases();
      return;
    }
    if (sampleMap is Map<String, dynamic>) {
      var resolvedBase =
          baseUrl ?? sampleMap['_base']?.toString() ?? '';
      resolvedBase = _resolveSampleBase(resolvedBase);
      _addSampleMap(
        sampleMap,
        resolvedBase,
        allowMapBase: baseUrl == null,
      );
      _applyBankAliases();
      return;
    }
    print('SampleManager: Unsupported sample map: ${sampleMap.runtimeType}');
  }

  Future<String?> getSamplePath(
    String sound, {
    String? bank,
    int n = 0,
    dynamic note,
    dynamic freq,
  }) async {
    await initializeDefaults();
    String normalizedSound = _normalizeSoundKey(sound);
    final colonIndex = normalizedSound.indexOf(':');
    if (colonIndex != -1 && n == 0) {
      final maybeIndex = int.tryParse(normalizedSound.substring(colonIndex + 1));
      if (maybeIndex != null) {
        n = maybeIndex;
        normalizedSound = normalizedSound.substring(0, colonIndex);
      }
    }

    String? resolvedKey;
    if (bank != null && bank.trim().isNotEmpty) {
      final normalizedBank = _normalizeSoundKey(bank);
      final canonicalBank = _aliasToBank[normalizedBank] ?? normalizedBank;
      final bankKey = '${canonicalBank}_$normalizedSound';
      if (_banks.containsKey(bankKey)) {
        resolvedKey = bankKey;
      } else {
        final rawBankKey = '${normalizedBank}_$normalizedSound';
        if (_banks.containsKey(rawBankKey)) {
          resolvedKey = rawBankKey;
        }
      }
    }
    resolvedKey ??= normalizedSound;

    final bankData = _banks[resolvedKey];
    if (bankData == null) {
      return _getLegacySamplePath(normalizedSound, bank: bank, n: n);
    }

    final url = _selectUrl(bankData, n, note: note, freq: freq);
    if (url == null) {
      print('SampleManager: No sample URL found for $resolvedKey');
      return null;
    }

    if (_cache.containsKey(url)) {
      return _cache[url];
    }

    // Check local storage
    final file = await _getLocalFileForUrl(url);
    if (await file.exists()) {
      _cache[url] = file.path;
      return file.path;
    }

    // Download
    try {
      print('SampleManager: Downloading $url...');
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(response.bodyBytes);
        _cache[url] = file.path;
        print('SampleManager: Downloaded and cached $resolvedKey');
        return file.path;
      } else {
        print(
          'SampleManager: Download failed (${response.statusCode}) for $url',
        );
      }
    } catch (e) {
      print('SampleManager: Error downloading sample: $e');
    }

    return null;
  }

  String? _selectUrl(
    SampleBank bankData,
    int n, {
    dynamic note,
    dynamic freq,
  }) {
    if (bankData.isPitched) {
      final pitched = bankData.pitched!;
      if (pitched.isEmpty) return null;
      final closestKey = _closestPitchKey(
        pitched.keys.toList(),
        n: n,
        note: note,
        freq: freq,
      );
      final urls = pitched[closestKey];
      if (urls == null || urls.isEmpty) return null;
      return urls[n % urls.length];
    }
    final urls = bankData.urls ?? [];
    if (urls.isEmpty) return null;
    return urls[n % urls.length];
  }

  String _closestPitchKey(
    List<String> keys, {
    int n = 0,
    dynamic note,
    dynamic freq,
  }) {
    final normalized = keys.map((k) => k.toLowerCase()).toList();
    final targetMidi = _valueToMidi(note, freq, fallback: 36);
    double bestDiff = double.infinity;
    String bestKey = normalized.first;
    for (final key in normalized) {
      final midi = _noteToMidi(key, fallback: null);
      if (midi == null) continue;
      final diff = (midi - targetMidi).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestKey = key;
      }
    }
    return bestKey;
  }

  double _valueToMidi(dynamic note, dynamic freq, {required double fallback}) {
    if (freq is num && freq > 0) {
      return _freqToMidi(freq.toDouble());
    }
    if (note is num) {
      return note.toDouble();
    }
    if (note is String) {
      final midi = _noteToMidi(note, fallback: fallback.toInt());
      if (midi != null) return midi.toDouble();
    }
    return fallback;
  }

  double _freqToMidi(double freq) {
    return (12 * (math.log(freq / 440) / math.ln2)) + 69;
  }

  int? _noteToMidi(String note, {int? fallback}) {
    final match = RegExp(r'^([a-gA-G])([#bsf]*)(-?[0-9]*)$').firstMatch(
      note.trim(),
    );
    if (match == null) return fallback;
    final pc = match.group(1);
    final acc = match.group(2) ?? '';
    final octText = match.group(3);
    if (pc == null) return fallback;
    final chromas = {
      'c': 0,
      'd': 2,
      'e': 4,
      'f': 5,
      'g': 7,
      'a': 9,
      'b': 11,
    };
    final accs = {'#': 1, 'b': -1, 's': 1, 'f': -1};
    final octave = octText == null || octText.isEmpty
        ? 3
        : int.tryParse(octText) ?? 3;
    final chroma = chromas[pc.toLowerCase()];
    if (chroma == null) return fallback;
    int offset = 0;
    for (final char in acc.split('')) {
      offset += accs[char] ?? 0;
    }
    return (octave + 1) * 12 + chroma + offset;
  }

  Future<void> _addSampleMapFromUrl(
    String url, {
    String? baseOverride,
  }) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        print('SampleManager: Failed to load sample map $url');
        return;
      }
      final jsonBody = jsonDecode(response.body);
      if (jsonBody is! Map<String, dynamic>) {
        print('SampleManager: Invalid sample map format: $url');
        return;
      }
      final base = baseOverride ?? _baseFromUrl(url);
      _addSampleMap(
        jsonBody,
        base,
        allowMapBase: baseOverride == null,
      );
    } catch (e) {
      print('SampleManager: Error loading sample map $url: $e');
    }
  }

  void _addSampleMap(
    Map<String, dynamic> sampleMap,
    String baseUrl, {
    bool allowMapBase = true,
  }) {
    final dynamic baseOverride =
        allowMapBase ? sampleMap['_base'] : null;
    final String mapBase = _resolveSampleBase(
      baseOverride is String ? baseOverride : baseUrl,
    );
    for (final entry in sampleMap.entries) {
      if (entry.key == '_base') continue;
      _addSampleEntry(entry.key, entry.value, mapBase);
    }
  }

  void _addSampleEntry(String key, dynamic value, String baseUrl) {
    String entryBase = baseUrl;
    if (value is Map && value['_base'] is String) {
      entryBase = _resolveSampleBase(value['_base'] as String);
    }
    entryBase = _ensureTrailingSlash(entryBase);
    final normalizedKey = _normalizeSoundKey(key);

    if (value is String) {
      _banks[normalizedKey] =
          SampleBank.list([_resolveUrl(entryBase, value)]);
      return;
    }

    if (value is List) {
      final urls = value
          .whereType<String>()
          .map((path) => _resolveUrl(entryBase, path))
          .toList();
      if (urls.isNotEmpty) {
        _banks[normalizedKey] = SampleBank.list(urls);
      }
      return;
    }

    if (value is Map) {
      final entries = value.entries.where((e) => e.key != '_base').toList();
      if (entries.isEmpty) return;

      if (_isNoteMap(entries.map((e) => e.key.toString()).toList())) {
        final pitched = <String, List<String>>{};
        for (final noteEntry in entries) {
          final noteKey = noteEntry.key.toLowerCase();
          final noteValue = noteEntry.value;
          if (noteValue is String) {
            pitched[noteKey] = [_resolveUrl(entryBase, noteValue)];
          } else if (noteValue is List) {
            final urls = noteValue
                .whereType<String>()
                .map((path) => _resolveUrl(entryBase, path))
                .toList();
            if (urls.isNotEmpty) {
              pitched[noteKey] = urls;
            }
          }
        }
        if (pitched.isNotEmpty) {
          _banks[normalizedKey] = SampleBank.pitched(pitched);
        }
        return;
      }

      for (final soundEntry in entries) {
        _addSampleEntry('${key}_${soundEntry.key}', soundEntry.value, entryBase);
      }
    }
  }

  Future<void> _loadAliasBankMap(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        print('SampleManager: Failed to load alias bank map $url');
        return;
      }
      final jsonBody = jsonDecode(response.body);
      if (jsonBody is! Map<String, dynamic>) {
        print('SampleManager: Invalid alias bank format: $url');
        return;
      }
      for (final entry in jsonBody.entries) {
        final bank = _normalizeSoundKey(entry.key);
        final aliases = <String>[];
        final value = entry.value;
        if (value is String) {
          aliases.add(_normalizeSoundKey(value));
        } else if (value is List) {
          aliases.addAll(
            value.whereType<String>().map(_normalizeSoundKey),
          );
        }
        _bankAliases[bank] = aliases;
        _aliasToBank[bank] = bank;
        for (final alias in aliases) {
          _aliasToBank[alias] = bank;
        }
      }
    } catch (e) {
      print('SampleManager: Error loading alias bank map $url: $e');
    }
  }

  void _applyBankAliases() {
    if (_bankAliases.isEmpty) return;
    final entries = Map<String, SampleBank>.from(_banks);
    for (final entry in entries.entries) {
      final key = entry.key;
      final splitIndex = key.indexOf('_');
      if (splitIndex == -1) continue;
      final bank = key.substring(0, splitIndex);
      final suffix = key.substring(splitIndex + 1);
      final aliases = _bankAliases[bank];
      if (aliases == null) continue;
      for (final alias in aliases) {
        final aliasKey = '${alias}_$suffix';
        _banks.putIfAbsent(aliasKey, () => entry.value);
      }
    }
  }

  String _normalizeSoundKey(String key) {
    return key.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
  }

  bool _isNoteMap(List<String> keys) {
    final noteRegex = RegExp(r'^([a-gA-G])([#bsf]*)(-?[0-9]*)$');
    return keys.isNotEmpty && keys.every((k) => noteRegex.hasMatch(k));
  }

  String _resolveSampleMapUrl(String url) {
    var resolved = _resolveSpecialPaths(url);
    if (resolved.startsWith('github:')) {
      resolved = _githubPath(resolved, 'strudel.json');
    }
    if (resolved.startsWith('local:')) {
      resolved = 'http://localhost:5432';
    }
    if (resolved.startsWith('shabda:')) {
      final parts = resolved.split('shabda:');
      final path = parts.length > 1 ? parts[1] : '';
      resolved = 'https://shabda.ndre.gr/$path.json?strudel=1';
    }
    if (resolved.startsWith('shabda/speech')) {
      final parts = resolved.split('shabda/speech');
      var path = parts.length > 1 ? parts[1] : '';
      path = path.startsWith('/') ? path.substring(1) : path;
      final segments = path.split(':');
      final params = segments.isNotEmpty ? segments[0] : '';
      final words = segments.length > 1 ? segments[1] : '';
      var language = 'en-GB';
      var gender = 'f';
      if (params.isNotEmpty) {
        final parts = params.split('/');
        if (parts.isNotEmpty) language = parts[0];
        if (parts.length > 1) gender = parts[1];
      }
      resolved =
          'https://shabda.ndre.gr/speech/$words.json?gender=$gender&language=$language&strudel=1';
    }
    return resolved;
  }

  String _resolveSampleBase(String baseUrl) {
    var resolved = _resolveSpecialPaths(baseUrl);
    if (resolved.startsWith('github:')) {
      resolved = _githubPath(resolved, '');
    }
    return resolved;
  }

  String _resolveSpecialPaths(String base) {
    if (base.startsWith('bubo:')) {
      final parts = base.split(':');
      final repo = parts.length > 1 ? parts[1] : '';
      return 'github:Bubobubobubobubo/dough-$repo';
    }
    return base;
  }

  String _githubPath(String base, String subpath) {
    if (!base.startsWith('github:')) {
      return base;
    }
    var path = base.substring('github:'.length);
    path = path.endsWith('/') ? path.substring(0, path.length - 1) : path;

    final parts = path.split('/');
    final user = parts.isNotEmpty ? parts[0] : '';
    final repo = parts.length >= 2 ? parts[1] : 'samples';
    final branch = parts.length >= 3 ? parts[2] : 'main';
    final remaining = parts.length > 3 ? parts.sublist(3) : <String>[];
    final segments = [...remaining, if (subpath.isNotEmpty) subpath];
    final suffix = segments.isEmpty ? '' : segments.join('/');
    return 'https://raw.githubusercontent.com/$user/$repo/$branch/$suffix';
  }

  String _resolveUrl(String base, String path) {
    final schemeMatch = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:');
    if (schemeMatch.hasMatch(path)) {
      return path;
    }
    return '${_ensureTrailingSlash(base)}$path';
  }

  String _baseFromUrl(String url) {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments.toList();
    if (segments.isNotEmpty) {
      segments.removeLast();
    }
    final baseUri = uri.replace(pathSegments: segments, query: '');
    return _ensureTrailingSlash(baseUri.toString());
  }

  String _ensureTrailingSlash(String base) {
    if (base.isEmpty) return base;
    return base.endsWith('/') ? base : '$base/';
  }

  Future<String?> _getLegacySamplePath(
    String sound, {
    String? bank,
    int n = 0,
  }) async {
    String key;
    if (bank != null && bank.isNotEmpty) {
      String normalizedBank = bank;
      final bankLower = bank.toLowerCase();
      if (bankLower == 'tr909' ||
          bankLower == '909' ||
          bankLower == 'rolandtr909') {
        normalizedBank = 'RolandTR909';
      } else if (bankLower == 'tr808' ||
          bankLower == '808' ||
          bankLower == 'rolandtr808') {
        normalizedBank = 'RolandTR808';
      } else if (bankLower == 'jazz') {
        normalizedBank = 'jazz';
      }
      key = '${normalizedBank}_$sound';
    } else {
      key = sound;
    }

    if (!_legacySampleMap.containsKey(key)) {
      print('SampleManager: No mapping found for $key');
      return null;
    }

    final paths = _legacySampleMap[key]!;
    final pathSuffix = paths[n % paths.length];

    String baseUrl = _drumMachinesBaseUrl;
    if (pathSuffix.startsWith('jazz/') ||
        pathSuffix.startsWith('casio/') ||
        pathSuffix.startsWith('crow/') ||
        pathSuffix.startsWith('insect/') ||
        pathSuffix.startsWith('wind/') ||
        pathSuffix.startsWith('metal/') ||
        pathSuffix.startsWith('misc/') ||
        pathSuffix.startsWith('hh27/') ||
        pathSuffix.startsWith('tabla/') ||
        pathSuffix.startsWith('perc/') ||
        pathSuffix.startsWith('future/')) {
      baseUrl = _dirtSamplesBaseUrl;
    }
    final url = '$baseUrl$pathSuffix';

    if (_cache.containsKey(url)) {
      return _cache[url];
    }

    final file = await _getLocalFile(pathSuffix);
    if (await file.exists()) {
      _cache[url] = file.path;
      return file.path;
    }

    try {
      print('SampleManager: Downloading $url...');
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(response.bodyBytes);
        _cache[url] = file.path;
        print('SampleManager: Downloaded and cached $key');
        return file.path;
      } else {
        print(
          'SampleManager: Download failed (${response.statusCode}) for $url',
        );
      }
    } catch (e) {
      print('SampleManager: Error downloading sample: $e');
    }

    return null;
  }

  Future<File> _getLocalFile(String pathSuffix) async {
    final cacheDir = await getTemporaryDirectory();
    final localPath = p.join(cacheDir.path, 'strudel_cache', pathSuffix);
    return File(localPath);
  }

  Future<File> _getLocalFileForUrl(String url) async {
    final uri = Uri.tryParse(url);
    String pathSuffix;
    if (uri != null && uri.path.isNotEmpty) {
      pathSuffix =
          uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    } else {
      pathSuffix = base64Url.encode(utf8.encode(url));
    }
    return _getLocalFile(pathSuffix);
  }
}
