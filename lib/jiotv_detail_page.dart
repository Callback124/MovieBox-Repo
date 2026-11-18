import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'player_page.dart';
import 'jiotv_service.dart';
import 'widgets.dart';

class JioTvDetailPage extends StatefulWidget {
  const JioTvDetailPage({super.key, required this.item});
  final Item item;

  @override
  State<JioTvDetailPage> createState() => _JioTvDetailPageState();
}

class _JioTvDetailPageState extends State<JioTvDetailPage> {
  int _selectedOffset = 0;
  List<JioTvProgram> _selectedPrograms = const [];
  List<JioTvProgram> _todayPrograms = const [];
  List<JioTvProgram> _tomorrowPrograms = const [];
  bool _loadingSelected = true;
  bool _loadingTomorrow = true;
  String? _selectedError;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loadingSelected = true;
      _loadingTomorrow = true;
      _selectedError = null;
    });
    try {
      final today = await JioTvEpgService.loadDay(widget.item.id, 0);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _todayPrograms = today;
        _selectedPrograms = today;
        _loadingSelected = false;
      });
      unawaited(_loadTomorrow(generation));
      unawaited(JioTvEpgService.prefetch(widget.item.id, selectedOffset: 0));
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _selectedError = e.toString();
        _loadingSelected = false;
        _loadingTomorrow = false;
      });
    }
  }

  Future<void> _loadTomorrow(int generation) async {
    try {
      final tomorrow = await JioTvEpgService.loadDay(widget.item.id, 1);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _tomorrowPrograms = tomorrow;
        _loadingTomorrow = false;
      });
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadingTomorrow = false);
      }
    }
  }

  Future<void> _selectDay(int offset) async {
    if (offset == _selectedOffset && !_loadingSelected && _selectedError == null) return;
    final generation = ++_loadGeneration;
    setState(() {
      _selectedOffset = offset;
      _loadingSelected = true;
      _selectedError = null;
      _selectedPrograms = const [];
    });
    try {
      final programs = await JioTvEpgService.loadDay(widget.item.id, offset);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _selectedPrograms = programs;
        _loadingSelected = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _selectedError = e.toString();
        _loadingSelected = false;
      });
    }
  }

  Future<void> _playLive() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(item: widget.item),
    ));
  }

  DateTime _dayForOffset(int offset) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(Duration(days: offset));
  }

  String _dayLabel(int offset) {
    if (offset == 0) return 'Today';
    if (offset == -1) return 'Yesterday';
    if (offset == 1) return 'Tomorrow';
    final date = _dayForOffset(offset);
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[date.weekday - 1] + ' ' + date.day.toString() + '/' + date.month.toString();
  }

  JioTvProgram? _findLive(List<JioTvProgram> programs) {
    for (final program in programs) {
      if (program.isLiveAt()) return program;
    }
    return null;
  }

  List<JioTvProgram> _upNext() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final all = <JioTvProgram>[..._todayPrograms, ..._tomorrowPrograms]
      ..sort((a, b) => a.startEpochMs.compareTo(b.startEpochMs));
    final live = _findLive(all);
    final boundary = live?.endEpochMs ?? now;
    final horizon = boundary + const Duration(hours: 48).inMilliseconds;
    final seen = <String>{};
    return all.where((program) =>
      program.startEpochMs >= boundary &&
      program.startEpochMs < horizon &&
      seen.add(program.id)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final live = _findLive(_todayPrograms);
    final upcoming = _upNext();
    final bannerImage = live?.posterUrl ?? widget.item.poster;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 238,
            title: Text(widget.item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (isHttp(bannerImage))
                    CachedNetworkImage(
                      cacheManager: AppImageCache.instance,
                      imageUrl: bannerImage!,
                      fit: BoxFit.cover,
                      memCacheWidth: 900,
                      errorWidget: (_, __, ___) => _bannerFallback(),
                    )
                  else
                    _bannerFallback(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withValues(alpha: .12), Colors.black.withValues(alpha: .88)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: live == null ? Colors.black54 : Colors.red,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(live == null ? 'LIVE TV' : 'LIVE NOW',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(widget.item.corner ?? 'TV Channel',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 12))),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text(live?.title ?? 'Program guide',
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                        if (live != null) ...[
                          const SizedBox(height: 4),
                          Text(live.timeLabel,
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.item.title,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text((widget.item.corner ?? 'Live TV') +
                            (widget.item.genres.length > 1 ? ' · ' + widget.item.genres.last : ''),
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _playLive,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Watch Live'),
                    style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  ),
                ],
              ),
            ),
          ),
          if (live != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: _CurrentProgramDetails(program: live),
              ),
            )
          else if (!_loadingSelected && _selectedError == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text('No program is marked LIVE at this moment.',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                children: [
                  Expanded(child: Text('Up Next · 48 Hours',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                  if (_loadingTomorrow) const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ),
          ),
          if (upcoming.isEmpty && (_loadingSelected || _loadingTomorrow))
            const SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (upcoming.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                child: Text('No upcoming programs are available in the EPG right now.',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              sliver: SliverGrid.builder(
                itemCount: upcoming.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 390,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.15,
                ),
                itemBuilder: (context, index) => _ProgramCard(
                  program: upcoming[index],
                  onTap: () => _showProgramInfo(upcoming[index]),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Text('TV Guide · Past 7 Days / Next 7 Days',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (var offset = -7; offset <= 7; offset++)
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: ChoiceChip(
                        showCheckmark: false,
                        label: Text(_dayLabel(offset)),
                        selected: offset == _selectedOffset,
                        onSelected: (_) => _selectDay(offset),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_loadingSelected)
            const SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.all(22), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (_selectedError != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: EmptyState(
                  title: 'Could not load TV schedule',
                  text: _selectedError!,
                  action: OutlinedButton.icon(
                    onPressed: () => _selectDay(_selectedOffset),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ),
              ),
            )
          else if (_selectedPrograms.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('No programs found for ' + _dayLabel(_selectedOffset) + '.',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              sliver: SliverGrid.builder(
                itemCount: _selectedPrograms.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 390,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.15,
                ),
                itemBuilder: (context, index) => _ProgramCard(
                  program: _selectedPrograms[index],
                  onTap: () => _showProgramInfo(_selectedPrograms[index]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bannerFallback() => ColoredBox(
    color: const Color(0xFF20242B),
    child: Center(child: Icon(Icons.live_tv_rounded, size: 62, color: Colors.white.withValues(alpha: .45))),
  );

  void _showProgramInfo(JioTvProgram program) {
    final status = program.statusAt();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(program.title),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isHttp(program.posterUrl))
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: CachedNetworkImage(
                        cacheManager: AppImageCache.instance,
                        imageUrl: program.posterUrl!,
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) => const Icon(Icons.live_tv_outlined),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Text(status, style: TextStyle(
                  color: status == 'LIVE' ? Colors.red : Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(program.timeLabel),
                Text(program.durationMinutes.toString() + ' minutes'),
                const SizedBox(height: 10),
                Text(program.description),
                if (program.category.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Category: ' + program.category),
                ],
                if (program.genre.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text('Genre: ' + program.genre),
                ],
                if (program.starCast.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text('Cast: ' + program.starCast),
                ],
                if (program.director.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text('Director: ' + program.director),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
          if (program.isLiveAt())
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _playLive();
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Watch Live'),
            ),
        ],
      ),
    );
  }
}

class _CurrentProgramDetails extends StatelessWidget {
  const _CurrentProgramDetails({required this.program});
  final JioTvProgram program;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final progress = program.progressAt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.circle, color: Colors.red, size: 9),
            const SizedBox(width: 7),
            const Text('LIVE', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text(program.durationMinutes.toString() + ' min',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 7),
        Text(program.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(value: progress, minHeight: 5),
        ),
        const SizedBox(height: 7),
        Text(program.timeLabel, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 10),
        Text(program.description, style: const TextStyle(height: 1.45)),
        if (program.category.isNotEmpty || program.genre.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text([program.category, if (program.genre.isNotEmpty) program.genre].join(' · '),
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ],
        if (program.starCast.isNotEmpty) ...[
          const SizedBox(height: 7),
          Text('Cast: ' + program.starCast, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ],
        if (program.director.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text('Director: ' + program.director, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ],
      ],
    );
  }
}

class _ProgramCard extends StatelessWidget {
  const _ProgramCard({required this.program, required this.onTap});
  final JioTvProgram program;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = program.statusAt();
    final statusColor = status == 'LIVE'
        ? Colors.red
        : (status == 'CATCH-UP' ? Colors.blueGrey : Colors.green);
    final image = program.thumbnailUrl ?? program.posterUrl;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 112,
                  height: 76,
                  child: ColoredBox(
                    color: cs.surfaceContainerHighest,
                    child: isHttp(image)
                        ? CachedNetworkImage(
                            cacheManager: AppImageCache.instance,
                            imageUrl: image!,
                            fit: BoxFit.contain,
                            memCacheWidth: 260,
                            errorWidget: (_, __, ___) => const Icon(Icons.live_tv_outlined),
                          )
                        : const Icon(Icons.live_tv_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(program.title,
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(color: statusColor.withValues(alpha: .13), borderRadius: BorderRadius.circular(4)),
                          child: Text(status, style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(program.timeLabel, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10)),
                    const SizedBox(height: 4),
                    Text(program.category + ' · ' + program.durationMinutes.toString() + ' min',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10)),
                    if (status == 'LIVE') ...[
                      const SizedBox(height: 5),
                      ClipRRect(borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: program.progressAt(), minHeight: 3)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
