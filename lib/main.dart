import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MovieFoxApp());
}

class MovieFoxApp extends StatelessWidget {
  const MovieFoxApp({super.key});

  static const Color _accent = Color(0xFFE50914);
  static const Color _background = Color(0xFFFFFFFF);
  static const Color _surface = Color(0xFFF5F5F5);
  static const Color _text = Color(0xFF171717);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MovieFox',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: _background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.light,
          surface: _background,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: _background,
          foregroundColor: _text,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: _text,
            backgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: _surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        useMaterial3: true,
      ),
      home: const MovieFoxHomePage(),
    );
  }
}

class MovieFoxHomePage extends StatefulWidget {
  const MovieFoxHomePage({super.key});

  @override
  State<MovieFoxHomePage> createState() => _MovieFoxHomePageState();
}

class _MovieFoxHomePageState extends State<MovieFoxHomePage> {
  String _currentPage = 'Home';

  void _openPage(String page) {
    setState(() => _currentPage = page);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: const Text(
          'MOVIEFOX',
          style: TextStyle(
            color: MovieFoxApp._accent,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            onPressed: () => _openPage('Search'),
            icon: const Icon(Icons.search, size: 25),
          ),
          IconButton(
            tooltip: 'Downloads',
            onPressed: () => _openPage('Downloads'),
            icon: const Icon(Icons.download_outlined, size: 24),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => _openPage('Settings'),
            icon: const Icon(Icons.settings_outlined, size: 24),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    if (_currentPage == 'Home') {
      return const Center(
        child: Text(
          'Welcome to MovieFox',
          style: TextStyle(
            color: MovieFoxApp._text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _currentPage == 'Search'
                ? Icons.search
                : _currentPage == 'Downloads'
                    ? Icons.download_outlined
                    : Icons.settings_outlined,
            size: 48,
            color: MovieFoxApp._accent,
          ),
          const SizedBox(height: 12),
          Text(
            _currentPage,
            style: const TextStyle(
              color: MovieFoxApp._text,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _openPage('Home'),
            style: TextButton.styleFrom(
              foregroundColor: MovieFoxApp._accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: const Text('Back to Home'),
          ),
        ],
      ),
    );
  }
}
