import 'package:flutter/material.dart';
import 'downloads_page.dart';
import 'downloads_service.dart';
import 'home_page.dart';
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
  late final List<Widget> _pages = const [HomePage(), SearchPage(), DownloadsPage(), SettingsPage()];
  @override
  void initState() {
    super.initState();
    DownloadService.instance.onOpenDownloads = () { if (mounted) setState(() => _page = 2); };
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      titleSpacing: 16,
      title: const Text('MovieFox', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.4)),
      actions: [
        IconButton(tooltip: 'Search', onPressed: () => setState(() => _page = 1), icon: const Icon(Icons.search)),
        IconButton(tooltip: 'Downloads', onPressed: () => setState(() => _page = 2), icon: const Icon(Icons.download_outlined)),
        IconButton(tooltip: 'Settings', onPressed: () => setState(() => _page = 3), icon: const Icon(Icons.settings_outlined)),
        const SizedBox(width: 4),
      ],
    ),
    body: IndexedStack(index: _page, children: _pages),
  );
}
