import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:strudel_dart/strudel_dart.dart';

class WavetableManager {
  final Map<String, Future<void>> _pendingTables = {};
  final Map<String, Future<Uint8List>> _pendingDownloads = {};

  bool isWavetableSound(String sound) {
    final key = _normalizeSound(sound);
    return WavetableRegistry.hasDefinition(key) || key.startsWith('wt_');
  }

  Future<bool> prepare(String sound, Map<String, dynamic> params) async {
    final request = _parseRequest(sound, params);
    if (WavetableRegistry.hasTable(request.key, request.index)) {
      return true;
    }
    final definition = WavetableRegistry.definition(request.key);
    if (definition == null) {
      return !request.key.startsWith('wt_');
    }
    if (definition.urls.isEmpty) return false;

    final index = request.index % definition.urls.length;
    if (WavetableRegistry.hasTable(request.key, index)) {
      return true;
    }
    await _loadTable(request.key, index, definition);
    return WavetableRegistry.hasTable(request.key, index);
  }

  Future<void> registerTablesFromUrl(
    String url, {
    int frameLen = 2048,
  }) async {
    final resolvedUrl = _resolveTableUrl(url);
    final json = await _fetchJson(resolvedUrl);
    if (json == null) return;
    final base = _baseFromUrl(resolvedUrl);
    registerTablesFromJson(json, baseUrl: base, frameLen: frameLen);
  }

  void registerTablesFromJson(
    Map<String, dynamic> json, {
    String? baseUrl,
    int frameLen = 2048,
  }) {
    var base =
        json['_base']?.toString() ?? baseUrl ?? '';
    base = _resolveTableBase(base);

    for (final entry in json.entries) {
      if (entry.key == '_base') continue;
      final paths = _extractPaths(entry.value);
      if (paths.isEmpty) continue;
      final urls = paths
          .map((path) => _resolveUrl(base, path))
          .where((path) => path.toLowerCase().endsWith('.wav'))
          .toList();
      if (urls.isNotEmpty) {
        WavetableRegistry.registerDefinition(
          entry.key,
          urls,
          frameLen: frameLen,
        );
      }
    }
  }

  Future<void> registerWavetablesFromSampleMap(
    dynamic sampleMap, {
    String? baseUrl,
  }) async {
    if (sampleMap is String) {
      final resolvedUrl = _resolveSampleMapUrl(sampleMap);
      final json = await _fetchJson(resolvedUrl);
      if (json == null) return;
      final baseFromUrl = _baseFromUrl(resolvedUrl);
      final base =
          baseUrl ?? json['_base']?.toString() ?? baseFromUrl;
      _registerWavetablesFromMap(json, base);
      return;
    }

    if (sampleMap is Map<String, dynamic>) {
      final base =
          baseUrl ?? sampleMap['_base']?.toString() ?? '';
      _registerWavetablesFromMap(sampleMap, base);
      return;
    }

    print('WavetableManager: Unsupported sample map type');
  }

  Future<void> _loadTable(
    String key,
    int index,
    WavetableDefinition definition,
  ) async {
    final loadKey = '$key:$index';
    final pending = _pendingTables[loadKey];
    if (pending != null) return pending;

    final future = () async {
      final url = definition.urls[index % definition.urls.length];
      final bytes = await _loadUrl(url);
      final data = _decodeWavetable(bytes, definition.frameLen);
      WavetableRegistry.registerTable(key, index, data);
    }();

    _pendingTables[loadKey] = future;
    try {
      await future;
    } finally {
      _pendingTables.remove(loadKey);
    }
  }

  Future<Uint8List> _loadUrl(String url) async {
    final cached = _pendingDownloads[url];
    if (cached != null) return cached;
    final future = _loadUrlInternal(url);
    _pendingDownloads[url] = future;
    try {
      return await future;
    } finally {
      _pendingDownloads.remove(url);
    }
  }

