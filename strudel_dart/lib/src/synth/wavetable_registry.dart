import 'dart:typed_data';

/// Holds wavetable definitions and decoded frame data for synth rendering.
class WavetableRegistry {
  static final Map<String, WavetableDefinition> _definitions = {};
  static final Map<String, WavetableData> _tables = {};

  /// Register a wavetable definition by key.
  static void registerDefinition(
    String key,
    List<String> urls, {
    int frameLen = 2048,
  }) {
    final normalized = key.trim().toLowerCase();
    _definitions[normalized] = WavetableDefinition(
      key: normalized,
      urls: urls,
      frameLen: frameLen,
    );
  }

  /// Get the wavetable definition for the given key.
  static WavetableDefinition? definition(String key) {
    return _definitions[key.trim().toLowerCase()];
  }

  /// Returns true if a definition exists for the given key.
  static bool hasDefinition(String key) => definition(key) != null;

  /// Registers a decoded wavetable for a specific index.
  static void registerTable(
    String key,
    int index,
    WavetableData data,
  ) {
    _tables[_tableKey(key, index)] = data;
  }

  /// Looks up a decoded wavetable for the given key and index.
  static WavetableData? table(String key, int index) {
    return _tables[_tableKey(key, index)];
  }

  /// Returns true if decoded data is available for key and index.
  static bool hasTable(String key, int index) {
    return _tables.containsKey(_tableKey(key, index));
  }

  static String _tableKey(String key, int index) {
    return '${key.trim().toLowerCase()}:$index';
  }
}

/// Defines a wavetable source before it is decoded.
class WavetableDefinition {
  const WavetableDefinition({
    required this.key,
    required this.urls,
    required this.frameLen,
  });

  final String key;
  final List<String> urls;
  final int frameLen;
}

/// Decoded wavetable frames.
class WavetableData {
  const WavetableData({required this.frames, required this.frameLen});

  final List<Float32List> frames;
  final int frameLen;
}
