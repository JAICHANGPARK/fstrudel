import 'dart:convert';

/// Sample Mapper - Ported from strudel/packages/superdough/sampler.mjs
///
/// Provides sample bank registration and mapping logic for Strudel sounds
/// Supports array-format banks, note-mapped banks, and various sample formats

class SampleMapper {
  static final Map<String, _SoundBank> _registeredBanks = {};

  /// Register a sample bank for use with sounds
  static void registerBank(String name, _SoundBank bank) {
    _registeredBanks[name] = bank;
    print(
      'SampleMapper: Registered bank "$name" with ${bank.registeredKeys.length} sounds',
    );
  }

  /// Get a registered bank by name
  static _SoundBank? getBank(String name) => _registeredBanks[name];

  /// Register a single sound for direct access
  static void registerSound(String key, _SoundInfo sound) {
    final parts = key.split('_');
    if (parts.length == 2) {
      final bankName = parts[0];
      final bank = _registeredBanks[bankName];
      if (bank != null && bank is _ArrayBank) {
        (bank as _ArrayBank).addSound(key, sound);
      }
    }
  }

  /// Resolve a sample from a bank name and sound string
  /// Supports formats: "bank_sound", "bank:sound", "sound:n", or just "sound"
  static _SoundInfo? resolveSample(String value, {String? defaultBank}) {
    // Try bank_sound format
    final bankSoundMatch = RegExp(r'^([^_:]+)_([^_:]+)$').firstMatch(value);
    if (bankSoundMatch != null) {
      final bankName = bankSoundMatch!.group(1)!;
      final soundName = bankSoundMatch!.group(2)!;
      final bank = _registeredBanks[bankName];
      if (bank != null) {
        return bank!.getSound(soundName);
      }
    }

    // Try bank:sound format
    final colonIndex = value.indexOf(':');
    if (colonIndex > 0) {
      final bankName = value.substring(0, colonIndex);
      final soundName = value.substring(colonIndex + 1);
      final bank = _registeredBanks[bankName];
      if (bank != null) {
        return bank!.getSound(soundName);
      }
    }

    // Try sound:n format
    final colonIndex2 = value.indexOf(':');
    if (colonIndex2 > 0) {
      final soundPart = value.substring(colonIndex2 + 1);
      final soundNameMatch = RegExp(r'^(\w+):(\d+)$').firstMatch(soundPart);
      if (soundNameMatch != null) {
        final soundName = soundNameMatch!.group(1)!;
        final index = int.parse(soundNameMatch!.group(2)!);
        final bankName = soundPart.split(':')[0];
        final bank = _registeredBanks[bankName];
        if (bank != null && bank is _ArrayBank) {
          return (bank as _ArrayBank).getByIndex(index);
        }
      }
    }

    // Try just the sound name (check in default bank)
    final bank = defaultBank != null ? _registeredBanks[defaultBank!] : null;
    if (bank != null) {
      return bank!.getSound(value);
    }

    // Try finding in all registered banks
    for (final entry in _registeredBanks.entries) {
      final info = entry.value.getSound(value);
      if (info != null) return info;
    }

    return null;
  }

  /// Parse a sample map from JSON (for loading sample packs)
  static Map<String, _SoundBank> parseSampleMap(String jsonStr) {
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    final result = <String, _SoundBank>{};

    for (final entry in json.entries) {
      final bankName = entry.key;
      final value = entry.value;

      if (value is Map<String, dynamic>) {
        result[bankName] = _NoteBank(value as Map<String, dynamic>);
      } else if (value is List<dynamic>) {
        result[bankName] = _ArrayBank(value as List<dynamic>);
      }
    }

    return result;
  }

  /// Create a sample map from direct bank definitions
  static Map<String, _SoundBank> fromBanks(Map<String, dynamic> banks) {
    final result = <String, _SoundBank>{};
    for (final entry in banks.entries) {
      final bankName = entry.key;
      final value = entry.value;

      if (value is Map<String, dynamic>) {
        result[bankName] = _NoteBank(value);
      } else if (value is List<dynamic>) {
        result[bankName] = _ArrayBank(value as List<dynamic>);
      } else if (value is String) {
        // Handle base URL format
        result[bankName] = _BaseBank(value as String);
      }
    }

    return result;
  }

  /// Register a sample map from JSON string
  static void registerSampleMap(String jsonStr) {
    final banks = parseSampleMap(jsonStr);
    for (final entry in banks.entries) {
      _registeredBanks[entry.key] = entry.value;
      print(
        'SampleMapper: Registered bank "${entry.key}" with ${entry.value.registeredKeys.length} sounds',
      );
    }
  }

  /// Get all registered bank names
  static List<String> get registeredBanks => _registeredBanks.keys.toList();
}

