import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MovieFoxApp());
}

class MovieFoxApp extends StatelessWidget {
  const MovieFoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MovieFox',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101114),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE50914),
          brightness: Brightness.dark,
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
  int _selectedIndex = 0;

  static const _tabs = ['Home', 'Search', 'Downloads', 'Settings'];
  static const _icons = [
    Icons.home_rounded,
    Icons.search_rounded,
    Icons.download_rounded,
    Icons.settings_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text(
          'MOVIEFOX',
          style: TextStyle(
            color: Color(0xFFE50914),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            onPressed: () => setState(() => _selectedIndex = 1),
            icon: const Icon(Icons.search_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.movie_creation_outlined,
                  size: 68, color: Color(0xFFE50914)),
              const SizedBox(height: 18),
              Text(
                _tabs[_selectedIndex],
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'MovieFox base app is ready.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white60,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: List.generate(
          _tabs.length,
          (index) => NavigationDestination(
            icon: Icon(_icons[index]),
            label: _tabs[index],
          ),
        ),
      ),
    );
  }
}
