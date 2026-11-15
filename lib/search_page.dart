import 'dart:async';

import 'package:flutter/material.dart';

import 'models.dart';
import 'providers.dart';
import 'store.dart';
import 'widgets.dart';
import 'jiosaavn_service.dart';
import 'music_page.dart';

class _Group {
  _Group(this.provider, this.items, this.error);
  final ProviderDef provider;
  final List<Item> items;
  final Object? error;
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => SearchPageState();
}

class SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  late final ScrollController _scroll;
  Timer? _debounce;
  int _token = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _searchCursor;
  String _query = '';
  List<_Group> _groups = const [];
  List<String> _suggestions = const [];

  bool _saavnMode = false;
  int _saavnTab = 0;
  List<SaavnSong> _saavnSongs = [];
  List<Map<String, dynamic>> _saavnMedia = [];

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
  }

  void setSaavnMode(bool value) {
    _saavnMode = value;
    _saavnTab = 0;
    resetSearch();
  }

  void resetSearch() {
    ++_token;
    _debounce?.cancel();
    _ctrl.clear();
    _query = '';
    _groups = const [];
    _suggestions = const [];
    _saavnSongs = [];
    _saavnMedia = [];
    _loading = false;
    _loadingMore = false;
    _hasMore = false;
    _page = 1;
    _searchCursor = null;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    setState(() {
      _query = '';
      _groups = const [];
      _saavnSongs = [];
      _saavnMedia = [];
      _loading = false;
      _loadingMore = false;
      _hasMore = false;
      _suggestions = const [];
    });
    _loadSuggestions(v);
  }

  Future<void> _loadSuggestions(String raw) async {
    final q = raw.trim();
    if (q.length < 2) {
      if (mounted) setState(() => _suggestions = const []);
      return;
    }
    final providers = app.scope();
    if (providers.isEmpty) return;
    try {
      final active = providers.first;
      final values = active.kind == 'storytv'
          ? await StoryTvAdapter().suggestions(q)
          : active.kind == 'freereels'
              ? await FreeReelsAdapter().suggestions(q)
              : active.kind == 'moviebox'
                  ? await MovieBoxAdapter().suggestions(q) : const <String>[];
      if (!mounted || _ctrl.text.trim() != q) return;
      setState(() => _suggestions = values.take(8).toList());
    } catch (_) {
      if (mounted) setState(() => _suggestions = const []);
    }
  }

  void _useSuggestion(String value) {
    _ctrl.text = value;
    _ctrl.selection = TextSelection.collapsed(offset: value.length);
    setState(() => _suggestions = const []);
    _search(value);
  }

  Future<void> _search(String raw) async {
    final q = raw.trim();
    if (_saavnMode) {
      final my = ++_token;
      if (q.isEmpty) { setState(() { _query = ''; _saavnSongs = []; _saavnMedia = []; _loading = false; }); return; }
      if (_scroll.hasClients) _scroll.jumpTo(0);
      setState(() { _query = q; _loading = true; _saavnSongs = []; _saavnMedia = []; });
      try {
        if (_saavnTab == 0) {
          final result = await JioSaavnPlayer.instance.api.searchSongs(q);
          if (!mounted || my != _token) return;
          setState(() { _saavnSongs = result; _loading = false; });
        } else {
          final kind = ['songs', 'albums', 'playlists', 'artists'][_saavnTab];
          final result = await JioSaavnPlayer.instance.api.searchMedia(kind, q);
          if (!mounted || my != _token) return;
          setState(() { _saavnMedia = result; _loading = false; });
        }
      } catch (e) {
        if (mounted && my == _token) { setState(() => _loading = false); toast(context, 'JioSaavn search failed: $e'); }
      }
      return;
    }
    final my = ++_token;
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _groups = const [];
        _suggestions = const [];
        _loading = false;
      });
      return;
    }
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      _query = q;
      _loading = true;
      _loadingMore = false;
      _page = 1;
      _hasMore = false;
      _searchCursor = null;
    });
    final ps = app.scope();
    final groups = await Future.wait(ps.map((p) async {
      try {
        if (p.kind == 'moviebox') {
          final page = await MovieBoxAdapter().searchPage(p, q);
          if (mounted && my == _token) {
            _page = 1;
            _hasMore = page.hasMore;
          }
          return _Group(p, page.items, null);
        }
        if (p.kind == 'storytv') {
          final page = await StoryTvAdapter().searchPage(p, q, page: 0);
          if (mounted && my == _token) {
            _page = 0;
            _hasMore = page.hasMore;
          }
          return _Group(p, page.items, null);
        }
        if (p.kind == 'freereels') {
          final page = await FreeReelsAdapter().searchPage(p, q);
          if (mounted && my == _token) {
            _searchCursor = page.nextCursor;
            _hasMore = page.hasMore;
          }
          return _Group(p, page.items, null);
        }
        return _Group(p, await adapterFor(p).search(p, q), null);
      } catch (e) {
        return _Group(p, const [], e);
      }
    }));
    if (!mounted || my != _token) return;
    setState(() {
      _groups = groups;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loading || _loadingMore || !_hasMore || _query.isEmpty) return;
    if (_scroll.position.extentAfter < 500) _loadMore();
  }

  Future<void> _loadMore() async {
    final matches = app.scope().where((x) => x.kind == 'moviebox' || x.kind == 'storytv' || x.kind == 'freereels').toList();
    if (matches.isEmpty) return;
    final p = matches.first;
    setState(() => _loadingMore = true);
    try {
      late final List<Item> nextItems;
      late final bool moreAvailable;
      if (p.kind == 'storytv') {
        final page = await StoryTvAdapter().searchPage(p, _query, page: _page + 1);
        nextItems = page.items;
        moreAvailable = page.hasMore;
      } else if (p.kind == 'freereels') {
        final page = await FreeReelsAdapter().searchPage(p, _query, cursor: _searchCursor);
        nextItems = page.items;
        _searchCursor = page.nextCursor;
        moreAvailable = page.hasMore;
      } else {
        final page = await MovieBoxAdapter().searchPage(p, _query, page: _page + 1);
        nextItems = page.items;
        moreAvailable = page.hasMore;
      }
      if (!mounted) return;
      final idx = _groups.indexWhere((g) => g.provider.id == p.id);
      if (idx >= 0) {
        final updated = [..._groups];
        final old = updated[idx];
        final seen = old.items.map((x) => x.id).toSet();
        final fresh = nextItems.where((x) => seen.add(x.id)).toList();
        updated[idx] = _Group(p, [...old.items, ...fresh], null);
        setState(() {
          _groups = updated;
          _page++;
          _hasMore = moreAvailable && fresh.isNotEmpty;
          _loadingMore = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
      } else {
        setState(() => _loadingMore = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loadingMore = false);
      if (mounted) toast(context, 'Could not load more results: $e');
    }
  }

  Widget _saavnSongGrid(List<SaavnSong> songs) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    sliver: SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 190, childAspectRatio: .82, crossAxisSpacing: 12, mainAxisSpacing: 14),
      itemCount: songs.length,
      itemBuilder: (context, i) {
        final song = songs[i];
        return InkWell(borderRadius: BorderRadius.circular(12), onTap: () async {
          try { await JioSaavnPlayer.instance.playList(songs, start: i); if (context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const SaavnFullPlayer())); }
          catch (e) { if (context.mounted) toast(context, 'Playback failed: $e'); }
        }, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox.expand(child: song.image.isEmpty ? const ColoredBox(color: Color(0xFFF1F2F4), child: Icon(Icons.music_note, size: 42)) : Image.network(song.image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFF1F2F4), child: Icon(Icons.music_note, size: 42)))))),
          const SizedBox(height: 7), Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]));
      },
    ),
  );

  Widget _saavnMediaGrid(List<Map<String, dynamic>> items) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    sliver: SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 190, childAspectRatio: .82, crossAxisSpacing: 12, mainAxisSpacing: 14),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        final image = (item['image'] ?? item['album_image'] ?? '').toString().replaceAll('150x150', '500x500').replaceAll('50x50', '500x500').replaceAll('http://', 'https://');
        final title = saavnClean(item['title'] ?? item['name'] ?? 'Music');
        final subtitle = saavnClean(item['subtitle'] ?? item['type'] ?? item['artist'] ?? '');
        return InkWell(borderRadius: BorderRadius.circular(12), onTap: () {
          if (_saavnTab == 3) Navigator.push(context, MaterialPageRoute(builder: (_) => SaavnArtistPage(item: item)));
          else if (_saavnTab == 1 || _saavnTab == 2) showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => SaavnTracklistSheet(item: item, playlist: _saavnTab == 2));
          else { final song = SaavnSong.fromJson(item); JioSaavnPlayer.instance.playList([song]).then((_) { if (context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const SaavnFullPlayer())); }).catchError((e) { if (context.mounted) toast(context, 'Playback failed: $e'); }); }
        }, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox.expand(child: image.isEmpty ? const ColoredBox(color: Color(0xFFF1F2F4), child: Icon(Icons.music_note, size: 42)) : Image.network(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFF1F2F4), child: Icon(Icons.music_note, size: 42)))))),
          const SizedBox(height: 7), Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (subtitle.isNotEmpty) Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]));
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final multi = _groups.length > 1;
    final nothing = !_loading && _query.isNotEmpty &&
        (_saavnMode ? (_saavnTab == 0 ? _saavnSongs.isEmpty : _saavnMedia.isEmpty)
          : _groups.every((g) => g.error == null && g.items.isEmpty));
    return NotificationListener<ScrollNotification>(
      onNotification: (n) { if (n is ScrollUpdateNotification || n is ScrollMetricsNotification) _onScroll(); return false; },
      child: CustomScrollView(
      key: const PageStorageKey<String>('movie-search-results'),
      controller: _scroll,
      slivers: [
        SliverAppBar(
          floating: true,
          titleSpacing: 16,
          title: TextField(
            controller: _ctrl,
            onChanged: _onChanged,
            onSubmitted: _search,
            textInputAction: TextInputAction.search,
            textAlign: TextAlign.center,
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              hintText: _saavnMode ? 'Search songs, albums, artists' : 'Search movies and shows',
              filled: true,
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        if (_saavnMode)
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            for (var i = 0; i < 4; i++) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(['Songs', 'Albums', 'Playlists', 'Artists'][i]), selected: _saavnTab == i, showCheckmark: false, onSelected: (_) { setState(() { _saavnTab = i; _saavnSongs = []; _saavnMedia = []; }); if (_query.isNotEmpty) _search(_query); }))
          ])))),
        if (_suggestions.isNotEmpty && _query.isEmpty && !_saavnMode)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final suggestion in _suggestions)
                    ActionChip(
                      label: Text(suggestion),
                      onPressed: () => _useSuggestion(suggestion),
                    ),
                ],
              ),
            ),
          ),
        if (_loading)
          const SliverToBoxAdapter(child: Padding(
              padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()))
        else if (_query.isEmpty)
          const SliverToBoxAdapter(child: SizedBox.shrink())
        else if (_saavnMode && _saavnTab == 0)
          _saavnSongGrid(_saavnSongs)
        else if (_saavnMode)
          _saavnMediaGrid(_saavnMedia)
        else if (nothing)
          SliverToBoxAdapter(
              child: EmptyState(
                  title: 'No results for "$_query"',
                  text: 'Try a different spelling or another provider.'))
        else
          for (final g in _groups) ...[
            if (multi) SliverToBoxAdapter(child: ProviderHeader(g.provider.name)),
            if (g.error != null)
              SliverToBoxAdapter(child: ErrorNote(name: g.provider.name, error: g.error!))
            else if (g.items.isEmpty && multi)
              const SliverToBoxAdapter(
                  child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 12), child: Text('No matches.')))
            else
              PosterGrid(items: g.items),
          ],
        if (_loadingMore)
          const SliverToBoxAdapter(child: Padding(
            padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))),
      ],
    ),
    );
  }
}
