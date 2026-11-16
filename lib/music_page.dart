import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'downloads_service.dart';
import 'jiosaavn_service.dart';
import 'models.dart';
import 'widgets.dart';

const _musicAccent = Color(0xFF38DAD5);

Future<void> _downloadSaavn(BuildContext context, SaavnSong song) async {
  final quality = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.all(16), child: Text('Download quality', style: Theme.of(ctx).textTheme.titleLarge)),
      for (final q in ['320', '160', '96'])
        ListTile(leading: const Icon(Icons.audio_file), title: Text('$q kbps'), onTap: () => Navigator.pop(ctx, q)),
      const SizedBox(height: 8),
    ])),
  );
  if (quality == null) return;
  try {
    final url = await JioSaavnPlayer.instance.resolveAudioUrl(song, quality);
    final safe = song.title.replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '').trim();
    await DownloadService.instance.enqueue(
      url: url,
      title: song.title,
      fileName: '${safe.isEmpty ? 'JioSaavn Song' : safe}_${quality}kbps.mp4',
      headers: const {'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36', 'Accept': '*/*'},
      isMusic: true,
      artist: song.artist,
      image: song.image,
      duration: song.duration,
      songId: song.id,
    );
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloading ${song.title} · $quality kbps')));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
  }
}

Future<void> _playSaavnAndOpen(BuildContext context, List<SaavnSong> songs, {int start = 0}) async {
  if (songs.isEmpty) return;
  try {
    await JioSaavnPlayer.instance.playList(songs, start: start);
    if (context.mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => const SaavnFullPlayer()));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Playback failed: $e')));
  }
}