  Future<Uint8List> _loadUrlInternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.scheme == 'file' || uri.scheme.isEmpty)) {
      final path = uri.scheme == 'file' ? uri.toFilePath() : url;
      return File(path).readAsBytes();
    }

    final file = await _getLocalFileForUrl(url);
    if (await file.exists()) {
      return file.readAsBytes();
    }

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to download wavetable: $url');
    }
    await file.parent.create(recursive: true);
    await file.writeAsBytes(response.bodyBytes);
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>?> _fetchJson(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        print('WavetableManager: Failed to load $url');
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        print('WavetableManager: Invalid JSON format at $url');
        return null;
      }
      return decoded;
    } catch (e) {
      print('WavetableManager: Error loading $url: $e');
      return null;
    }
  }

  void _registerWavetablesFromMap(
    Map<String, dynamic> map,
    String baseUrl,
  ) {
    var base = _resolveSampleBase(baseUrl);
    for (final entry in map.entries) {
      final key = entry.key;
      if (key == '_base') continue;
      if (!key.toLowerCase().startsWith('wt_')) continue;

      var entryBase = base;
      final value = entry.value;
      if (value is Map && value['_base'] is String) {
        entryBase = _resolveSampleBase(value['_base'] as String);
      }

      final paths = _extractPaths(value);
      if (paths.isEmpty) continue;
      final urls = paths
          .map((path) => _resolveUrl(entryBase, path))
          .where((path) => path.toLowerCase().endsWith('.wav'))
          .toList();
      if (urls.isNotEmpty) {
        WavetableRegistry.registerDefinition(key, urls);
      }
    }
  }

  String _resolveTableUrl(String url) {
    var resolved = url.trim();
    if (resolved.startsWith('github:')) {
      resolved = _githubPath(resolved, 'strudel.json');
    }
    if (resolved.startsWith('local:')) {
      resolved = 'http://localhost:5432';
    }
    return resolved;
  }

  String _resolveTableBase(String baseUrl) {
    var resolved = baseUrl.trim();
    if (resolved.startsWith('github:')) {
      resolved = _githubPath(resolved, '');
    }
    return resolved;
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

  String _normalizeSound(String sound) {
    return sound.trim().toLowerCase();
  }

  _WavetableRequest _parseRequest(String sound, Map<String, dynamic> params) {
    var key = _normalizeSound(sound);
    var index = 0;
    final nVal = params['n'];
    if (nVal is num) {
      index = nVal.toInt();
    } else if (nVal is String) {
      index = int.tryParse(nVal) ?? 0;
    }
    final colonIndex = key.lastIndexOf(':');
    if (colonIndex > 0) {
      final parsed = int.tryParse(key.substring(colonIndex + 1));
      if (parsed != null && index == 0) {
        index = parsed;
      }
      key = key.substring(0, colonIndex);
    }
    return _WavetableRequest(key: key, index: index);
  }

  List<String> _extractPaths(dynamic value) {
    if (value is String) return [value];
    if (value is List) {
      return value.whereType<String>().toList();
    }
    if (value is Map) {
      final paths = <String>[];
      for (final entry in value.entries) {
        if (entry.key == '_base') continue;
        final v = entry.value;
        if (v is String) {
          paths.add(v);
        } else if (v is List) {
          paths.addAll(v.whereType<String>());
        }
      }
      return paths;
    }
    return [];
  }

  String _resolveUrl(String base, String path) {
    final schemeMatch = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:');
    if (schemeMatch.hasMatch(path)) {
      return path;
    }
    return '${_ensureTrailingSlash(base)}$path';
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
    final cacheDir = await getTemporaryDirectory();
    final localPath =
        p.join(cacheDir.path, 'strudel_cache', 'wavetables', pathSuffix);
    return File(localPath);
  }
}

class _WavetableRequest {
  const _WavetableRequest({required this.key, required this.index});

  final String key;
  final int index;
}

