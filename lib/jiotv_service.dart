import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

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

  static const _workerEndpoint =
      'https://eliteapiyash.streamxlive.workers.dev';
  static const _workerUserAgent =
      'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36';
  static const _workerHeaders = <String, String>{
    'User-Agent': _workerUserAgent,
    'Accept': 'application/json',
  };

  static final http.Client _client = http.Client();
  static List<Item>? _channelCache;
  static Future<List<Item>>? _channelFlight;
  static final Map<String, Map<String, dynamic>> _rawChannelCache = {};

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

      _rawChannelCache
        ..clear()
        ..addAll(merged);

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


  List<Map> _flattenPlaybackMaps(dynamic value) {
    final result = <Map>[];
    final visited = <int>{};
    void visit(dynamic node, int depth) {
      if (depth > 7 || node == null) return;
      if (node is List) {
        for (final entry in node) {
          visit(entry, depth + 1);
        }
        return;
      }
      if (node is! Map) return;
      if (!visited.add(identityHashCode(node))) return;
      result.add(node);
      for (final key in [
        'data', 'result', 'play_data', 'playData', 'playback',
        'playbackInfo', 'playback_info', 'stream', 'source',
      ]) {
        if (node.containsKey(key)) visit(node[key], depth + 1);
      }
    }
    visit(value, 0);
    return result;
  }

  String? _stringAcross(List<Map> maps, List<String> keys) {
    for (final key in keys) {
      for (final map in maps) {
        for (final entry in map.entries) {
          if (entry.key.toString().toLowerCase() != key.toLowerCase()) continue;
          final value = entry.value;
          if (value is String || value is num) {
            final text = value.toString().trim();
            if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
          }
        }
      }
    }
    return null;
  }

  Map<String, String> _pipeParameters(String raw) {
    final result = <String, String>{};
    for (final part in raw.split('&')) {
      final index = part.indexOf('=');
      if (index <= 0) continue;
      try {
        final key = Uri.decodeComponent(part.substring(0, index)).trim().toLowerCase();
        final value = Uri.decodeComponent(part.substring(index + 1)).trim();
        if (key.isNotEmpty && value.isNotEmpty) result[key] = value;
      } catch (_) {}
    }
    return result;
  }

  String _hexToBase64Url(String value) {
    final clean = value.trim().replaceAll('-', '');
    if (clean.length == 32 && RegExp(r'^[0-9a-fA-F]{32}
}


class JioTvProgram {
  const JioTvProgram({
    required this.id,
    required this.channelId,
    required this.title,
    required this.description,
    required this.startEpochMs,
    required this.endEpochMs,
    required this.posterUrl,
    required this.thumbnailUrl,
    required this.category,
    required this.genre,
    required this.starCast,
    required this.director,
  });

  final String id;
  final String channelId;
  final String title;
  final String description;
  final int startEpochMs;
  final int endEpochMs;
  final String? posterUrl;
  final String? thumbnailUrl;
  final String category;
  final String genre;
  final String starCast;
  final String director;

  bool isLiveAt([DateTime? at]) {
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    return now >= startEpochMs && now < endEpochMs;
  }

  bool isPastAt([DateTime? at]) {
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    return endEpochMs <= now;
  }

  String statusAt([DateTime? at]) =>
      isLiveAt(at) ? 'LIVE' : (isPastAt(at) ? 'CATCH-UP' : 'UPCOMING');

  double progressAt([DateTime? at]) {
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final span = endEpochMs - startEpochMs;
    if (span <= 0) return 0;
    return ((now - startEpochMs) / span).clamp(0.0, 1.0).toDouble();
  }

  int get durationMinutes =>
      ((endEpochMs - startEpochMs) / 60000).round();

  String get timeLabel =>
      _formatTime(startEpochMs) + ' - ' + _formatTime(endEpochMs);

  static String _formatTime(int epochMs) {
    final time = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute ' + (time.hour >= 12 ? 'PM' : 'AM');
  }
}

/// EPG cache is scoped to channel + day offset. Selected day is loaded first;
/// the remaining 14 days are warmed in nearest-first order with max 10 requests.
class JioTvEpgService {
  static const _endpoint =
      'https://jiotv.data.cdn.jio.com/apis/v1.3/getepg/get';
  static const _cacheTtl = Duration(minutes: 10);
  static const _headers = <String, String>{
    'User-Agent': 'JioTV',
    'x-api-key': 'l7xx75e822925f184370b2e25170c5d5820a',
    'Origin': 'https://www.jiotv.com',
    'Referer': 'https://www.jiotv.com/tv-guide',
    'Accept': 'application/json',
    'appkey': 'NzNiMDhlYzQyNjJm',
    'os': 'android',
    'devicetype': 'phone',
  };

  static final http.Client _client = http.Client();
  static final Map<String, List<JioTvProgram>> _cache = {};
  static final Map<String, DateTime> _cacheTimes = {};
  static final Map<String, Future<List<JioTvProgram>>> _inFlight = {};

  static String _key(String channelId, int offset) => '$channelId|$offset';

  static String _text(dynamic value) {
    if (value == null) return '';
    if (value is List) {
      return value.map(_text).where((x) => x.isNotEmpty).join(', ').trim();
    }
    return value.toString().trim();
  }

  static int? _epoch(dynamic value) {
    if (value == null) return null;
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value.toString().trim());
    if (parsed == null || parsed <= 0) return null;
    final integer = parsed.round();
    return integer < 10000000000 ? integer * 1000 : integer;
  }

  static DateTime? _timeForOffset(dynamic value, int offset) {
    final raw = _text(value);
    if (raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    final second = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;
    if (hour == null || minute == null || hour < 0 || hour > 23 ||
        minute < 0 || minute > 59 || second < 0 || second > 59) {
      return null;
    }
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day).add(Duration(days: offset));
    return DateTime(day.year, day.month, day.day, hour, minute, second);
  }

  static String? _imageUrl(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final path = raw.replaceFirst(RegExp(r'^/+'), '');
    if (path.startsWith('dare_images/')) {
      return 'https://jiotv.catchup.cdn.jio.com/' + path;
    }
    return 'https://jiotv.catchup.cdn.jio.com/dare_images/shows/' + path;
  }

  static JioTvProgram? _parse(Map raw, String channelId, int offset) {
    final start = _epoch(raw['startEpoch']) ??
        _timeForOffset(raw['showtime'], offset)?.millisecondsSinceEpoch;
    if (start == null) return null;

    var end = _epoch(raw['endEpoch']) ??
        _timeForOffset(raw['endtime'], offset)?.millisecondsSinceEpoch;
    if (end == null) {
      end = start + 3600000;
    } else if (end <= start && raw['endEpoch'] == null) {
      end += 86400000;
    }
    if (end <= start) end = start + 3600000;

    final showName = _text(raw['showname']);
    final showTitle = _text(raw['showtitle']);
    final title = showName.isNotEmpty
        ? showName
        : (showTitle.isNotEmpty ? showTitle : 'Program');
    final genre = _text(raw['showGenre']);
    final showCategory = _text(raw['showCategory']);
    final category = showCategory.isNotEmpty
        ? showCategory
        : (genre.isNotEmpty ? genre : 'TV Show');
    final srno = _text(raw['srno']);
    final poster = _imageUrl(raw['episodePoster']);
    final thumbnail = _imageUrl(raw['episodeThumbnail']) ?? poster;

    return JioTvProgram(
      id: srno.isNotEmpty ? srno : channelId + '_' + start.toString(),
      channelId: channelId,
      title: title,
      description: _text(raw['description']).isNotEmpty
          ? _text(raw['description'])
          : 'No episode synopsis available.',
      startEpochMs: start,
      endEpochMs: end,
      posterUrl: poster,
      thumbnailUrl: thumbnail,
      category: category,
      genre: genre,
      starCast: _text(raw['starCast']),
      director: _text(raw['director']),
    );
  }

  static Future<List<JioTvProgram>> loadDay(
    String channelId,
    int offset, {
    bool forceRefresh = false,
  }) async {
    if (offset < -7 || offset > 7) {
      throw ArgumentError.value(offset, 'offset', 'EPG offset must be -7..7');
    }
    final key = _key(channelId, offset);
    final cached = _cache[key];
    final cachedAt = _cacheTimes[key];
    if (!forceRefresh && cached != null && cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return cached;
    }
    if (_inFlight.containsKey(key)) return _inFlight[key]!;

    final future = () async {
      final uri = Uri.parse(_endpoint).replace(queryParameters: {
        'offset': offset.toString(),
        'channel_id': channelId,
        'langId': '6',
      });
      final response = await _client.get(uri, headers: _headers)
          .timeout(const Duration(seconds: 22));
      if (response.statusCode != 200) {
        throw ProviderError('JioTV EPG HTTP ' + response.statusCode.toString());
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['epg'] is! List) {
        throw ProviderError('JioTV EPG response is missing epg[].');
      }
      final programs = (decoded['epg'] as List)
          .whereType<Map>()
          .map((entry) => _parse(entry, channelId, offset))
          .whereType<JioTvProgram>()
          .toList()
        ..sort((a, b) => a.startEpochMs.compareTo(b.startEpochMs));
      _cache[key] = programs;
      _cacheTimes[key] = DateTime.now();
      return programs;
    }();

    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  static Future<void> prefetch(
    String channelId, {
    int selectedOffset = 0,
  }) async {
    await loadDay(channelId, selectedOffset);
    final offsets = <int>[];
    for (var distance = 1; distance <= 7; distance++) {
      for (final offset in [-distance, distance]) {
        if (offset != selectedOffset) offsets.add(offset);
      }
    }
    var next = 0;
    final workers = offsets.length < 10 ? offsets.length : 10;
    await Future.wait(List.generate(workers, (_) async {
      while (next < offsets.length) {
        final offset = offsets[next++];
        try {
          await loadDay(channelId, offset);
        } catch (_) {
          // A failed day remains retryable when the user opens that date.
        }
      }
    }));
  }
}
).hasMatch(clean)) {
      final bytes = <int>[
        for (var i = 0; i < 32; i += 2)
          int.parse(clean.substring(i, i + 2), radix: 16),
      ];
      return base64Url.encode(bytes).replaceAll('=', '');
    }
    return clean.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
  }

  Map<String, String> _parseClearKeyPairs(Iterable<dynamic> values) {
    final pairs = <String, String>{};
    void add(dynamic value) {
      if (value == null) return;
      if (value is Map) {
        final keys = value['keys'];
        if (keys is List) {
          for (final entry in keys.whereType<Map>()) {
            final kid = _first(entry, ['kid', 'keyId', 'key_id']);
            final key = _first(entry, ['k', 'key', 'value']);
            if (kid != null && key != null) pairs[kid] = key;
          }
        } else {
          for (final entry in value.entries) {
            if (entry.value != null &&
                entry.key.toString().toLowerCase() != 'type') {
              pairs[entry.key.toString()] = entry.value.toString();
            }
          }
        }
        return;
      }
      if (value is! String) return;
      final text = value.trim();
      if (text.isEmpty || text.startsWith('http://') || text.startsWith('https://')) return;
      if (text.startsWith('{')) {
        try {
          add(jsonDecode(text));
          return;
        } catch (_) {}
      }
      for (final part in text.split(RegExp(r'[,;\n]+'))) {
        final index = part.indexOf(':');
        if (index <= 0) continue;
        final kid = part.substring(0, index).trim();
        final key = part.substring(index + 1).trim();
        if (kid.isNotEmpty && key.isNotEmpty) pairs[kid] = key;
      }
    }

    for (final value in values) {
      add(value);
    }
    return pairs;
  }

  String _canonicalHeaderName(String name) {
    switch (name.toLowerCase()) {
      case 'user-agent':
        return 'User-Agent';
      case 'cookie':
        return 'Cookie';
      case 'referer':
      case 'referrer':
        return 'Referer';
      case 'origin':
        return 'Origin';
      case 'accept':
        return 'Accept';
      default:
        return name;
    }
  }

  Source? _candidateFromMaps(List<Map> maps, {required String name, bool worker = false}) {
    if (maps.isEmpty) return null;
    if (worker) {
      final status = (_stringAcross(maps, ['status']) ?? '').toLowerCase();
      if (status == 'error' || status == 'failed') return null;
    }

    final readyLink = _stringAcross(maps, ['ready_to_use_link']);
    var rawUrl = readyLink ?? _stringAcross(maps, [
      'channel_url', 'stream_url', 'streamUrl', 'play_url',
      'mpd_url', 'm3u8_url', 'hls_url',
    ]);
    if (rawUrl == null && maps.length > 1) {
      rawUrl = _stringAcross(maps.skip(1).toList(), ['url', 'link']);
    }
    if (rawUrl == null) {
      final generic = _stringAcross([maps.first], ['url', 'link']);
      final hasPlaybackContext = _stringAcross(maps, [
        'status', 'cookie', 'drmScheme', 'drm_scheme', 'mimeTypeHint',
        'playbackInfo', 'playback_info',
      ]) != null;
      if (generic != null && (_looksLikeVideoUrl(generic) || hasPlaybackContext)) {
        rawUrl = generic;
      }
    }
    if (rawUrl == null) return null;

    var cleanUrl = rawUrl;
    final pipe = <String, String>{};
    final pipeIndex = rawUrl.indexOf('|');
    if (pipeIndex >= 0) {
      cleanUrl = rawUrl.substring(0, pipeIndex).trim();
      pipe.addAll(_pipeParameters(rawUrl.substring(pipeIndex + 1)));
    }
    if (!isHttp(cleanUrl)) return null;

    final headers = <String, String>{
      'User-Agent': _workerUserAgent,
      'Accept': '*/*',
    };
    for (final map in maps) {
      for (final key in ['headers', 'httpHeaders', 'streamHeaders']) {
        final supplied = map[key];
        if (supplied is Map) {
          for (final entry in supplied.entries) {
            if (entry.value != null) {
              headers[_canonicalHeaderName(entry.key.toString())] =
                  entry.value.toString();
            }
          }
        }
      }
    }
    final userAgent = _stringAcross(maps, ['userAgent', 'user_agent']);
    final cookie = pipe['cookie'] ?? _stringAcross(maps, ['cookie']);
    final referer = _stringAcross(maps, ['referer', 'referrer']);
    final origin = _stringAcross(maps, ['origin']);
    if (userAgent != null) headers['User-Agent'] = userAgent;
    if (cookie != null) headers['Cookie'] = cookie;
    if (referer != null) headers['Referer'] = referer;
    if (origin != null) headers['Origin'] = origin;

    final keyValues = <dynamic>[];
    for (final map in maps) {
      for (final key in ['all_keys', 'allKeys', 'drmLicense', 'clearkey', 'clearKey']) {
        if (map.containsKey(key)) keyValues.add(map[key]);
      }
    }
    if (pipe['drmlicense'] != null &&
        !pipe['drmlicense']!.startsWith('http')) {
      keyValues.add(pipe['drmlicense']);
    }
    final keyId = pipe['keyid'] ?? _stringAcross(maps, ['keyId', 'key_id', 'kid']);
    final singleKey = _stringAcross(maps, ['key']);
    final keyPairs = _parseClearKeyPairs(keyValues);
    if (keyPairs.isEmpty && keyId != null && singleKey != null) {
      keyPairs[keyId] = singleKey;
    }

    var licenseUrl = pipe['drmlicense'];
    if (licenseUrl == null || !licenseUrl.startsWith('http')) {
      final mappedLicense = _stringAcross(maps, [
        'license_url', 'licenseUrl', 'drmLicense',
      ]);
      licenseUrl = mappedLicense != null && mappedLicense.startsWith('http')
          ? mappedLicense
          : null;
    }
    final rawScheme = (pipe['drmscheme'] ??
        _stringAcross(maps, ['drm_scheme', 'drmScheme']) ?? '').toLowerCase();
    final drmScheme = keyPairs.isNotEmpty
        ? 'clearkey'
        : (licenseUrl != null && licenseUrl.startsWith('http')
            ? 'widevine'
            : rawScheme.isEmpty ? null : rawScheme);

    String? clearKeyJson;
    if (keyPairs.isNotEmpty) {
      clearKeyJson = jsonEncode({
        'keys': [
          for (final entry in keyPairs.entries)
            {
              'kty': 'oct',
              'kid': _hexToBase64Url(entry.key),
              'k': _hexToBase64Url(entry.value),
            },
        ],
        'type': 'temporary',
      });
    }

    var mimeTypeHint = pipe['mimetypehint'] ??
        _stringAcross(maps, ['mimeTypeHint', 'mime_type', 'format']);
    final lowerUrl = cleanUrl.toLowerCase();
    mimeTypeHint ??= lowerUrl.contains('.mpd') ? 'mpd' :
        (lowerUrl.contains('.m3u8') ? 'm3u8' : null);

    return Source.clean(
      name: name,
      url: cleanUrl,
      headers: headers,
      mimeTypeHint: mimeTypeHint,
      drmScheme: drmScheme,
      drmLicenseUrl: licenseUrl,
      drmClearKey: clearKeyJson,
    );
  }

  Source? _candidateFromDynamic(dynamic value, {required String name, bool worker = false}) =>
      _candidateFromMaps(_flattenPlaybackMaps(value), name: name, worker: worker);

  Future<Source?> _fetchWorkerCandidate(String channelId) async {
    try {
      final uri = Uri.parse(_workerEndpoint).replace(queryParameters: {'id': channelId});
      final response = await _client.get(uri, headers: _workerHeaders)
          .timeout(const Duration(seconds: 18));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      return _candidateFromDynamic(json, name: 'Worker API', worker: true);
    } catch (_) {
      return null;
    }
  }

  Future<int?> _probeManifest(Source source) async {
    try {
      final request = http.Request('GET', Uri.parse(source.url!));
      request.headers.addAll(source.headers);
      final response = await _client.send(request)
          .timeout(const Duration(seconds: 12));
      final subscription = response.stream.listen((_) {});
      await subscription.cancel();
      return response.statusCode;
    } catch (_) {
      // A probe timeout or network interruption should not prevent ExoPlayer
      // from trying the candidate with the same headers.
      return null;
    }
  }

  Future<List<Source>> resolvePlayback(
    Item item, {
    bool forceRefresh = false,
  }) async {
    // Worker responses are deliberately never cached: every retry obtains a fresh token.
    Map<String, dynamic>? raw = _rawChannelCache[item.id];
    if (raw == null) {
      try {
        await _loadChannels();
        raw = _rawChannelCache[item.id];
      } catch (_) {}
    }

    final candidates = <Source>[];
    final numericId = int.tryParse(item.id);
    if (numericId != null && numericId > 0 && numericId < 1000000) {
      final worker = await _fetchWorkerCandidate(item.id);
      if (worker != null) candidates.add(worker);
    }

    final fallback = raw == null
        ? null
        : _candidateFromDynamic(raw, name: 'npoint fallback');
    if (fallback != null &&
        !candidates.any((source) => source.url == fallback.url)) {
      candidates.add(fallback);
    }
    if (item.sources.isNotEmpty &&
        !candidates.any((source) => source.url == item.sources.first.url)) {
      candidates.add(item.sources.first);
    }

    final valid = <Source>[];
    int? lastFailureStatus;
    for (final candidate in candidates) {
      final status = await _probeManifest(candidate);
      if (status == null || status == 200 || status == 206 ||
          (status >= 300 && status < 400)) {
        valid.add(candidate);
      } else if (status >= 400) {
        if (status == 451 || lastFailureStatus == null) {
          lastFailureStatus = status;
        }
      }
      // 403 / 410 / 451 and other HTTP errors are rejected so the next
      // candidate (npoint) is tried before handing anything to ExoPlayer.
    }
    if (valid.isEmpty) {
      final message = lastFailureStatus == 451
          ? 'HTTP 451: JioTV CDN blocked this stream. An Indian IP/network may be required.'
          : (lastFailureStatus == 403 || lastFailureStatus == 410
              ? 'HTTP $lastFailureStatus: JioTV stream token expired or was rejected. Retry to fetch a fresh Worker token.'
              : (lastFailureStatus == 404
                  ? 'HTTP 404: this JioTV channel manifest is currently unavailable.'
                  : 'JioTV stream is unavailable. Check the Indian network and retry for a fresh stream token.'));
      throw ProviderError(message);
    }
    return valid;
  }

  @override
  Future<Item> detail(ProviderDef p, Item item) async => item;

  @override
  Future<List<Source>> sources(ProviderDef p, Item item, Episode? ep) async =>
      resolvePlayback(item);
}