/// Base class for sound banks
abstract class _SoundBank {
  List<String> get registeredKeys;

  _SoundInfo? getSound(String name);
}

/// Array-format bank (sounds indexed by number or name)
class _ArrayBank extends _SoundBank {
  final List<_SoundInfo> _soundList;
  final List<String> _keyList;

  _ArrayBank(List<dynamic> sounds)
    : _soundList = sounds.map((s) => _SoundInfo.fromDynamic(s)).toList(),
      _keyList = sounds.map((s) => s.toString()).toList() {
    for (var i = 0; i < _keyList.length; i++) {
      final name = _keyList[i];
      if (_keyList.indexOf(name) == i) continue;
      _keyList.remove(name);
      _keyList.add('${name}_$i');
      break;
    }
  }

  @override
  _SoundInfo? getSound(String name) {
    final index = _keyList.indexOf(name);
    if (index >= 0 && index < _soundList.length) {
      return _soundList[index];
    }
    return null;
  }

  void addSound(String key, _SoundInfo sound) {
    final match = RegExp(r'^(.+?)_(\d+)$').firstMatch(key);
    if (match == null) {
      _keyList.add(key);
      _soundList.add(sound);
      return;
    }
    final baseName = match.group(1)!;
    final index = int.parse(match.group(2)!);
    int insertIndex = _keyList.indexOf(baseName);
    if (insertIndex < 0) {
      insertIndex = _keyList.length;
    }
    _keyList.insert(insertIndex + 1, key);
    _soundList.insert(insertIndex + 1, sound);
  }

  _SoundInfo? getByIndex(int index) {
    if (index >= 0 && index < _soundList.length) {
      return _soundList[index];
    }
    return null;
  }

  @override
  List<String> get registeredKeys => _keyList;
}

/// Note-mapped bank (sounds indexed by note name)
class _NoteBank extends _SoundBank {
  final Map<String, _SoundInfo> _soundMap;

  _NoteBank(Map<String, dynamic> sounds)
    : _soundMap = sounds.map(
        (key, value) => MapEntry(key, _SoundInfo.fromDynamic(value)),
      );

  @override
  _SoundInfo? getSound(String name) => _soundMap[name];

  @override
  List<String> get registeredKeys => _soundMap.keys.toList();
}

/// Base URL bank (all sounds inherit this base)
class _BaseBank extends _SoundBank {
  final String baseUrl;
  final List<String> _soundList;

  _BaseBank(this.baseUrl) : _soundList = [];

  void addSound(String name, {String? path, int? transpose = 0}) {
    _soundList.add(name);
  }

  @override
  _SoundInfo? getSound(String name) {
    if (_soundList.contains(name)) {
      return _SoundInfo(url: '$baseUrl/$name', type: _SoundType.sample);
    }
    return null;
  }

  @override
  List<String> get registeredKeys => _soundList;
}

/// Sound information
class _SoundInfo {
  final String url;
  final _SoundType type;
  final int? transpose;
  final bool? loop;
  final double? attack;
  final double? decay;
  final double? sustain;
  final double? release;
  final double? cutoff;
  final double? resonance;

  _SoundInfo({
    required this.url,
    required this.type,
    this.transpose,
    this.loop,
    this.attack,
    this.decay,
    this.sustain,
    this.release,
    this.cutoff,
    this.resonance,
  });

  factory _SoundInfo.fromDynamic(dynamic value) {
    if (value is String) {
      return _SoundInfo(
        url: value,
        type: _SoundType.sample,
        transpose: null,
        loop: null,
        attack: null,
        decay: null,
        sustain: null,
        release: null,
        cutoff: null,
        resonance: null,
      );
    } else if (value is Map<String, dynamic>) {
      final map = value;
      return _SoundInfo(
        url: (map['url']?.toString() ?? map['_base']?.toString() ?? ''),
        type: _parseType(map['type']?.toString()) ?? _SoundType.sample,
        transpose: map['transpose'] as int?,
        loop: map['loop'] as bool?,
        attack: map['attack'] as double?,
        decay: map['decay'] as double?,
        sustain: map['sustain'] as double?,
        release: map['release'] as double?,
        cutoff: map['cutoff'] as double?,
        resonance: map['resonance'] as double?,
      );
    }
    throw ArgumentError('Invalid sound info: $value');
  }

  static _SoundType? _parseType(String? typeStr) {
    if (typeStr == null) return null;
    switch (typeStr!.toLowerCase()) {
      case 'sample':
        return _SoundType.sample;
      case 'synth':
        return _SoundType.synth;
      case 'wavetable':
        return _SoundType.wavetable;
      default:
        return null;
    }
  }
}

enum _SoundType { sample, synth, wavetable }
