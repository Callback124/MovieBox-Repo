import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'downloads_page.dart';
import 'downloads_service.dart';
import 'home_page.dart';
import 'history_page.dart';
import 'music_page.dart';
import 'jiosaavn_service.dart';
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
  final _searchKey = GlobalKey<SearchPageState>();
  late final List<Widget> _pages = [
    const HomePage(), SearchPage(key: _searchKey), const DownloadsPage(),
    const HistoryPage(), const SettingsPage(), const MusicPage(),
  ];

  @override
  void initState() {
    super.initState();
    DownloadService.instance.onOpenDownloads = () => _goToPage(2);
  }

  void _goToPage(int next) {
    if (_page == next) return;
    if (next == 1) { _searchKey.currentState?.setSaavnMode(_page == 5); _searchKey.currentState?.resetSearch(); }
    setState(() {
      _pageHistory.add(_page);
      _page = next;
    });
  }

  Future<bool> _handleBack() async {
    if (_page == 5) return true;
    if (_page == 0 && JioSaavnPlayer.instance.miniPlayerVisible.value) {
      try {
        await const MethodChannel('app.moviefox/task').invokeMethod<bool>('moveToBackground');
        return false;
      } catch (_) {}
    }
    if (_page == 1) _searchKey.currentState?.resetSearch();
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

  Widget _providerIcon(String kind) {
    const movieBox = 'https://h5-static.aoneroom.com/ssrStatic/mbOfficial/public/_nuxt/image-1.apJjVir2.svg';
    const storyTv = 'https://play-lh.googleusercontent.com/A5ISR8CT9j9gTFpqTSJBXwvxWKk1WmJlJ8-WRl7dYUzI0U3srRPCF0t6_sX6Jvfl1Su1_-p0R5k9wd4fur79VQ';
    const freeReels = 'https://cdn.aptoide.com/imgs/f/1/c/f1c5e0e44aeeb449090037d9088cb0d2_icon.png';
    const jioSaavn = 'https://play-lh.googleusercontent.com/tJwz_QkxqQN1yFfb8ItXc2hpfzzSfxA-sdqaPGv51ldOFDXCMSmG0coD0uCzKo5y28rJLzyiIY7tmCHiuOOtdKM';
    if (kind == 'moviebox') return SvgPicture.network(movieBox, width: 27, height: 27, fit: BoxFit.contain, placeholderBuilder: (_) => const Icon(Icons.movie_creation_outlined, size: 24));
    final url = kind == 'storytv' ? storyTv : kind == 'freereels' ? freeReels : jioSaavn;
    return Image.network(url, width: 27, height: 27, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(kind == 'storytv' ? Icons.smart_display_outlined : kind == 'freereels' ? Icons.video_library_outlined : Icons.music_note_rounded, size: 24));
  }

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
                      selected: _page != 5 && app.active == provider.id,
                      onTap: () {
                        app.setActive(provider.id);
                        Navigator.pop(sheetContext);
                        if (_page != 0) setState(() { _pageHistory.add(_page); _page = 0; });
                      },
                    ),
                  _ProviderChoice(
                    name: 'JioSaavn',
                    icon: _providerIcon('jiosaavn'),
                    selected: _page == 5,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _goToPage(5);
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
        appBar: (_page == 0 || _page == 5) ? AppBar(
          titleSpacing: 16,
          title: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _chooseProvider(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              child: Text(_page == 5 ? 'JioSaavn' : app.scopeName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.4)),
            ),
          ),
          actions: [
            IconButton(tooltip: 'Search', onPressed: () => _goToPage(1), icon: const Icon(Icons.search)),
            IconButton(tooltip: 'Downloads', onPressed: () => _goToPage(2), icon: const Icon(Icons.download_outlined)),
            IconButton(tooltip: 'Watch history', onPressed: () => _goToPage(3), icon: const Icon(Icons.history_rounded)),
            IconButton(tooltip: 'Settings', onPressed: () => _goToPage(4), icon: const Icon(Icons.settings_outlined)),
            const SizedBox(width: 4),
          ],
        ) : null,
        body: IndexedStack(index: _page, children: _pages),
        bottomNavigationBar: ValueListenableBuilder<bool>(
          valueListenable: JioSaavnPlayer.instance.miniPlayerVisible,
          builder: (context, visible, _) => visible && _page != 5
              ? const MusicMiniPlayer()
              : (_page == 5 && visible ? const MusicMiniPlayer() : null),
        ),
      ),
    ),
  );
}

class _ProviderChoice extends StatelessWidget {
  const _ProviderChoice({required this.name, required this.icon, required this.selected, required this.onTap});
  final String name;
  final Widget icon;
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
          SizedBox(width: 27, height: 27, child: Center(child: icon)),
          const SizedBox(width: 9),
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w600, color: selected ? const Color(0xFF3157C8) : Colors.black87))),
        ]),
      ),
    ),
  );
}