class JioTvProgram {
  const JioTvProgram({
    required this.id,
    required this.channelId,
    required this.title,
    required this.description,
    required this.startEpochMs,
    required this.endEpochMs,
    required this.posterUrl,
    required this.thumbnailUrl,
    required this.category,
    required this.genre,
    required this.starCast,
    required this.director,
  });

  final String id;
  final String channelId;
  final String title;
  final String description;
  final int startEpochMs;
  final int endEpochMs;
  final String? posterUrl;
  final String? thumbnailUrl;
  final String category;
  final String genre;
  final String starCast;
  final String director;

  bool isLiveAt([DateTime? at]) {
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    return now >= startEpochMs && now < endEpochMs;
  }

  bool isPastAt([DateTime? at]) {
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    return endEpochMs <= now;
  }

  String statusAt([DateTime? at]) =>
      isLiveAt(at) ? 'LIVE' : (isPastAt(at) ? 'CATCH-UP' : 'UPCOMING');

  double progressAt([DateTime? at]) {
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final span = endEpochMs - startEpochMs;
    if (span <= 0) return 0;
    return ((now - startEpochMs) / span).clamp(0.0, 1.0).toDouble();
  }

  int get durationMinutes =>
      ((endEpochMs - startEpochMs) / 60000).round();

  String get timeLabel =>
      _formatTime(startEpochMs) + ' - ' + _formatTime(endEpochMs);

