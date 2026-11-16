import 'package:flutter/material.dart';
import 'models.dart';
import 'player_page.dart';
import 'store.dart';
import 'widgets.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: app.progressRev,
      builder: (context, _, __) {
        final entries = app.progress.entries.toList()
          ..sort((a, b) => b.value.ts.compareTo(a.value.ts));
        return CustomScrollView(slivers: [
          SliverAppBar(
            floating: true,
            title: const Text('Watch history'),
            actions: [
              if (entries.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Clear all watch history?'),
                        content: const Text('This will remove all watched items and saved progress. This action cannot be undone.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear all')),
                        ],
                      ),
                    );
                    if (ok == true) app.clearProgress();
                  },
                  child: const Text('Clear all'),
                ),
              const SizedBox(width: 8),
            ],
          ),
          if (entries.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.history_rounded, size: 54, color: Colors.black38),
                SizedBox(height: 12),
                Text('No watch history yet', style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                Text('Movies and episodes you watch will appear here.'),
              ])),
            )
          else
            SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final p = entries[index].value;
                final ep = p.ep;
                final percent = p.d > 0 ? (p.t / p.d).clamp(0.0, 1.0) : 0.0;
                final date = DateTime.fromMillisecondsSinceEpoch(p.ts);
                final now = DateTime.now();
                final sameDay = date.year == now.year && date.month == now.month && date.day == now.day;
                final yesterday = DateTime(now.year, now.month, now.day).difference(DateTime(date.year, date.month, date.day)).inDays == 1;
                final time = TimeOfDay.fromDateTime(date).format(context);
                final stamp = sameDay ? 'Today · $time' : (yesterday ? 'Yesterday · $time' : '${date.day.toString().padLeft(2,'0')}/${date.month.toString().padLeft(2,'0')}/${date.year} · $time');
                return GestureDetector(
                  onLongPress: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete from watch history?'),
                        content: Text('Remove "${p.item.title}" from watch history?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok == true) app.removeProgress(p.item, ep);
                  },
                  child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: SizedBox(width: 58, height: 78,
                      child: p.item.poster != null && p.item.poster!.startsWith('http')
                        ? AppCachedImage(imageUrl: p.item.poster!, memCacheWidth: 180, errorWidget: const ColoredBox(color: Color(0xFFF0F1F4), child: Icon(Icons.movie_outlined)))
                        : const ColoredBox(color: Color(0xFFF0F1F4), child: Icon(Icons.movie_outlined)),
                    ),
                  ),
                  title: Text(p.item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (ep != null) Text('${ep.label} · ${ep.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(stamp, style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 5),
                    LinearProgressIndicator(value: percent, minHeight: 3),
                  ]),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PlayerPage(item: p.item, ep: ep, list: p.item.episodes),
                  )),
                  ),
                );
              },
            ),
        ]);
      },
    );
  }
}