WavetableData _decodeWavetable(Uint8List bytes, int frameLen) {
  final wav = _parseWav(bytes);
  final samples = wav.samples;
  final total = samples.length;
  final numFrames = math.max(1, total ~/ frameLen);
  final frames = List<Float32List>.generate(numFrames, (i) {
    final start = i * frameLen;
    final end = math.min(start + frameLen, total);
    return Float32List.sublistView(samples, start, end);
  });
  return WavetableData(frames: frames, frameLen: frameLen);
}

_WavData _parseWav(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  if (data.lengthInBytes < 12) {
    throw Exception('Invalid WAV header');
  }
  final riff = _readString(data, 0, 4);
  final wave = _readString(data, 8, 4);
  if (riff != 'RIFF' || wave != 'WAVE') {
    throw Exception('Invalid WAV file');
  }

  int? audioFormat;
  int? numChannels;
  int? bitsPerSample;
  int? dataOffset;
  int? dataSize;

  var offset = 12;
  while (offset + 8 <= data.lengthInBytes) {
    final id = _readString(data, offset, 4);
    final size = data.getUint32(offset + 4, Endian.little);
    final chunkStart = offset + 8;
    if (id == 'fmt ') {
      audioFormat = data.getUint16(chunkStart, Endian.little);
      numChannels = data.getUint16(chunkStart + 2, Endian.little);
      bitsPerSample = data.getUint16(chunkStart + 14, Endian.little);
    } else if (id == 'data') {
      dataOffset = chunkStart;
      dataSize = size;
    }
    offset = chunkStart + size + (size & 1);
  }

  if (audioFormat == null ||
      numChannels == null ||
      bitsPerSample == null ||
      dataOffset == null ||
      dataSize == null) {
    throw Exception('Invalid WAV format');
  }

  final bytesPerSample = bitsPerSample ~/ 8;
  final frameCount =
      dataSize ~/ (bytesPerSample * numChannels);
  final samples = Float32List(frameCount);
  var sampleOffset = dataOffset;
  for (var i = 0; i < frameCount; i++) {
    final value = _readSample(
      data,
      sampleOffset,
      audioFormat,
      bitsPerSample,
    );
    samples[i] = value;
    sampleOffset += bytesPerSample * numChannels;
  }
  return _WavData(samples: samples);
}

double _readSample(
  ByteData data,
  int offset,
  int audioFormat,
  int bitsPerSample,
) {
  if (audioFormat == 3) {
    if (bitsPerSample == 32) {
      return data.getFloat32(offset, Endian.little).clamp(-1.0, 1.0);
    }
    if (bitsPerSample == 64) {
      return data.getFloat64(offset, Endian.little).clamp(-1.0, 1.0);
    }
  }

  if (audioFormat == 1) {
    if (bitsPerSample == 16) {
      return (data.getInt16(offset, Endian.little) / 32768.0)
          .clamp(-1.0, 1.0);
    }
    if (bitsPerSample == 24) {
      final b0 = data.getUint8(offset);
      final b1 = data.getUint8(offset + 1);
      final b2 = data.getUint8(offset + 2);
      var sample = b0 | (b1 << 8) | (b2 << 16);
      if (sample & 0x800000 != 0) {
        sample |= ~0xffffff;
      }
      return (sample / 8388608.0).clamp(-1.0, 1.0);
    }
    if (bitsPerSample == 32) {
      return (data.getInt32(offset, Endian.little) / 2147483648.0)
          .clamp(-1.0, 1.0);
    }
  }

  throw Exception('Unsupported WAV format: $audioFormat/$bitsPerSample');
}

String _readString(ByteData data, int offset, int length) {
  final codes = <int>[];
  for (var i = 0; i < length; i++) {
    codes.add(data.getUint8(offset + i));
  }
  return String.fromCharCodes(codes);
}

class _WavData {
  const _WavData({required this.samples});

  final Float32List samples;
}
