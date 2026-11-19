import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';


/// Current/now-playing programme returned by JioTV's EPG endpoint.
class JioTvProgram {
  const JioTvProgram({
    required this.title,
    required this.description,
    required this.start,
    required this.end,
    this.poster,
    this.thumbnail,
    this.category = 'TV Show',
    this.genre = '',
    this.cast = '',
    this.director = '',
    this.id = '',
  });

  final String id;
  final String title;
  final String description;
  final DateTime start;
  final DateTime end;
  final String? poster;
  final String? thumbnail;
  final String category;
  final String genre;
  final String cast;
  final String director;

  String get status {
    final now = DateTime.now();
    if (!now.isBefore(start) && now.isBefore(end)) return 'LIVE';
    return end.isBefore(now) || end.isAtSameMomentAs(now) ? 'CATCH-UP' : 'UPCOMING';
  }

  double get progress {
    final total = end.difference(start).inMilliseconds;
    if (total <= 0) return 0;
    final elapsed = DateTime.now().difference(start).inMilliseconds;
    return (elapsed / total).clamp(0.0, 1.0).toDouble();
  }

  String get timeLabel =>
      '${_clock(start)} - ${_clock(end)}';

  static String _clock(DateTime value) {
    final h = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final m = value.minute.toString().padLeft(2, '0');
    return '$h:$m ${value.hour >= 12 ? 'PM' : 'AM'}';
  }
}

/// JioTV live-channel catalog. The two catalog endpoints are fetched in parallel;
/// the npoint feed enriches the official list with logos, categories and stream URLs.
class JioTvAdapter extends Adapter {
  static const _extraUrl =
      'https://api.npoint.io/9db02feba76eb297fc65?v=1794981838621';

  static const _apiHeaders = <String, String>{
    'User-Agent': 'JioTV',
    'x-api-key': 'l7xx75e822925f184370b2e25170c5d5820a',
    'Origin': 'https://www.jiotv.com',
    'Referer': 'https://www.jiotv.com/tv-guide',
    'Accept': 'application/json',
    'appkey': 'NzNiMDhlYzQyNjJm',
    'os': 'android',
    'devicetype': 'phone',
  };

  static const _playerHeaders = <String, String>{
    'User-Agent': 'JioTV',
    'Origin': 'https://www.jiotv.com',
    'Referer': 'https://www.jiotv.com/tv-guide',
    'Accept': '*/*',
  };

  static const _categoryNames = <int, String>{
    0: 'All',
    5: 'Entertainment',
    6: 'Movies',
    8: 'Sports',
    12: 'News',
    7: 'Kids',
    13: 'Music',
    10: 'Infotainment',
    9: 'Lifestyle',
    15: 'Devotional',
    16: 'Business',
    17: 'Educational',
    18: 'Shopping',
  };

  static const _languageNames = <int, String>{
    1: 'Hindi',
    2: 'Marathi',
    3: 'Punjabi',
    4: 'Urdu',
    5: 'Bengali',
    6: 'English',
    7: 'Malayalam',
    8: 'Tamil',
    9: 'Gujarati',
    10: 'Odia',
    11: 'Telugu',
    12: 'Bhojpuri',
    13: 'Kannada',
    14: 'Assamese',
    15: 'Nepali',
  };

  static final http.Client _client = http.Client();
  static List<Item>? _channelCache;
  static Future<List<Item>>? _channelFlight;
  static final Map<String, Map<String, dynamic>> _rawChannelById = {};

  static const _playbackUserAgent = 'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36';
  static const _workerPlaybackUrl = 'https://eliteapiyash.streamxlive.workers.dev';