class MusicPage extends StatefulWidget {
  const MusicPage({super.key});
  @override
  State<MusicPage> createState() => _MusicPageState();
}
class _MusicPageState extends State<MusicPage> {
  final api = JioSaavnPlayer.instance.api;
  late Future<List<SaavnSection>> home;
  final query = TextEditingController();
  bool searching = false, loading = false;
  int tab = 0;
  List<SaavnSong> songs = [];
  List<Map<String,dynamic>> media = [];
  @override
  void initState(){super.initState();home=api.home();}
  @override
  void dispose(){query.dispose();super.dispose();}
  Future<void> search(String q) async {
    if(q.trim().isEmpty)return;
    setState(()=>loading=true);
    try {
      if(tab==0){songs=await api.searchSongs(q);media=[];}
      else {media=await api.searchMedia(['songs','albums','playlists','artists'][tab],q);songs=[];}
    } catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
    if(mounted)setState(()=>loading=false);
  }
  String img(Map m)=>(m['image']??m['album_image']??'').toString().replaceAll('150x150','500x500').replaceAll('50x50','500x500').replaceAll('http://','https://');
  String type(Map m){final t=(m['type']??m['media_type']??'').toString().toLowerCase();if(t.contains('artist')||m.containsKey('artistid'))return 'artist';if(t.contains('album')||m.containsKey('albumid'))return 'album';if(t.contains('song')||m.containsKey('encrypted_media_url'))return 'song';return 'playlist';}
  Future<void> _searchGenre(String genre) async { setState(() { searching = true; query.text = saavnClean(genre); tab = 0; songs = []; media = []; }); await search(query.text); }
  void open(Map<String,dynamic> m){final t=type(m);if(t=='artist'){Navigator.push(context,MaterialPageRoute(builder:(_)=>SaavnArtistPage(item:m)));}else if(t=='song'){final s=SaavnSong.fromJson(m);play([s],0);}else{Navigator.push(context,MaterialPageRoute(builder:(_)=>SaavnCollectionPage(item:m,playlist:t=='playlist')));}}
  Future<void> play(List<SaavnSong> list,int i)async{try{await JioSaavnPlayer.instance.playList(list,start:i);if(mounted)Navigator.push(context,MaterialPageRoute(builder:(_)=>const SaavnFullPlayer()));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Playback failed: '+e.toString())));}}
  @override
  Widget build(BuildContext context)=>PopScope(canPop: !searching,onPopInvokedWithResult: (didPop, result){if(!didPop && searching){setState(()=>searching=false);}},child:CustomScrollView(slivers:[
    if(searching)SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(16,0,16,12),child:Column(children:[
      TextField(controller:query,textInputAction:TextInputAction.search,onSubmitted:search,decoration:InputDecoration(hintText:'Songs, albums, artists, playlists',suffixIcon:IconButton(onPressed:()=>search(query.text),icon:const Icon(Icons.arrow_forward)),filled:true,border:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:BorderSide.none))),
      const SizedBox(height:8),SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:List.generate(4,(i)=>Padding(padding:const EdgeInsets.only(right:8),child:ChoiceChip(label:Text(['Songs','Albums','Playlists','Artists'][i]),selected:tab==i,showCheckmark:false,onSelected:(_){setState(()=>tab=i);if(query.text.isNotEmpty)search(query.text);}))))),
    ]))),
    if(loading)const SliverToBoxAdapter(child:LinearProgressIndicator()),
    if(searching && (songs.isNotEmpty || media.isNotEmpty)) _musicSearchGrid(),
    if(!searching)SliverToBoxAdapter(child:FutureBuilder<List<SaavnSection>>(future:home,builder:(context,snap){
      if(snap.connectionState==ConnectionState.waiting)return const Padding(padding:EdgeInsets.all(32),child:Center(child:CircularProgressIndicator()));
      if(snap.hasError)return Padding(padding:const EdgeInsets.all(20),child:Column(children:[Text('JioSaavn load failed: '+snap.error.toString()),TextButton(onPressed:()=>setState(()=>home=api.home()),child:const Text('Retry'))]));
      final sections = (snap.data??[]).where((s)=>!s.title.toLowerCase().contains('devotional') && !s.title.toLowerCase().contains('bhakti')).toList();
      return Column(children:[for(final sec in sections)_section(sec)]);
    })),
  ]));
  Widget _musicSearchGrid() => SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
    sliver: SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150, childAspectRatio: .48,
        crossAxisSpacing: 12, mainAxisSpacing: 14,
      ),
      itemCount: tab == 0 ? songs.length : media.length,
      itemBuilder: (context, i) {
        if (tab == 0) {
          final song = songs[i];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => play(songs, i),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox.expand(
                child: song.image.isEmpty ? const ColoredBox(color: Color(0xFFF1F2F4), child: Icon(Icons.music_note, size: 42))
                  : Image.network(song.image, fit: BoxFit.cover, loadingBuilder: (_, child, progress) => progress == null ? child : const ColoredBox(color: Color(0xFFF1F2F4), child: Center(child: Icon(Icons.music_note, size: 32))), errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFF1F2F4), child: Icon(Icons.music_note, size: 42))),
              ))),
              const SizedBox(height: 7),
              Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ]),
          );
        }
        final item = media[i];
        final image = img(item);
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => open(item),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox.expand(
              child: image.isEmpty ? const ColoredBox(color: Color(0xFFF1F2F4), child: Icon(Icons.music_note, size: 42))
                : Image.network(image, fit: BoxFit.cover, loadingBuilder: (_, child, progress) => progress == null ? child : const ColoredBox(color: Color(0xFFF1F2F4), child: Center(child: Icon(Icons.music_note, size: 32))), errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFF1F2F4), child: Icon(Icons.music_note, size: 42))),
            ))),
            const SizedBox(height: 7),
            Text(saavnClean(item['title'] ?? item['name'] ?? 'Music'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(saavnClean(item['subtitle'] ?? item['type'] ?? ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          ]),
        );
      },
    ),
  );

  Item _saavnCard(Map<String, dynamic> m) => Item(
    pid: 'jiosaavn',
    id: (m['id'] ?? m['albumid'] ?? m['listid'] ?? m['artistid'] ?? m['title'] ?? '').toString(),
    type: 'music',
    title: saavnClean(m['title'] ?? m['name'] ?? 'Music'),
    poster: img(m),
  );

  Widget _section(SaavnSection s) {
    final w = cardWidth(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(children: [
            Expanded(child: Text(s.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            if (s.items.isNotEmpty)
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => SaavnSectionGridPage(title: s.title, items: s.items, onOpen: open))),
                child: const Text('View all'),
              ),
          ]),
        ),
        SizedBox(
          height: w * 1.5 + 54,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: s.items.length,
            itemExtent: w + 12,
            cacheExtent: w * 7,
            itemBuilder: (context, i) {
              final m = s.items[i];
              final item = _saavnCard(m);
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: PosterCard(
                  item: item,
                  onTap: () => s.title.toLowerCase().contains('genres')
                      ? _searchGenre(item.title)
                      : open(m),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
  Widget _songTile(SaavnSong s,List<SaavnSong> list)=>ListTile(leading:ClipRRect(borderRadius:BorderRadius.circular(8),child:Image.network(s.image,width:50,height:50,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const Icon(Icons.music_note))),title:Text(s.title,maxLines:1),subtitle:Text(s.artist,maxLines:1),trailing:IconButton(icon:const Icon(Icons.more_vert),onPressed:()=>showModalBottomSheet<void>(context:context,builder:(ctx)=>SafeArea(child:Wrap(children:[
    ListTile(title:Text(s.title),subtitle:Text(s.artist)),
    ListTile(leading:const Icon(Icons.play_arrow),title:const Text('Play next'),onTap:(){final p=JioSaavnPlayer.instance;p.queue.insert((p.index+1).clamp(0,p.queue.length).toInt(),s);Navigator.pop(ctx);}),
    ListTile(leading:const Icon(Icons.queue_music),title:const Text('Add to queue'),onTap:(){JioSaavnPlayer.instance.queue.add(s);Navigator.pop(ctx);}),
    ListTile(leading:const Icon(Icons.download_outlined),title:const Text('Download'),onTap:(){Navigator.pop(ctx);_downloadSaavn(context,s);}),
    ListTile(leading:const Icon(Icons.album),title:const Text('View album'),onTap:(){Navigator.pop(ctx);Navigator.push(context,MaterialPageRoute(builder:(_)=>SaavnCollectionPage(item:{'albumid':s.albumId,'title':s.album,'image':s.image},playlist:false)));}),
  ])))),onTap:()=>play(list,list.indexOf(s)));
}

class SaavnSectionGridPage extends StatelessWidget {
  const SaavnSectionGridPage({super.key, required this.title, required this.items, required this.onOpen});
  final String title;
  final List<Map<String, dynamic>> items;
  final ValueChanged<Map<String, dynamic>> onOpen;

  String _image(Map<String, dynamic> m) => (m['image'] ?? m['album_image'] ?? '')
      .toString().replaceAll('150x150', '500x500')
      .replaceAll('50x50', '500x500').replaceAll('http://', 'https://');

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(saavnClean(title))),
    body: GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150, childAspectRatio: .48,
        crossAxisSpacing: 12, mainAxisSpacing: 14,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final m = items[i];
        final card = Item(
          pid: 'jiosaavn',
          id: (m['id'] ?? m['albumid'] ?? m['listid'] ?? m['artistid'] ?? m['title'] ?? '').toString(),
          type: 'music',
          title: saavnClean(m['title'] ?? m['name'] ?? 'Music'),
          poster: _image(m),
        );
        return PosterCard(item: card, onTap: () => onOpen(m));
      },
    ),
  );
}

