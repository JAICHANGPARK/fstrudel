import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class SampleManager {
  static const String _drumMachinesBaseUrl =
      'https://raw.githubusercontent.com/ritchse/tidal-drum-machines/main/machines/';
  static const String _dirtSamplesBaseUrl =
      'https://strudel.b-cdn.net/Dirt-Samples/';

  // Mappings for common banks and sounds
  // Format: {bank_sound: path_suffix}
  static const Map<String, List<String>> _sampleMap = {
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

  final Map<String, String> _cache = {};

  Future<String?> getSamplePath(String sound, {String? bank, int n = 0}) async {
    String key;
    if (bank != null && bank.isNotEmpty) {
      // Normalize bank names (strudel often uses lowercase or shorthands)
      String normalizedBank = bank;
      if (bank.toLowerCase() == 'tr909' || bank.toLowerCase() == '909') {
        normalizedBank = 'RolandTR909';
      } else if (bank.toLowerCase() == 'tr808' || bank.toLowerCase() == '808') {
        normalizedBank = 'RolandTR808';
      } else if (bank.toLowerCase() == 'jazz') {
        normalizedBank = 'jazz';
      }
      key = '${normalizedBank}_$sound';
    } else {
      key = sound;
    }

    if (!_sampleMap.containsKey(key)) {
      print('SampleManager: No mapping found for $key');
      return null;
    }

    final paths = _sampleMap[key]!;
    final pathSuffix = paths[n % paths.length];

    // Determine base URL based on the path prefix
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

    // Check local storage
    final file = await _getLocalFile(pathSuffix);
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
}