  String? _first(Map raw, List<String> keys) {
    for (final key in keys) {
      final value = raw[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return null;
  }

  Future<dynamic> _getJson(Uri uri, Map<String, String> headers) async {
    final response = await _client.get(uri, headers: headers)
        .timeout(const Duration(seconds: 22));
    if (response.statusCode != 200) {
      throw ProviderError('JioTV HTTP ' + response.statusCode.toString());
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ProviderError('JioTV returned invalid JSON.');
    }
  }

  Future<List<Map>> _fetchPrimary() async {
    Object? lastError;
    for (final version in ['v3.1', 'v3.0']) {
      try {
        final uri = Uri.https(
          'jiotv.data.cdn.jio.com',
          '/apis/' + version + '/getMobileChannelList/get/',
          const {
            'os': 'android',
            'devicetype': 'phone',
            'usertype': 'tvYR7NSNn7rymo3F',
          },
        );
        final json = await _getJson(uri, _apiHeaders);
        if (json is! Map || json['result'] is! List) {
          throw ProviderError('JioTV channel list response is missing result[].');
        }
        return (json['result'] as List)
            .whereType<Map>()
            .map((x) => Map<String, dynamic>.from(x))
            .toList();
      } catch (e) {
        lastError = e;
      }
    }
    throw ProviderError('JioTV channel list failed: ' + lastError.toString());
  }

  List<Map> _extractChannels(dynamic value) {
    if (value is List) {
      final direct = value.whereType<Map>()
          .map((x) => Map<String, dynamic>.from(x)).toList();
      if (direct.isNotEmpty) return direct;
      for (final entry in value) {
        final nested = _extractChannels(entry);
        if (nested.isNotEmpty) return nested;
      }
    }
    if (value is Map) {
      final hasName = _first(value, [
        'channel_name', 'name', 'title', 'channelName'
      ]) != null;
      final hasId = _first(value, [
        'channel_id', 'id', 'channelId', 'chid'
      ]) != null;
      if (hasName && hasId) return [Map<String, dynamic>.from(value)];
      for (final key in [
        'channels', 'channelList', 'extraChannels', 'result',
        'data', 'items', 'list', 'results'
      ]) {
        final nested = _extractChannels(value[key]);
        if (nested.isNotEmpty) return nested;
      }
    }
    return const [];
  }

  Future<List<Map>> _fetchExtra() async {
    final json = await _getJson(Uri.parse(_extraUrl), const {
      'Accept': 'application/json',
    });
    return _extractChannels(json);
  }

  Future<List<Map>> _safe(Future<List<Map>> request) async {
    try {
      return await request;
    } catch (_) {
      return const [];
    }
  }

  String _channelId(Map raw) {
    final id = _first(raw, ['channel_id', 'id', 'channelId', 'chid']);
    final numeric = int.tryParse(id ?? '');
    if (numeric != null) return numeric.toString();

    final seed = (id ?? _first(raw, [
      'channel_name', 'name', 'title', 'channelName'
    ]) ?? 'channel').toLowerCase();
    var hash = 0x811c9dc5;
    for (final unit in seed.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return (1000000 + (hash % 900000000)).toString();
  }

  Map<String, dynamic> _mergeMissing(
      Map<String, dynamic> primary, Map<String, dynamic> extra) {
    final merged = Map<String, dynamic>.from(primary);
    for (final entry in extra.entries) {
      final current = merged[entry.key];
      final incoming = entry.value;
      final currentEmpty = current == null || current.toString().trim().isEmpty;
      final incomingEmpty = incoming == null || incoming.toString().trim().isEmpty;
      if (currentEmpty && !incomingEmpty) merged[entry.key] = incoming;
    }
    return merged;
  }

  String? _category(Map raw) {
    final rawName = _first(raw, [
      'channel_genre', 'cat', 'category', 'categoryName', 'genre'
    ]);
    final id = int.tryParse(_first(raw, [
      'channelCategoryId', 'category_id', 'categoryId'
    ]) ?? '');
    if (rawName != null && int.tryParse(rawName) == null) return rawName;
    return _categoryNames[int.tryParse(rawName ?? '') ?? id] ?? 'Other';
  }

  String? _language(Map raw) {
    var name = _first(raw, ['languageName', 'language', 'lang']);
    final id = int.tryParse(_first(raw, [
      'channelLanguageId', 'language_id', 'languageId', 'langId'
    ]) ?? '');
    name ??= _languageNames[id ?? -1];
    if (name == null) return null;
    if (name.toLowerCase() == 'malyalam') return 'Malayalam';
    return name;
  }

  (String?, String?) _logoUrls(Map raw) {
    final logo = _first(raw, [
      'channel_logo', 'logoUrl', 'logo', 'tvg_logo', 'image'
    ]);
    if (logo == null) return (null, null);
    if (logo.startsWith('http://') || logo.startsWith('https://')) {
      return (logo, null);
    }
    final path = logo.replaceFirst(RegExp(r'^/+'), '');
    if (path.startsWith('dare_images/')) {
      return (
        'https://jiotvimages.cdn.jio.com/' + path,
        'https://jiotv.catchup.cdn.jio.com/' + path,
      );
    }
    final imagePath = 'dare_images/images/' + path;
    return (
      'https://jiotvimages.cdn.jio.com/' + imagePath,
      'https://jiotv.catchup.cdn.jio.com/' + imagePath,
    );
  }

  bool _looksLikeVideoUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    final path = uri.path.toLowerCase();
    return path.endsWith('.m3u8') || path.endsWith('.mpd') ||
        path.endsWith('.mp4') || path.endsWith('.ism') ||
        path.endsWith('.ts');
  }

  String? _findStreamUrl(dynamic value, {bool playbackContext = false}) {
    if (value is String) {
      return playbackContext &&
              (value.startsWith('http://') || value.startsWith('https://'))
          ? value.trim()
          : null;
    }
    if (value is List) {
      for (final entry in value) {
        final found = _findStreamUrl(entry, playbackContext: playbackContext);
        if (found != null) return found;
      }
    }
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        final child = entry.value;
        final context = playbackContext ||
            key.contains('stream') || key.contains('playback') ||
            key.contains('player') || key.contains('manifest') ||
            key.contains('source') || key.contains('video');
        if (child is String &&
            (child.startsWith('http://') || child.startsWith('https://'))) {
          final directKey = {
            'streamurl', 'stream', 'playurl', 'playbackurl', 'playback',
            'm3u8', 'hls', 'hlsurl', 'manifesturl', 'videourl',
            'channelurl', 'url', 'link', 'src', 'file', 'video',
          }.contains(key);
          if (directKey || (context &&
              (key == 'url' || key == 'link' || key == 'src' || key == 'file')) ||
              _looksLikeVideoUrl(child)) {
            return child.trim();
          }
        }
      }
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        final context = playbackContext ||
            key.contains('stream') || key.contains('playback') ||
            key.contains('player') || key.contains('manifest') ||
            key.contains('source') || key.contains('video');
        final found = _findStreamUrl(entry.value, playbackContext: context);
        if (found != null) return found;
      }
    }
    return null;
  }

  Map<String, String> _streamHeaders(Map raw) {
    final headers = Map<String, String>.from(_playerHeaders);
    final supplied = raw['headers'] ?? raw['streamHeaders'];
    if (supplied is Map) {
      for (final entry in supplied.entries) {
        if (entry.value != null) {
          headers[entry.key.toString()] = entry.value.toString();
        }
      }
    }
    return headers;
  }

  Item _toItem(Map<String, dynamic> raw) {
    final id = _channelId(raw);
    _rawChannelById[id] = Map<String, dynamic>.from(raw);
    final name = _first(raw, [
      'channel_name', 'name', 'title', 'channelName'
    ]) ?? 'Channel ' + id;
    final category = _category(raw) ?? 'Other';
    final language = _language(raw);
    final logo = _logoUrls(raw);
    final stream = _findStreamUrl(raw);
    final sources = stream == null
        ? const <Source>[]
        : <Source>[
            Source.clean(
              name: 'Live stream',
              url: stream,
              headers: _streamHeaders(raw),
            ),
          ];
    return Item(
      pid: 'jiotv',
      id: id,
      type: 'live',
      title: name,
      poster: logo.$1,
      posterFallback: logo.$2,
      bg: logo.$1,
      plot: language == null ? 'Live TV channel' : 'Live TV · ' + language,
      genres: [category, if (language != null) language],
      sources: sources,
      corner: category,
    );
  }


  static final Map<String, ({DateTime savedAt, List<JioTvProgram> programs})> _epgCache = {};
  static final Map<String, Future<List<JioTvProgram>>> _epgFlights = {};
  static const int _epgCacheMinutes = 5;

  static String _epgText(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    if (value is List) {
      final parts = value.map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty && e.toLowerCase() != 'null');
      final joined = parts.join(', ');
      return joined.isEmpty ? fallback : joined;
    }
    final text = value.toString().trim();
    return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
  }

  static int? _epgEpoch(dynamic value) {
    final parsed = value is num ? value : num.tryParse(value?.toString() ?? '');
    if (parsed == null) return null;
    return (parsed.abs() < 10000000000 ? parsed * 1000 : parsed).round();
  }

  static DateTime? _epgClock(dynamic value, DateTime day) {
    final text = _epgText(value);
    final match = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(text);
    if (match == null) return null;
    final h = int.tryParse(match.group(1)!) ?? 0;
    final m = int.tryParse(match.group(2)!) ?? 0;
    final sec = int.tryParse(match.group(3) ?? '0') ?? 0;
    if (h > 23 || m > 59 || sec > 59) return null;
    return DateTime(day.year, day.month, day.day, h, m, sec);
  }

  static String? _epgImage(dynamic value) {
    var path = _epgText(value);
    if (path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    path = path.replaceFirst(RegExp(r'^/+'), '');
    if (path.startsWith('dare_images/')) {
      return 'https://jiotv.catchup.cdn.jio.com/' + path;
    }
    return 'https://jiotv.catchup.cdn.jio.com/dare_images/shows/' + path;
  }

  static Future<List<JioTvProgram>> schedule(String channelId, int offset) {
    final key = '$channelId|$offset';
    final cached = _epgCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.savedAt) < const Duration(minutes: _epgCacheMinutes)) {
      return Future.value(cached.programs);
    }
    final running = _epgFlights[key];
    if (running != null) return running;
    final flight = _fetchSchedule(channelId, offset);
    _epgFlights[key] = flight;
    return flight.whenComplete(() => _epgFlights.remove(key));
  }

  static Future<List<JioTvProgram>> _fetchSchedule(String channelId, int offset) async {
    final uri = Uri.https(
      'jiotv.data.cdn.jio.com',
      '/apis/v1.3/getepg/get',
      {'offset': '$offset', 'channel_id': channelId, 'langId': '6'},
    );
    final response = await _client.get(uri, headers: _apiHeaders)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw ProviderError('JioTV EPG HTTP ${response.statusCode} (offset $offset)');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final rows = decoded is Map && decoded['epg'] is List
        ? decoded['epg'] as List
        : decoded is List ? decoded : const <dynamic>[];
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day).add(Duration(days: offset));
    final programs = <JioTvProgram>[];
    for (final row in rows.whereType<Map>()) {
      var startMs = _epgEpoch(row['startEpoch'] ?? row['start_epoch']);
      var endMs = _epgEpoch(row['endEpoch'] ?? row['end_epoch']);
      var start = startMs == null ? _epgClock(row['showtime'], day) : DateTime.fromMillisecondsSinceEpoch(startMs);
      var end = endMs == null ? _epgClock(row['endtime'], day) : DateTime.fromMillisecondsSinceEpoch(endMs);
      if (start == null) continue;
      if (end == null) end = start.add(const Duration(hours: 1));
      if (!end.isAfter(start) && end.difference(start).inSeconds <= 0) {
        end = end.add(const Duration(days: 1));
      }
      if (!end.isAfter(start)) continue;
      startMs = start.millisecondsSinceEpoch;
      endMs = end.millisecondsSinceEpoch;
      final poster = _epgImage(row['episodePoster']);
      final thumb = _epgImage(row['episodeThumbnail']) ?? poster;
      final title = _epgText(row['showname'], _epgText(row['showtitle'], 'Program'));
      final genre = _epgText(row['showGenre']);
      final category = _epgText(row['showCategory'], genre.isNotEmpty ? genre : 'TV Show');
      programs.add(JioTvProgram(
        id: _epgText(row['srno'], '${channelId}_${startMs}'),
        title: title,
        description: _epgText(row['description'], 'No episode synopsis available.'),
        start: start,
        end: end,
        poster: poster,
        thumbnail: thumb,
        category: category,
        genre: genre,
        cast: _epgText(row['starCast']),
        director: _epgText(row['director']),
      ));
    }
    programs.sort((a, b) => a.start.compareTo(b.start));
    _epgCache['$channelId|$offset'] = (savedAt: DateTime.now(), programs: programs);
    return programs;
  }

  /// Prefetches the selected day first, then the remaining 14 days with a
  /// bounded worker pool (maximum ten simultaneous CDN requests).
  static Future<void> prefetchSchedule(String channelId, int selectedOffset) async {
    try { await schedule(channelId, selectedOffset); } catch (_) {}
    final offsets = List<int>.generate(15, (i) => i - 7)
      ..remove(selectedOffset)
      ..sort((a, b) => a.abs().compareTo(b.abs()));
    var cursor = 0;
    Future<void> worker() async {
      while (true) {
        final index = cursor++;
        if (index >= offsets.length) return;
        try { await schedule(channelId, offsets[index]); } catch (_) {}
      }
    }
    await Future.wait(List.generate(10, (_) => worker()));
  }

  static Future<JioTvProgram?> currentProgram(String channelId) async {
    final today = await schedule(channelId, 0);
    final now = DateTime.now();
    for (final program in today) {
      if (!now.isBefore(program.start) && now.isBefore(program.end)) return program;
    }
    for (final program in today) {
      if (program.start.isAfter(now)) return program;
    }
    return today.isNotEmpty ? today.last : null;
  }

  static String _playbackValue(dynamic value) {
    if (value == null) return '';
    final text = value.toString().trim();
    return text.toLowerCase() == 'null' ? '' : text;
  }

  static Map<String, dynamic> _playbackRow(dynamic decoded) {
    if (decoded is List) {
      for (final value in decoded) {
        if (value is Map) return Map<String, dynamic>.from(value);
      }
    }
    if (decoded is Map) {
      for (final key in ['data', 'result', 'stream', 'playback']) {
        final nested = decoded[key];
        if (nested is List) {
          for (final value in nested) {
            if (value is Map) return Map<String, dynamic>.from(value);
          }
        }
        if (nested is Map) return Map<String, dynamic>.from(nested);
      }
      return Map<String, dynamic>.from(decoded);
    }
    return <String, dynamic>{};
  }

  static Map<String, dynamic> _fallbackPlayback(Item item) {
    final raw = _rawChannelById[item.id] ?? <String, dynamic>{};
    final values = <String, dynamic>{
      ...raw,
      'channel_url': raw['channel_url'] ?? raw['channelUrl'],
      'mpd_url': raw['mpd_url'] ?? raw['mpdUrl'],
      'ready_to_use_link': raw['ready_to_use_link'] ?? raw['readyToUseLink'],
    };
    final extras = <String, String>{
      'Origin': 'https://www.jiotv.com',
      'Referer': 'https://www.jiotv.com/tv-guide',
      'Accept': '*/*',
    };
    final suppliedHeaders = raw['headers'] ?? raw['streamHeaders'] ?? raw['extraHeaders'];
    if (suppliedHeaders is Map) {
      for (final entry in suppliedHeaders.entries) {
        if (entry.key != null && entry.value != null) {
          extras[entry.key.toString()] = entry.value.toString();
        }
      }
    }

    String url = '';
    String cookie = _playbackValue(raw['cookie']);
    String allKeys = _playbackValue(raw['all_keys'] ?? raw['allKeys']);
    String drmScheme = _playbackValue(raw['drmScheme'] ?? raw['drm_scheme']);
    String licenseUrl = _playbackValue(raw['drmLicense'] ?? raw['drm_license'] ?? raw['license_url']);

    for (final key in ['ready_to_use_link', 'channel_url', 'mpd_url', 'stream_url', 'channelUrl']) {
      final candidate = _playbackValue(values[key]);
      if (candidate.isEmpty) continue;
      final parts = candidate.split('|');
      if (url.isEmpty && (parts.first.startsWith('http://') || parts.first.startsWith('https://'))) {
        url = parts.first.trim();
      }
      for (final part in parts.skip(1)) {
        final index = part.indexOf('=');
        if (index <= 0) continue;
        final name = part.substring(0, index).trim().toLowerCase();
        final value = part.substring(index + 1).trim();
        if (name == 'cookie') cookie = value;
        if (name == 'all_keys' || name == 'allkeys') allKeys = value;
        if (name == 'drmscheme' || name == 'drm_scheme') drmScheme = value;
        if (name == 'drmlicense' || name == 'licenseurl' || name == 'license_url') licenseUrl = value;
        if (name == 'useragent' || name == 'user_agent') extras['User-Agent'] = value;
        if (name == 'referer') extras['Referer'] = value;
        if (name == 'origin') extras['Origin'] = value;
      }
    }

    if (url.isEmpty && item.sources.isNotEmpty) {
      url = item.sources.first.url ?? '';
      if (cookie.isEmpty) cookie = _playbackValue(item.sources.first.headers['Cookie']);
      extras.addAll(item.sources.first.headers);
    }
    if (url.isEmpty) {
      throw ProviderError('JioTV playback URL is missing in Worker response and npoint fallback.');
    }
    if (drmScheme.isEmpty && allKeys.isNotEmpty) drmScheme = 'clearkey';
    final userAgent = _playbackValue(extras.remove('User-Agent'));
    return <String, dynamic>{
      'url': url,
      'cookie': cookie,
      'allKeys': allKeys,
      'drmScheme': drmScheme.toLowerCase(),
      'licenseUrl': licenseUrl,
      'userAgent': userAgent.isEmpty ? _playbackUserAgent : userAgent,
      'extraHeaders': extras,
    };
  }

  /// Resolves JioTV playback through the primary Worker API and falls back to
  /// the original npoint channel object whenever the Worker cannot provide a stream.
  static Future<Map<String, dynamic>> resolvePlayback(Item item) async {
    final numericId = int.tryParse(item.id) ?? 0;
    if (numericId > 0 && numericId < 1000000) {
      try {
        final response = await _client.get(
          Uri.parse(_workerPlaybackUrl + '?id=' + Uri.encodeQueryComponent(item.id)),
          headers: const {
            'User-Agent': _playbackUserAgent,
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 18));
        if (response.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          final row = _playbackRow(decoded);
          final status = _playbackValue(row['status']).toLowerCase();
          final url = _playbackValue(
            row['mpd_url'] ?? row['stream_url'] ?? row['channel_url'] ??
            row['hls_url'] ?? row['ready_to_use_link'] ?? row['readyToUseLink'] ?? row['url'],
          );
          if (url.isNotEmpty && (status.isEmpty || const {'success', 'ok', 'true', '200', 'available'}.contains(status))) {
            final rawHeaders = row['extraHeaders'] ?? row['headers'];
            final headers = <String, String>{
              'Origin': 'https://www.jiotv.com',
              'Referer': 'https://www.jiotv.com/tv-guide',
              'Accept': '*/*',
            };
            if (rawHeaders is Map) {
              for (final entry in rawHeaders.entries) {
                if (entry.key != null && entry.value != null) {
                  headers[entry.key.toString()] = entry.value.toString();
                }
              }
            }
            var cookie = _playbackValue(row['cookie']);
            var keys = _playbackValue(row['all_keys'] ?? row['allKeys']);
            var scheme = _playbackValue(row['drmScheme'] ?? row['drm_scheme']).toLowerCase();
            var license = _playbackValue(row['drmLicense'] ?? row['license_url'] ?? row['drm_license']);
            var userAgent = _playbackValue(row['userAgent'] ?? row['user_agent']);
            final pipeParts = url.split('|');
            for (final part in pipeParts.skip(1)) {
              final index = part.indexOf('=');
              if (index <= 0) continue;
              final name = part.substring(0, index).trim().toLowerCase();
              final value = part.substring(index + 1).trim();
              if (name == 'cookie') cookie = value;
              if (name == 'drmscheme' || name == 'drm_scheme') scheme = value.toLowerCase();
              if (name == 'drmlicense' || name == 'licenseurl' || name == 'license_url') license = value;
              if (name == 'useragent' || name == 'user_agent') userAgent = value;
              if (name == 'all_keys' || name == 'allkeys') keys = value;
              if (name == 'referer' || name == 'origin') headers[name == 'referer' ? 'Referer' : 'Origin'] = value;
            }
            if (scheme.isEmpty && keys.isNotEmpty) scheme = 'clearkey';
            return <String, dynamic>{
              'url': pipeParts.first.trim(),
              'cookie': cookie,
              'allKeys': keys,
              'drmScheme': scheme,
              'licenseUrl': license,
              'userAgent': userAgent.isEmpty ? _playbackUserAgent : userAgent,
              'extraHeaders': headers,
            };
          }
        }
      } catch (_) {
        // Continue with the npoint fallback below (including 403/451/410).
      }
    }
    return _fallbackPlayback(item);
  }

  Future<List<Item>> _loadChannels() async {
    if (_channelCache != null) return _channelCache!;
    if (_channelFlight != null) return _channelFlight!;

    final flight = () async {
      // Fetch both feeds at the same time. Either feed can still populate the grid
      // if the other endpoint is temporarily unavailable.
      final feeds = await Future.wait<List<Map>>([
        _safe(_fetchPrimary()),
        _safe(_fetchExtra()),
      ]);
      final primary = feeds[0];
      final extra = feeds[1];
      if (primary.isEmpty && extra.isEmpty) {
        throw ProviderError('JioTV could not load channels from either API.');
      }

      final merged = <String, Map<String, dynamic>>{};
      for (final channel in primary) {
        final id = _channelId(channel);
        merged[id] = Map<String, dynamic>.from(channel);
      }
      for (final channel in extra) {
        final id = _channelId(channel);
        final current = merged[id];
        merged[id] = current == null
            ? Map<String, dynamic>.from(channel)
            : _mergeMissing(current, Map<String, dynamic>.from(channel));
      }

      final ordered = merged.values.toList()
        ..sort((a, b) {
          final orderA = int.tryParse(_first(a, [
                'channel_order', 'channelOrder', 'order'
              ]) ?? '') ?? 0x7fffffff;
          final orderB = int.tryParse(_first(b, [
                'channel_order', 'channelOrder', 'order'
              ]) ?? '') ?? 0x7fffffff;
          if (orderA != orderB) return orderA.compareTo(orderB);
          final nameA = (_first(a, [
                'channel_name', 'name', 'title', 'channelName'
              ]) ?? '').toLowerCase();
          final nameB = (_first(b, [
                'channel_name', 'name', 'title', 'channelName'
              ]) ?? '').toLowerCase();
          return nameA.compareTo(nameB);
        });
      return ordered.map(_toItem).toList();
    }();

    _channelFlight = flight;
    try {
      final channels = await flight;
      _channelCache = channels;
      return channels;
    } finally {
      _channelFlight = null;
    }
  }

  @override
  Future<List<Shelf>> home(ProviderDef p) async {
    final channels = await _loadChannels();
    if (channels.isEmpty) throw ProviderError('JioTV returned no channels.');
    return [Shelf('Live TV Channels', channels)];
  }

  @override
  Future<List<Item>> search(ProviderDef p, String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final channels = await _loadChannels();
    return channels.where((item) =>
        item.title.toLowerCase().contains(q) ||
        item.genres.any((tag) => tag.toLowerCase().contains(q)) ||
        (item.plot ?? '').toLowerCase().contains(q)).toList();
  }

  @override
  Future<Item> detail(ProviderDef p, Item item) async => item;

  @override
  Future<List<Source>> sources(ProviderDef p, Item item, Episode? ep) async {
    if (item.sources.isEmpty) {
      throw ProviderError(
        'No direct stream URL was included for this channel in the extra channels feed.',
      );
    }
    return item.sources;
  }
}