class MusicMiniPlayer extends StatelessWidget {
  const MusicMiniPlayer({super.key});
  @override
  Widget build(BuildContext context){final p=JioSaavnPlayer.instance;return ValueListenableBuilder<int>(valueListenable:p.revision,builder:(context,_,__) {final s=p.current;if(s==null)return const SizedBox.shrink();return Material(color:Theme.of(context).colorScheme.surfaceContainer,child:InkWell(onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const SaavnFullPlayer())),child:SizedBox(height:64,child:Row(children:[
    const SizedBox(width:10),ClipRRect(borderRadius:BorderRadius.circular(7),child:Image.network(s.image,width:46,height:46,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const Icon(Icons.music_note))),
    const SizedBox(width:10),Expanded(child:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.start,children:[Text(s.title,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.bold)),Text(s.artist,maxLines:1,overflow:TextOverflow.ellipsis)])),
    StreamBuilder<PlayerState>(stream:p.audio.playerStateStream,builder:(context,snap)=>IconButton(onPressed:()=>snap.data?.playing==true?p.audio.pause():p.audio.play(),icon:Icon(snap.data?.playing==true?Icons.pause:Icons.play_arrow))),
    IconButton(onPressed:p.next,icon:const Icon(Icons.skip_next)),
    IconButton(tooltip:'Close mini player',onPressed:p.stopAndClear,icon:const Icon(Icons.close)),const SizedBox(width:4),
  ]))));});}
}