  static String _formatTime(int epochMs) {
    final time = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute ' + (time.hour >= 12 ? 'PM' : 'AM');
  }
}

/// EPG cache is scoped to channel + day offset. Selected day is loaded first;
/// the remaining 14 days are warmed in nearest-first order with max 10 requests.
class JioTvEpgService {
  static const _endpoint =
      'https://jiotv.data.cdn.jio.com/apis/v1.3/getepg/get';
  static const _cacheTtl = Duration(minutes: 10);
  static const _headers = <String, String>{
    'User-Agent': 'JioTV',
    'x-api-key': 'l7xx75e822925f184370b2e25170c5d5820a',
    'Origin': 'https://www.jiotv.com',
    'Referer': 'https://www.jiotv.com/tv-guide',
    'Accept': 'application/json',
    'appkey': 'NzNiMDhlYzQyNjJm',
    'os': 'android',
    'devicetype': 'phone',
  };

  static final http.Client _client = http.Client();
  static final Map<String, List<JioTvProgram>> _cache = {};
  static final Map<String, DateTime> _cacheTimes = {};
  static final Map<String, Future<List<JioTvProgram>>> _inFlight = {};

  static String _key(String channelId, int offset) => '$channelId|$offset';

  static String _text(dynamic value) {
    if (value == null) return '';
    if (value is List) {
      return value.map(_text).where((x) => x.isNotEmpty).join(', ').trim();
    }
    return value.toString().trim();
  }

