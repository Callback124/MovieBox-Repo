import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'jiotv_service.dart';
import 'models.dart';

class JioTvPlayerPage extends StatefulWidget {
  const JioTvPlayerPage({super.key, required this.item});

  final Item item;

  @override
  State<JioTvPlayerPage> createState() => _JioTvPlayerPageState();
}

class _JioTvPlayerPageState extends State<JioTvPlayerPage> {
  late Future<Map<String, dynamic>> _playback;

  @override
  void initState() {
    super.initState();
    _playback = JioTvAdapter.resolvePlayback(widget.item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _playback,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white70, size: 42),
                    const SizedBox(height: 12),
                    Text(
                      snapshot.error?.toString() ?? 'Could not resolve this JioTV channel.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: () => setState(() {
                        _playback = JioTvAdapter.resolvePlayback(widget.item);
                      }),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!Platform.isAndroid) {
            return const Center(
              child: Text('JioTV ExoPlayer is available on Android.', style: TextStyle(color: Colors.white)),
            );
          }
          return Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: AndroidView(
                viewType: 'moviefox/jiotv_exoplayer',
                creationParams: <String, dynamic>{
                  ...snapshot.data!,
                  'title': widget.item.title,
                },
                creationParamsCodec: const StandardMessageCodec(),
              ),
            ),
          );
        },
      ),
    );
  }
}