class SaavnFullPlayer extends StatefulWidget {
  const SaavnFullPlayer({super.key});
  @override
  State<SaavnFullPlayer> createState()=>_SaavnFullPlayerState();
}
class _SaavnFullPlayerState extends State<SaavnFullPlayer>{
  final p=JioSaavnPlayer.instance;
  bool shuffle=false, repeat=false;
  String time(Duration d)=>d.inMinutes.toString()+':'+(d.inSeconds%60).toString().padLeft(2,'0');
  @override
  Widget build(BuildContext context)=>ValueListenableBuilder<int>(valueListenable:p.revision,builder:(context,_,__){final s=p.current;if(s==null)return const Scaffold(body:Center(child:Text('Nothing playing')));return Scaffold(backgroundColor:const Color(0xFF15171E),appBar:AppBar(backgroundColor:const Color(0xFF15171E),foregroundColor:Colors.white,title:const Text('Playing now'),centerTitle:true,actions:[IconButton(tooltip:'Download',onPressed:()=>_downloadSaavn(context,s),icon:const Icon(Icons.download_outlined)),IconButton(onPressed:_queue,icon:const Icon(Icons.queue_music)),IconButton(onPressed:_lyrics,icon:const Icon(Icons.lyrics_outlined)),PopupMenuButton<String>(onSelected:(v){if(v=='quality')_quality();if(v=='lyrics')_lyrics();},itemBuilder:(_)=>const [PopupMenuItem(value:'quality',child:Text('Audio quality')),PopupMenuItem(value:'lyrics',child:Text('Lyrics'))])]),body:SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(24,12,24,18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Expanded(flex:6,child:Center(child:AspectRatio(aspectRatio:1,child:ClipRRect(borderRadius:BorderRadius.circular(22),child:Image.network(s.image,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const ColoredBox(color:Colors.black26,child:Icon(Icons.music_note,size:90,color:Colors.white))))))),
    const SizedBox(height:24),Row(children:[Expanded(child:Text(s.title,style:const TextStyle(color:Colors.white,fontSize:28,fontWeight:FontWeight.w700),maxLines:2,overflow:TextOverflow.ellipsis)),IconButton(onPressed:()=>ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Favorite saved in a later music update'))),icon:const Icon(Icons.favorite,color:Color(0xFF7CE8E7),size:30))]),
    Text(s.artist,style:const TextStyle(color:Colors.white60,fontSize:18)),const SizedBox(height:24),
    StreamBuilder<Duration>(stream:p.audio.positionStream,builder:(context,snap){final pos=snap.data??Duration.zero;final total=p.audio.duration??Duration(seconds:s.duration>0?s.duration:1);final max=total.inMilliseconds.toDouble().clamp(1,double.infinity);return Column(children:[
      SliderTheme(data:SliderTheme.of(context).copyWith(activeTrackColor:_musicAccent,inactiveTrackColor:Colors.white54,thumbColor:_musicAccent,trackHeight:2),child:Slider(value:(pos.inMilliseconds/max).clamp(0,1).toDouble(),onChanged:(v)=>p.audio.seek(Duration(milliseconds:(v*max).round())))),
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(time(pos),style:const TextStyle(color:Colors.white38,fontSize:11)),Text(time(total),style:const TextStyle(color:Colors.white38,fontSize:11))]),
    ]);}),
    const Spacer(),Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
      IconButton(color:shuffle?_musicAccent:Colors.white70,onPressed:()async{shuffle=!shuffle;await p.audio.setShuffleModeEnabled(shuffle);if(mounted)setState((){});},icon:const Icon(Icons.shuffle_rounded)),
      IconButton(color:Colors.white,onPressed:p.previous,icon:const Icon(Icons.skip_previous_rounded,size:36)),
      StreamBuilder<PlayerState>(stream:p.audio.playerStateStream,builder:(context,snap)=>Container(width:78,height:78,decoration:const BoxDecoration(color:_musicAccent,shape:BoxShape.circle),child:IconButton(color:const Color(0xFF10252A),iconSize:38,onPressed:()=>snap.data?.playing==true?p.audio.pause():p.audio.play(),icon:Icon(snap.data?.playing==true?Icons.pause_rounded:Icons.play_arrow_rounded)))),
      IconButton(color:Colors.white,onPressed:p.next,icon:const Icon(Icons.skip_next_rounded,size:36)),
      IconButton(color:repeat?_musicAccent:Colors.white70,onPressed:()async{repeat=!repeat;await p.audio.setLoopMode(repeat?LoopMode.one:LoopMode.off);if(mounted)setState((){});},icon:const Icon(Icons.repeat_rounded)),
    ]),const SizedBox(height:10),
  ]))));});
  Future<void> _quality()async{final q=await showDialog<String>(context:context,builder:(ctx)=>SimpleDialog(title:const Text('Audio quality'),children:[for(final v in ['320','160','96'])SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,v),child:Text(v+' kbps'+(p.bitrate==v?' ✓':'')))]));if(q!=null){try{await p.setQuality(q);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}}}
  Future<void> _lyrics()async{final s=p.current;if(s==null)return;showModalBottomSheet<void>(context:context,isScrollControlled:true,showDragHandle:true,builder:(_)=>FutureBuilder<String>(future:p.api.lyrics(s),builder:(ctx,snap)=>SizedBox(height:MediaQuery.sizeOf(ctx).height*.7,child:Padding(padding:const EdgeInsets.all(22),child:snap.connectionState==ConnectionState.waiting?const Center(child:CircularProgressIndicator()):SingleChildScrollView(child:Text(snap.data??'Lyrics unavailable',style:const TextStyle(height:1.7)))))));}
  void _queue(){showModalBottomSheet<void>(context:context,isScrollControlled:true,showDragHandle:true,builder:(ctx)=>SizedBox(height:MediaQuery.sizeOf(ctx).height*.7,child:ListView(children:[const ListTile(title:Text('Up next')),for(var i=0;i<p.queue.length;i++)ListTile(title:Text(p.queue[i].title),subtitle:Text(p.queue[i].artist),selected:i==p.index,onTap:()async{p.index=i;p.revision.value++;await p.playCurrent();if(ctx.mounted)Navigator.pop(ctx);})])));}
}