  static int? _epoch(dynamic value) {
    if (value == null) return null;
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value.toString().trim());
    if (parsed == null || parsed <= 0) return null;
    final integer = parsed.round();
    return integer < 10000000000 ? integer * 1000 : integer;
  }

  static DateTime? _timeForOffset(dynamic value, int offset) {
    final raw = _text(value);
    if (raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    final second = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;
    if (hour == null || minute == null || hour < 0 || hour > 23 ||
        minute < 0 || minute > 59 || second < 0 || second > 59) {
      return null;
    }
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day).add(Duration(days: offset));
    return DateTime(day.year, day.month, day.day, hour, minute, second);
  }

  static String? _imageUrl(dynamic value) {
    final raw = _text(value);
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final path = raw.replaceFirst(RegExp(r'^/+'), '');
    if (path.startsWith('dare_images/')) {
      return 'https://jiotv.catchup.cdn.jio.com/' + path;
    }
    return 'https://jiotv.catchup.cdn.jio.com/dare_images/shows/' + path;
  }

  static JioTvProgram? _parse(Map raw, String channelId, int offset) {
    final start = _epoch(raw['startEpoch']) ??
        _timeForOffset(raw['showtime'], offset)?.millisecondsSinceEpoch;
    if (start == null) return null;

    var end = _epoch(raw['endEpoch']) ??
        _timeForOffset(raw['endtime'], offset)?.millisecondsSinceEpoch;
    if (end == null) {
      end = start + 3600000;
    } else if (end <= start && raw['endEpoch'] == null) {
      end += 86400000;
    }
    if (end <= start) end = start + 3600000;

    final showName = _text(raw['showname']);
    final showTitle = _text(raw['showtitle']);
    final title = showName.isNotEmpty
        ? showName
        : (showTitle.isNotEmpty ? showTitle : 'Program');
    final genre = _text(raw['showGenre']);
    final showCategory = _text(raw['showCategory']);
    final category = showCategory.isNotEmpty
        ? showCategory
        : (genre.isNotEmpty ? genre : 'TV Show');
    final srno = _text(raw['srno']);
    final poster = _imageUrl(raw['episodePoster']);
    final thumbnail = _imageUrl(raw['episodeThumbnail']) ?? poster;

    return JioTvProgram(
      id: srno.isNotEmpty ? srno : channelId + '_' + start.toString(),
      channelId: channelId,
      title: title,
      description: _text(raw['description']).isNotEmpty
          ? _text(raw['description'])
          : 'No episode synopsis available.',
      startEpochMs: start,
      endEpochMs: end,
      posterUrl: poster,
      thumbnailUrl: thumbnail,
      category: category,
      genre: genre,
      starCast: _text(raw['starCast']),
      director: _text(raw['director']),
    );
  }

  static Future<List<JioTvProgram>> loadDay(
    String channelId,
    int offset, {
    bool forceRefresh = false,
  }) async {
    if (offset < -7 || offset > 7) {
      throw ArgumentError.value(offset, 'offset', 'EPG offset must be -7..7');
    }
    final key = _key(channelId, offset);
    final cached = _cache[key];
    final cachedAt = _cacheTimes[key];
    if (!forceRefresh && cached != null && cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return cached;
    }
    if (_inFlight.containsKey(key)) return _inFlight[key]!;

    final future = () async {
      final uri = Uri.parse(_endpoint).replace(queryParameters: {
        'offset': offset.toString(),
        'channel_id': channelId,
        'langId': '6',
      });
      final response = await _client.get(uri, headers: _headers)
          .timeout(const Duration(seconds: 22));
      if (response.statusCode != 200) {
        throw ProviderError('JioTV EPG HTTP ' + response.statusCode.toString());
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['epg'] is! List) {
        throw ProviderError('JioTV EPG response is missing epg[].');
      }
      final programs = (decoded['epg'] as List)
          .whereType<Map>()
          .map((entry) => _parse(entry, channelId, offset))
          .whereType<JioTvProgram>()
          .toList()
        ..sort((a, b) => a.startEpochMs.compareTo(b.startEpochMs));
      _cache[key] = programs;
      _cacheTimes[key] = DateTime.now();
      return programs;
    }();

    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  static Future<void> prefetch(
    String channelId, {
    int selectedOffset = 0,
  }) async {
    await loadDay(channelId, selectedOffset);
    final offsets = <int>[];
    for (var distance = 1; distance <= 7; distance++) {
      for (final offset in [-distance, distance]) {
        if (offset != selectedOffset) offsets.add(offset);
      }
    }
    var next = 0;
    final workers = offsets.length < 10 ? offsets.length : 10;
    await Future.wait(List.generate(workers, (_) async {
      while (next < offsets.length) {
        final offset = offsets[next++];
        try {
          await loadDay(channelId, offset);
        } catch (_) {
          // A failed day remains retryable when the user opens that date.
        }
      }
    }));
  }
}
