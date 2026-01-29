typedef SamplesLoader = Future<void> Function(
  dynamic sampleMap, {
  String? baseUrl,
  Map<String, dynamic>? options,
});

typedef TablesLoader = Future<void> Function(
  dynamic source, {
  int? frameLen,
  dynamic json,
  Map<String, dynamic>? options,
});

/// Hooks for loading external sample and wavetable resources.
class StrudelResources {
  static SamplesLoader? onSamples;
  static TablesLoader? onTables;
}
