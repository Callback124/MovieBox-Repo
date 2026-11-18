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
  });

  final String title;
  final String description;
  final DateTime start;
  final DateTime end;
  final String? poster;

  double get progress {
    final total = end.difference(start).inMilliseconds;
    if (total <= 0) return 0;
    final elapsed = DateTime.now().difference(start).inMilliseconds;
    return (elapsed / total).clamp(0.0, 1.0);
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


  static final Map<String, ({DateTime savedAt, JioTvProgram? program})> _epgCache = {};

  /// Fetch today's EPG and return the programme that is on air right now.
  static Future<JioTvProgram?> currentProgram(String channelId) async {
    final cached = _epgCache[channelId];
    if (cached != null &&
        DateTime.now().difference(cached.savedAt) < const Duration(minutes: 5)) {
      return cached.program;
    }

    final uri = Uri.https(
      'jiotv.data.cdn.jio.com',
      '/apis/v1.3/getepg/get',
      {'offset': '0', 'channel_id': channelId},
    );
    final response = await _client.get(uri, headers: _apiHeaders)
        .timeout(const Duration(seconds: 18));
    if (response.statusCode != 200) {
      throw ProviderError('JioTV programme guide HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final rows = decoded is Map && decoded['epg'] is List
        ? decoded['epg'] as List
        : const <dynamic>[];
    final now = DateTime.now();
    JioTvProgram? current;
    for (final row in rows.whereType<Map>()) {
      final startRaw = num.tryParse(row['startEpoch']?.toString() ?? '');
      final endRaw = num.tryParse(row['endEpoch']?.toString() ?? '');
      if (startRaw == null || endRaw == null) continue;
      final startMs = startRaw < 1000000000000 ? startRaw * 1000 : startRaw;
      final endMs = endRaw < 1000000000000 ? endRaw * 1000 : endRaw;
      final start = DateTime.fromMillisecondsSinceEpoch(startMs.toInt());
      final end = DateTime.fromMillisecondsSinceEpoch(endMs.toInt());
      if (now.isBefore(start) || !now.isBefore(end)) continue;

      String? image = row['episodePoster']?.toString().trim();
      if (image == null || image.isEmpty || image.toLowerCase() == 'null') {
        image = row['episodeThumbnail']?.toString().trim();
      }
      if (image != null && image.isNotEmpty && !isHttp(image)) {
        image = 'https://jiotv.catchup.cdn.jio.com/dare_images/shows/${image.replaceFirst(RegExp(r'^/+'), '')}';
      }
      current = JioTvProgram(
        title: (row['showname'] ?? '').toString().trim(),
        description: (row['description'] ?? '').toString().trim(),
        start: start,
        end: end,
        poster: image,
      );
      break;
    }
    _epgCache[channelId] = (savedAt: DateTime.now(), program: current);
    return current;
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
