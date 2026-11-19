import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'download_page.dart';
import 'player_page.dart';
import 'providers.dart';
import 'store.dart';
import 'widgets.dart';
import 'jiotv_service.dart';
import 'jiotv_player_page.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.item});
  final Item item;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late Future<Item> _f = detailOf(_sourceItem);
  int? _season;
  int _rangeStart = 0;
  late Item _sourceItem = widget.item;
  late Future<JioTvProgram?> _jioProgram = widget.item.pid == 'jiotv'
      ? JioTvAdapter.currentProgram(widget.item.id)
      : Future.value(null);
  Timer? _programTicker;
  int _jioOffset = 0;
  late Future<List<JioTvProgram>> _jioSchedule = widget.item.pid == 'jiotv'
      ? JioTvAdapter.schedule(widget.item.id, 0)
      : Future.value(const <JioTvProgram>[]);

  @override
  void initState() {
    super.initState();
    if (widget.item.pid == 'jiotv') {
      JioTvAdapter.prefetchSchedule(widget.item.id, 0);
      _programTicker = Timer.periodic(const Duration(seconds: 60), (_) {
        if (mounted) {
          setState(() {
            _jioProgram = JioTvAdapter.currentProgram(widget.item.id);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _programTicker?.cancel();
    super.dispose();
  }

  void _selectDub(DubOption dub) {
    setState(() {
      _sourceItem = _sourceItem.copyWith(id: dub.subjectId, detailPath: dub.detailPath);
      _season = null;
      _rangeStart = 0;
      _f = detailOf(_sourceItem);
    });
  }

  /// The episode to continue from: the most recently watched one, or the next if it was finished.
  Episode? _lastEp(Item d) {
    if (d.episodes.isEmpty) return null;
    final pre = '${d.key}|';
    MapEntry<String, Progress>? best;
    for (final e in app.progress.entries) {
      if (e.key.startsWith(pre) && (best == null || e.value.ts > best.value.ts)) best = e;
    }
    if (best == null) return null;
    final id = best.key.substring(pre.length);
    final idx = d.episodes.indexWhere((x) => x.id == id);
    if (idx < 0) return null;
    if (best.value.frac > .95) {
      return idx + 1 < d.episodes.length ? d.episodes[idx + 1] : d.episodes[idx];
    }
    return d.episodes[idx];
  }

  String _playLabel(Item d) {
    final ep = d.episodes.isEmpty ? null : (_lastEp(d) ?? d.episodes.first);
    final pr = app.progress[progressKey(d, ep)];
    final resume = pr != null && pr.t > 5 && pr.frac < .95;
    return '${resume ? 'Resume' : 'Play'}${ep != null ? ' ${ep.label}' : ''}';
  }

  Future<void> _play(Item d, Episode? ep) async {
    if (d.pid == 'jiotv') {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => JioTvPlayerPage(item: d),
      ));
    } else {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerPage(item: d, ep: ep, list: d.episodes),
      ));
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: FutureBuilder<Item>(
        future: _f,
        builder: (context, snap) {
          final loading = snap.connectionState != ConnectionState.done;
          final d = snap.data ?? widget.item;
          final err = snap.error;
          final eps = d.episodes;
          final isStoryTv = d.pid == 'storytv' || d.pid == 'freereels';
          final isJioTv = d.pid == 'jiotv';
          final seasons = (eps.map((e) => e.season).toSet().toList()..sort());
          if (eps.isNotEmpty) _season ??= (_lastEp(d) ?? eps.first).season;
          final list = eps.where((e) => e.season == _season).toList();
          final rangeCount = (list.length + 99) ~/ 100;
          if (_rangeStart >= rangeCount * 100) _rangeStart = 0;
          final visibleEpisodes = list.skip(_rangeStart).take(100).toList();
          final tags = [
            d.type == 'movie' ? 'Movie' : (d.type == 'series' ? 'Series' : d.type),
            d.year,
            if (d.rating != null) '★ ${d.rating}',
            app.providerById(d.pid)?.name,
            ...d.genres,
          ].where((t) => t != null && t.isNotEmpty).cast<String>().toList();

          return ListenableBuilder(
            listenable: app,
            builder: (context, _) => CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 220,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (isJioTv)
                          FutureBuilder<JioTvProgram?>(
                            future: _jioProgram,
                            builder: (context, programSnap) {
                              final image = programSnap.data?.poster;
                              final fallback = d.bg ?? d.poster;
                              final url = isHttp(image) ? image : fallback;
                              if (!isHttp(url)) return const SizedBox.shrink();
                              return CachedNetworkImage(
                                cacheManager: AppImageCache.instance,
                                imageUrl: url!,
                                fit: BoxFit.cover,
                                memCacheWidth: 800,
                                errorWidget: (_, __, ___) => const SizedBox.shrink(),
                              );
                            },
                          )
                        else if (isHttp(d.bg ?? d.poster))
                          CachedNetworkImage(
                            cacheManager: AppImageCache.instance,
                            imageUrl: (d.bg ?? d.poster)!,
                            fit: BoxFit.cover,
                            memCacheWidth: 800,
                            errorWidget: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.black38, cs.surface],
                              stops: const [.3, 1],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        SizedBox(width: 110, child: Poster(url: d.poster, title: d.title)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.title,
                                  style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                              if (isJioTv)
                                FutureBuilder<JioTvProgram?>(
                                  future: _jioProgram,
                                  builder: (context, programSnap) {
                                    final program = programSnap.data;
                                    if (programSnap.connectionState == ConnectionState.waiting) {
                                      return const Padding(
                                        padding: EdgeInsets.only(top: 4),
                                        child: Text('Loading programme…', style: TextStyle(fontSize: 12)),
                                      );
                                    }
                                    if (program == null || program.title.isEmpty) {
                                      return const Padding(
                                        padding: EdgeInsets.only(top: 4),
                                        child: Text('Programme information unavailable', style: TextStyle(fontSize: 12)),
                                      );
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(program.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: tt.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: cs.primary,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              const SizedBox(height: 8),
                              Wrap(spacing: 6, runSpacing: 6, children: [
                                for (final t in tags)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: cs.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(999)),
                                    child: Text(t,
                                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                  ),
                              ]),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (d.dubs.length > 1)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: SizedBox(
                        height: 42,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final dub in d.dubs)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  showCheckmark: false,
                                  label: Text(dub.language + (dub.original ? ' · Original' : '')),
                                  selected: dub.subjectId == d.id && dub.detailPath == d.detailPath,
                                  onSelected: (_) => _selectDub(dub),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (loading) const SliverToBoxAdapter(child: LinearProgressIndicator()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Wrap(spacing: 10, runSpacing: 10, children: [
                      FilledButton(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: loading || err != null
                            ? null
                            : () => _play(
                                d, eps.isEmpty ? null : (_lastEp(d) ?? eps.first)),
                        child: Text(loading ? 'Loading…' : 'Watch'),
                      ),
                      if (!isJioTv)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: loading || err != null
                              ? null
                              : () => Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => DownloadPage(item: d),
                                  )),
                          icon: const Icon(Icons.download_outlined, size: 18),
                          label: const Text('Download'),
                        ),
                    ]),
                  ),
                ),
                if (err != null)
                  SliverToBoxAdapter(
                    child: EmptyState(
                      title: 'Could not load this title',
                      text: err.toString(),
                      action: OutlinedButton(
                        onPressed: () => setState(() => _f = detailOf(_sourceItem)),
                        child: const Text('Try again'),
                      ),
                    ),
                  ),
                if (isJioTv)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Programme Schedule', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 42,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                for (final offset in List<int>.generate(15, (i) => i - 7))
                                  Padding(
                                    padding: const EdgeInsets.only(right: 7),
                                    child: ChoiceChip(
                                      showCheckmark: false,
                                      label: Text(offset == 0 ? 'Today' : offset < 0 ? '${offset.abs()} days ago' : 'In $offset days'),
                                      selected: _jioOffset == offset,
                                      onSelected: (_) => setState(() {
                                        _jioOffset = offset;
                                        _jioSchedule = JioTvAdapter.schedule(widget.item.id, offset);
                                      }),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (isJioTv)
                  SliverToBoxAdapter(
                    child: FutureBuilder<List<JioTvProgram>>(
                      future: _jioSchedule,
                      builder: (context, scheduleSnap) {
                        if (scheduleSnap.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(18),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (scheduleSnap.hasError) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('EPG load failed: ${scheduleSnap.error}', style: TextStyle(color: cs.error)),
                          );
                        }
                        final programs = scheduleSnap.data ?? const <JioTvProgram>[];
                        if (programs.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Is date ke liye programme schedule available nahi hai.'),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            children: [
                              for (final program in programs)
                                Card(
                                  margin: const EdgeInsets.only(bottom: 9),
                                  clipBehavior: Clip.antiAlias,
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (isHttp(program.thumbnail))
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(7),
                                            child: CachedNetworkImage(
                                              cacheManager: AppImageCache.instance,
                                              imageUrl: program.thumbnail!,
                                              width: 88,
                                              height: 66,
                                              fit: BoxFit.cover,
                                              errorWidget: (_, __, ___) => Container(width: 88, height: 66, color: cs.surfaceContainerHighest),
                                            ),
                                          )
                                        else
                                          Container(width: 88, height: 66, decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(7)), child: const Icon(Icons.tv)),
                                        const SizedBox(width: 11),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(child: Text(program.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                                                  const SizedBox(width: 6),
                                                  InkWell(
                                                    onTap: program.status == 'LIVE' ? () => _play(d, null) : null,
                                                    borderRadius: BorderRadius.circular(20),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: program.status == 'LIVE' ? Colors.red.withOpacity(0.12) : cs.surfaceContainerHighest,
                                                        borderRadius: BorderRadius.circular(20),
                                                      ),
                                                      child: Text(program.status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: program.status == 'LIVE' ? Colors.red : cs.primary)),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 3),
                                              Text('${program.timeLabel}  ·  ${program.end.difference(program.start).inMinutes.round()} min  ·  ${program.category}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                                              const SizedBox(height: 5),
                                              Text(program.description, style: const TextStyle(fontSize: 12, height: 1.35)),
                                              if (program.genre.isNotEmpty || program.cast.isNotEmpty || program.director.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text([
                                                  if (program.genre.isNotEmpty) program.genre,
                                                  if (program.cast.isNotEmpty) 'Cast: ${program.cast}',
                                                  if (program.director.isNotEmpty) 'Director: ${program.director}',
                                                ].join(' · '), style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                                              ],
                                              if (program.status == 'LIVE') ...[
                                                const SizedBox(height: 6),
                                                ClipRRect(
                                                  borderRadius: BorderRadius.circular(99),
                                                  child: LinearProgressIndicator(value: program.progress, minHeight: 5, backgroundColor: cs.surfaceContainerHighest),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                if (!isJioTv && (d.plot ?? '').isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(d.plot!, style: const TextStyle(height: 1.5)),
                    ),
                  ),
                if (!isStoryTv && seasons.length > 1)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 52,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        children: [
                          for (final s in seasons)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                showCheckmark: false,
                                label: Text(s == 0 ? 'Specials' : 'Season $s'),
                                selected: s == _season,
                                onSelected: (_) => setState(() {
                                  _season = s;
                                  _rangeStart = 0;
                                }),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (rangeCount > 1)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 52,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        children: [
                          for (var r = 0; r < rangeCount; r++)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                showCheckmark: false,
                                label: Text(
                                  '${(r * 100 + 1).toString().padLeft(3, '0')}-${((r + 1) * 100 < list.length ? (r + 1) * 100 : list.length).toString().padLeft(3, '0')}',
                                ),
                                selected: _rangeStart == r * 100,
                                onSelected: (_) => setState(() => _rangeStart = r * 100),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  sliver: SliverGrid.builder(
                    itemCount: visibleEpisodes.length,
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 76,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1,
                    ),
                    itemBuilder: (context, i) {
                      final e = visibleEpisodes[i];
                      final episodeNumber = e.episode == 0 ? i + 1 : e.episode;
                      final episodeLabel = 'E${episodeNumber.toString().padLeft(2, '0')}';
                      return Card(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _play(d, e),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(episodeLabel,
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                )),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
          );
        },
      ),
    );
  }
}