class SaavnCollectionPage extends StatefulWidget {
  const SaavnCollectionPage({super.key, required this.item, required this.playlist});
  final Map<String, dynamic> item; final bool playlist;
  @override State<SaavnCollectionPage> createState() => _SaavnCollectionPageState();
}
class _SaavnCollectionPageState extends State<SaavnCollectionPage> {
  late Future<List<SaavnSong>> future;
  String img(Map m) => (m['image'] ?? m['album_image'] ?? '').toString().replaceAll('150x150','500x500').replaceAll('50x50','500x500').replaceAll('http://','https://');
  @override void initState() { super.initState(); final id = (widget.item[widget.playlist ? 'listid' : 'albumid'] ?? widget.item['id'] ?? '').toString(); future = JioSaavnPlayer.instance.api.albumSongs(id, playlist: widget.playlist); }
  Widget _hero(String image, String title, String subtitle, VoidCallback? play) {
    final cs = Theme.of(context).colorScheme;
    Widget placeholder() => const ColoredBox(color: Color(0xFFF1F2F4), child: Center(child: Icon(Icons.music_note, size: 42)));
    Widget cover() => image.isEmpty ? placeholder() : Image.network(image, fit: BoxFit.cover, loadingBuilder: (_, child, progress) => progress == null ? child : placeholder(), errorBuilder: (_, __, ___) => placeholder());
    return SliverToBoxAdapter(child: Column(children: [
      SizedBox(height: 220, child: Stack(fit: StackFit.expand, children: [cover(), DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black38, cs.surface], stops: const [.25, 1])))])),
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 14), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        SizedBox(width: 110, child: ClipRRect(borderRadius: BorderRadius.circular(10), child: AspectRatio(aspectRatio: 2/3, child: cover()))), const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 6), Text(subtitle), const SizedBox(height: 12),
          FilledButton(onPressed: play, style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Text('Play all'))
        ]))
      ]))
    ]));
  }
  @override Widget build(BuildContext context) {
    final title = saavnClean(widget.item['title'] ?? widget.item['name'] ?? (widget.playlist ? 'Playlist' : 'Album'));
    final image = img(widget.item);
    return Scaffold(body: FutureBuilder<List<SaavnSong>>(future: future, builder: (context, snap) {
      final rows = snap.data ?? <SaavnSong>[];
      return CustomScrollView(slivers: [
        _hero(image, title, rows.length.toString() + ' songs', rows.isEmpty ? null : () => _playSaavnAndOpen(context, rows)),
        if (snap.connectionState == ConnectionState.waiting) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))),
        if (snap.hasError) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(24), child: Text('Tracklist failed: ' + snap.error.toString()))),
        if (snap.connectionState == ConnectionState.done && !snap.hasError) SliverPadding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 22), sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 150, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .48), itemCount: rows.length,
          itemBuilder: (context, i) { final song = rows[i]; return PosterCard(item: Item(pid: 'jiosaavn', id: song.id, type: 'music', title: song.title, poster: song.image), subtitle: song.artist, onTap: () => _playSaavnAndOpen(context, rows, start: i)); }
        ))
      ]);
    }));
  }
}

