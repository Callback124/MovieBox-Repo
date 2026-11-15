import 'package:flutter/material.dart';
import 'downloads_page.dart';
import 'downloads_service.dart';
import 'home_page.dart';
import 'music_page.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await app.init().timeout(const Duration(seconds: 8)); } catch (_) {}
  try { await DownloadService.instance.loadSettings().timeout(const Duration(seconds: 5)); } catch (_) {}
  runApp(const MovieFoxApp());
}

ThemeData _lightTheme() {
  const bg = Colors.white;
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3157C8), brightness: Brightness.light).copyWith(surface: bg);
  return ThemeData(
    useMaterial3: true, brightness: Brightness.light, colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    appBarTheme: const AppBarTheme(backgroundColor: bg, foregroundColor: Colors.black, surfaceTintColor: Colors.transparent, scrolledUnderElevation: 0, elevation: 0),
    inputDecorationTheme: const InputDecorationTheme(filled: true, fillColor: Color(0xFFF3F4F6), border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(4)), borderSide: BorderSide.none)),
  );
}

class MovieFoxApp extends StatelessWidget {
  const MovieFoxApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(title: 'MovieFox', debugShowCheckedModeBanner: false, theme: _lightTheme(), home: const MovieFoxShell());
}

class MovieFoxShell extends StatefulWidget {
  const MovieFoxShell({super.key});
  @override
  State<MovieFoxShell> createState() => _MovieFoxShellState();
}

class _MovieFoxShellState extends State<MovieFoxShell> {
  int _page = 0;
  final List<int> _pageHistory = [];
  late final List<Widget> _pages = const [HomePage(), SearchPage(), DownloadsPage(), SettingsPage(), MusicPage()];

  @override
  void initState() {
    super.initState();
    DownloadService.instance.onOpenDownloads = () => _goToPage(2);
  }

  void _goToPage(int next) {
    if (_page == next) return;
    setState(() {
      _pageHistory.add(_page);
      _page = next;
    });
  }

  Future<bool> _handleBack() async {
    if (_pageHistory.isNotEmpty) {
      setState(() => _page = _pageHistory.removeLast());
      return false;
    }
    if (_page != 0) {
      setState(() => _page = 0);
      return false;
    }
    return true;
  }

  IconData _providerIcon(String kind) => switch (kind) {
    'moviebox' => Icons.movie_creation_outlined,
    'storytv' => Icons.smart_display_outlined,
    'freereels' => Icons.video_library_outlined,
    _ => Icons.extension_outlined,
  };

  void _chooseProvider(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: false,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Text('Choose provider', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.7,
                children: [
                  for (final provider in app.enabled)
                    _ProviderChoice(
                      name: provider.name,
                      icon: _providerIcon(provider.kind),
                      selected: _page != 4 && app.active == provider.id,
                      onTap: () {
                        app.setActive(provider.id);
                        Navigator.pop(sheetContext);
                        if (_page != 0) setState(() { _pageHistory.add(_page); _page = 0; });
                      },
                    ),
                  _ProviderChoice(
                    name: 'JioSaavn',
                    icon: Icons.music_note_rounded,
                    selected: _page == 4,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _goToPage(4);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) => WillPopScope(
      onWillPop: _handleBack,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _chooseProvider(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              child: Text(_page == 4 ? 'JioSaavn' : app.scopeName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.4)),
            ),
          ),
          actions: [
            IconButton(tooltip: 'Search', onPressed: () => _goToPage(1), icon: const Icon(Icons.search)),
            IconButton(tooltip: 'Downloads', onPressed: () => _goToPage(2), icon: const Icon(Icons.download_outlined)),
            IconButton(tooltip: 'Settings', onPressed: () => _goToPage(3), icon: const Icon(Icons.settings_outlined)),
            const SizedBox(width: 4),
          ],
        ),
        body: IndexedStack(index: _page, children: _pages),
      ),
    ),
  );
}

class _ProviderChoice extends StatelessWidget {
  const _ProviderChoice({required this.name, required this.icon, required this.selected, required this.onTap});
  final String name;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFFEAF0FF) : const Color(0xFFF5F6F8),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Icon(icon, size: 22, color: selected ? const Color(0xFF3157C8) : Colors.black87),
          const SizedBox(width: 9),
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w600, color: selected ? const Color(0xFF3157C8) : Colors.black87))),
          if (selected) const Icon(Icons.check_circle, size: 16, color: Color(0xFF3157C8)),
        ]),
      ),
    ),
  );
}