class SaavnArtistPage extends StatefulWidget {
  const SaavnArtistPage({super.key, required this.item}); final Map<String, dynamic> item;
  @override State<SaavnArtistPage> createState() => _SaavnArtistPageState();
}
class _SaavnArtistPageState extends State<SaavnArtistPage> {
  String img(Map m) => (m['image'] ?? m['album_image'] ?? '').toString().replaceAll('150x150','500x500').replaceAll('50x50','500x500').replaceAll('http://','https://');
  late Future<dynamic> future;
  @override void initState() { super.initState(); future = JioSaavnPlayer.instance.api.call('artist.getArtistPageDetails', {'artistId': (widget.item['artistid'] ?? widget.item['id'] ?? '').toString(), 'n_song': '50', 'n_album': '50'}); }
  @override Widget build(BuildContext context) => Scaffold(body: FutureBuilder<dynamic>(future: future, builder: (context, snap) {
    if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
    if (snap.hasError) return Center(child: Text(snap.error.toString()));
    final d = snap.data is Map ? snap.data as Map : <dynamic, dynamic>{};
    final rawSongs = d['topSongs'] is Map ? d['topSongs']['songs'] : d['topSongs'];
    final songs = rawSongs is List ? rawSongs.whereType<Map>().map((e) => SaavnSong.fromJson(e)).toList() : <SaavnSong>[];
    final rawAlbums = d['topAlbums'] is Map ? d['topAlbums']['albums'] : d['topAlbums'];
    final albums = rawAlbums is List ? rawAlbums.whereType<Map>().toList() : <Map>[];
    final name = saavnClean(widget.item['name'] ?? widget.item['title'] ?? 'Artist'); final image = img(widget.item);
    final cs = Theme.of(context).colorScheme;
    Widget placeholder() => const ColoredBox(color: Color(0xFFF1F2F4), child: Center(child: Icon(Icons.person, size: 42)));
    return CustomScrollView(slivers: [
      SliverAppBar(pinned: true, expandedHeight: 220, flexibleSpace: FlexibleSpaceBar(background: Stack(fit: StackFit.expand, children: [
        if (image.isNotEmpty) Image.network(image, fit: BoxFit.cover, loadingBuilder: (_, child, progress) => progress == null ? child : placeholder(), errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black38, cs.surface], stops: const [.25, 1])))
      ]))),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 14), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        SizedBox(width: 110, child: ClipRRect(borderRadius: BorderRadius.circular(10), child: AspectRatio(aspectRatio: 2/3, child: image.isEmpty ? placeholder() : Image.network(image, fit: BoxFit.cover, loadingBuilder: (_, child, progress) => progress == null ? child : placeholder(), errorBuilder: (_, __, ___) => placeholder())))), const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 6), Text((widget.item['follower_count'] ?? widget.item['fan_count'] ?? '').toString() + ' Fans'), const SizedBox(height: 12),
          FilledButton(onPressed: songs.isEmpty ? null : () => _playSaavnAndOpen(context, songs), style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Text('Play all'))
        ]))
      ]))),
      if (songs.isNotEmpty) ...[
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 10), child: Text('Top Songs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)))),
        SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 14), sliver: SliverGrid.builder(gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 150, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .48), itemCount: songs.length, itemBuilder: (context, i) { final song = songs[i]; return PosterCard(item: Item(pid: 'jiosaavn', id: song.id, type: 'music', title: song.title, poster: song.image), subtitle: song.artist, onTap: () => _playSaavnAndOpen(context, songs, start: i)); }))
      ],
      if (albums.isNotEmpty) ...[
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(16, 18, 16, 10), child: Text('Top Albums', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)))),
        SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 14), sliver: SliverGrid.builder(gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 150, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .48), itemCount: albums.length, itemBuilder: (context, i) { final item = Map<String, dynamic>.from(albums[i]); return PosterCard(item: Item(pid: 'jiosaavn', id: (item['id'] ?? item['albumid'] ?? '').toString(), type: 'music', title: saavnClean(item['title'] ?? item['name'] ?? 'Album'), poster: img(item)), subtitle: 'Album', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SaavnCollectionPage(item: item, playlist: false)))); }))
      ]
    ]);
  }));
}
