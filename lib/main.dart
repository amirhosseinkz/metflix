// lib/main.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/services.dart';

/// ───────────────────────  ENTRY  ───────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();
  runApp(const MetflixApp());
}

/// ───────────────────────  ROOT  ───────────────────────
class MetflixApp extends StatelessWidget {
  const MetflixApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Metflix',
    theme: ThemeData.dark(useMaterial3: true),
    debugShowCheckedModeBanner: false,
    home: const ProfileGate(),
  );
}

/// ───────────────────  MODELS  ──────────────────────────
class Profile {
  final String name;
  final bool kidMode;
  final String? pin;
  const Profile(this.name, {this.kidMode = false, this.pin});
}

class VideoModel {
  final String id, title, url, thumbnail, genre;
  final String? subtitleUrl;
  final bool isDrm;
  const VideoModel({
    required this.id,
    required this.title,
    required this.url,
    required this.thumbnail,
    required this.genre,
    this.subtitleUrl,
    this.isDrm = false,
  });
}

/// ───────────────  PROFILE SELECTION  ───────────────────
class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key});
  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  final profiles = [
    const Profile('Kid', kidMode: true),
    const Profile('Alice', pin: '1234'),
    const Profile('Bob'),
  ];
  Profile? active;

  @override
  void initState() {
    super.initState();

    _loadActive();






  }

  Future<void> _loadActive() async {
    final p = await SharedPreferences.getInstance();
    final name = p.getString('active_profile');
    setState(() => active = profiles.firstWhere(
          (e) => e.name == name,
      orElse: () => profiles[0],
    ));
  }

  void _select(Profile p) async {
    if (p.pin != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => _PinDialog(correct: p.pin!),
      ) ??
          false;
      if (!ok) return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_profile', p.name);
    setState(() => active = p);
  }

  @override
  Widget build(BuildContext context) {
    if (active == null) {
      return Scaffold(body: _grid(profiles));
    }
    return HomeScreen(profile: active!, onChangeProfile: () {
      setState(() => active = null);
    });
  }

  Widget _grid(List<Profile> list) => Scaffold(
    appBar: AppBar(title: const Text('Who’s watching?')),
    body: GridView.count(
      crossAxisCount: 3,
      children: list
          .map((p) => GestureDetector(
        onTap: () => _select(p),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(radius: 36, child: Text(p.name[0])),
            const SizedBox(height: 8),
            Text(p.name),
          ],
        ),
      ))
          .toList(),
    ),
  );
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.correct});
  final String correct;
  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final ctrl = TextEditingController();
  String? error;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Enter PIN'),
    content: TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      obscureText: true,
      maxLength: 4,
      decoration: InputDecoration(errorText: error),
    ),
    actions: [
      TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel')),
      TextButton(
          onPressed: () {
            if (ctrl.text == widget.correct) {
              Navigator.pop(context, true);
            } else {
              setState(() => error = 'Incorrect PIN');
            }
          },
          child: const Text('OK')),
    ],
  );
}

/// ───────────────────  HOME SCREEN  ─────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.profile, required this.onChangeProfile});
  final Profile profile;
  final VoidCallback onChangeProfile;



  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MethodChannel platform = const MethodChannel('com.metflix.player/drm');
  final prefsFuture = SharedPreferences.getInstance();

  // Hard-coded catalog
  late final List<VideoModel> all = [
    const VideoModel(
      id: 'bunny',
      title: 'Big Buck Bunny',
      thumbnail:
      'https://peach.blender.org/wp-content/uploads/title_anouncement.jpg?x11217',
      url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      genre: 'Kids',
    ),
    const VideoModel(
      id: 'sintel',
      title: 'Sintel',
      thumbnail:
      'https://upload.wikimedia.org/wikipedia/commons/8/8f/Sintel_poster.jpg',
      url: 'https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8',
      genre: 'Fantasy',
    ),
    const VideoModel(
      id: 'tears',
      title: 'Tears of Steel',
      thumbnail:
      'https://upload.wikimedia.org/wikipedia/commons/thumb/7/70/Tos-poster.png/500px-Tos-poster.png',
      url: 'https://test-streams.mux.dev/pts_shift/master.m3u8',
      genre: 'Sci-Fi',
    ),
    const VideoModel(
      id: "drm_test",
      title: "DRM Test (Widevine)",
      thumbnail: "https://media.istockphoto.com/id/1319587368/vector/drm-digital-rights-management-acronym.jpg?s=612x612&w=0&k=20&c=XczX1COvFbztSHP1rGho4zsB8QeKXWPWgbx27sgNm2A=",
      url: "https://storage.googleapis.com/shaka-demo-assets/angel-one-widevine/dash.mpd",
      genre: 'Documentary',
      isDrm: true,
    ),
  ];

  late List<VideoModel> visible;        // filtered by kid-mode
  List<VideoModel> continueList = [];
  late final AdService ads;
  @override
  void initState() {
    super.initState();
    ads = AdService()..load();
    visible = widget.profile.kidMode
        ? all.where((e) => e.genre == 'Kids').toList()
        : all;
    _loadContinue();
  }

  Future<void> _loadContinue() async {
    final p = await prefsFuture;
    final items = <VideoModel>[];
    for (final v in all) {
      if (p.containsKey('${v.id}_ts')) items.add(v);
    }
    items.sort((a, b) =>
        p.getInt('${b.id}_ts')!.compareTo(p.getInt('${a.id}_ts')!));
    setState(() => continueList = items);
  }

  // ───────────────── UI ─────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Metflix – ${widget.profile.name}'),
        leading: IconButton(
          icon: const Icon(Icons.account_circle),
          onPressed: widget.onChangeProfile,
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => showSearch(
                context: context,
                delegate: MetflixSearchDelegate(visible),
              )),
        ],
      ),
      body: ListView(
        children: [
          if (continueList.isNotEmpty)
            _GenreRow(title: 'Continue Watching', items: continueList, prefsFuture: prefsFuture, onTap: _play),
          ..._groupByGenre(visible).entries.map(
                (e) =>
                _GenreRow(title: e.key, items: e.value, prefsFuture: prefsFuture, onTap: _play),
          ),
          const SizedBox(height: 8),
          const Center(child: _BannerAdWidget()),
        ],
      ),
    );
  }

  // group list by genre
  Map<String, List<VideoModel>> _groupByGenre(List<VideoModel> list) {
    final map = <String, List<VideoModel>>{};
    for (final v in list) (map[v.genre] ??= []).add(v);
    return map;
  }

  // unified play handler
  void _play(VideoModel v) async {
    if (v.isDrm) {
      try {
        await platform.invokeMethod('playDRMVideo', {
          'id': v.id,
          'url': v.url,
          'licenseUrl': 'https://cwip-shaka-proxy.appspot.com/no_auth',
        });
      } on PlatformException catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('DRM error: ${e.message}')));
      }
    } else {
      // 1️⃣ Show ad first (await).
      await ads.showIfReady();

      // 2️⃣ Then start video.
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PlayerScreen(video: v)),
      ).then((_) => _loadContinue());
    }
  }
}

/// ──────────────  ROW WIDGET  ───────────────────────────
class _GenreRow extends StatelessWidget {
  const _GenreRow(
      {required this.title,
        required this.items,
        required this.prefsFuture,
        required this.onTap});
  final String title;
  final List<VideoModel> items;
  final Future<SharedPreferences> prefsFuture;
  final void Function(VideoModel) onTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 0, 8),
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      SizedBox(
        height: 160,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          itemBuilder: (_, i) => FutureBuilder<SharedPreferences>(
            future: prefsFuture,
            builder: (_, snap) {
              final prefs = snap.data;
              final v = items[i];
              final pos = prefs?.getInt('${v.id}_pos') ?? 0;
              return GestureDetector(
                onTap: () => onTap(v),
                child: Container(
                  width: 140,
                  margin: const EdgeInsets.only(left: 8),
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      Image.network(v.thumbnail,
                          width: 140, height: 160, fit: BoxFit.cover),
                      if (pos > 0)
                        LinearProgressIndicator(
                          value: pos / 600,
                          minHeight: 4,
                          backgroundColor: Colors.black54,
                          color: Colors.red,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ],
  );
}

/// ──────────────  SEARCH  ───────────────────────────────
class MetflixSearchDelegate extends SearchDelegate<VideoModel?> {
  MetflixSearchDelegate(this.videos);
  final List<VideoModel> videos;
  @override
  Widget buildSuggestions(BuildContext ctx) => _results(ctx);
  @override
  Widget buildResults(BuildContext ctx) => _results(ctx);
  Widget _results(ctx) {
    final q = query.toLowerCase();
    final hits = videos
        .where((v) =>
    v.title.toLowerCase().contains(q) || v.genre.toLowerCase().contains(q))
        .toList();
    return ListView(
      children: hits
          .map((v) => ListTile(
        leading:
        Image.network(v.thumbnail, width: 60, fit: BoxFit.cover),
        title: Text(v.title),
        subtitle: Text(v.genre),
        onTap: () => close(ctx, v),
      ))
          .toList(),
    );
  }

  @override
  List<Widget> buildActions(ctx) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')
  ];
  @override
  Widget buildLeading(ctx) => BackButton(onPressed: () => close(ctx, null));
}

/// ──────────────  GOOGLE ADS BANNER  ────────────────────


class _BannerAdWidget extends StatefulWidget {
  const _BannerAdWidget();
  @override
  State<_BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<_BannerAdWidget> {
  late final BannerAd _ad;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final adUnit = Platform.isAndroid
        ? 'ca-app-pub-3940256099942544/6300978111'
        : 'ca-app-pub-3940256099942544/2934735716';

    _ad = BannerAd(
      adUnitId: adUnit,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _ready = true),
        onAdFailedToLoad: (_, __) => setState(() => _ready = false),
      ),
    )..load();
  }

  @override
  Widget build(BuildContext context) => _ready
      ? SizedBox(
    width: _ad.size.width.toDouble(),
    height: _ad.size.height.toDouble(),
    child: AdWidget(ad: _ad),
  )
      : const SizedBox.shrink();

  @override
  void dispose() {
    _ad.dispose();
    super.dispose();
  }
}

/// ──────────────  PLAYER SCREEN  ────────────────────────
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.video});
  final VideoModel video;
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  BetterPlayerController? controller;
  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final prefs = await SharedPreferences.getInstance();
    final startAt = prefs.getInt('${widget.video.id}_pos') ?? 0;
    final src = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      widget.video.url,
      subtitles: widget.video.subtitleUrl != null
          ? [
        BetterPlayerSubtitlesSource(
            type: BetterPlayerSubtitlesSourceType.network,
            urls: [widget.video.subtitleUrl!],
            name: 'English'),
      ]
          : [],
      videoFormat: BetterPlayerVideoFormat.hls,
    );
    final cfg = BetterPlayerConfiguration(
      autoPlay: true,
      aspectRatio: 16 / 9,
      controlsConfiguration: const BetterPlayerControlsConfiguration(
        enableSubtitles: true,
        enablePlaybackSpeed: true,
      ),
      eventListener: (evt) async {
        if (evt.betterPlayerEventType == BetterPlayerEventType.progress) {
          await prefs.setInt('${widget.video.id}_pos',
              evt.parameters?['progress']?.inSeconds ?? 0);
          await prefs.setInt(
              '${widget.video.id}_ts', DateTime.now().millisecondsSinceEpoch);
        }
      },
    );
    setState(() =>
    controller = BetterPlayerController(cfg, betterPlayerDataSource: src));
    controller!.addEventsListener((e) {
      if (e.betterPlayerEventType == BetterPlayerEventType.initialized) {
        controller!.seekTo(Duration(seconds: startAt));
      }
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.video.title)),
    body: AspectRatio(
      aspectRatio: 16 / 9,
      child: controller == null
          ? const Center(child: CircularProgressIndicator())
          : BetterPlayer(controller: controller!),
    ),
  );
}
class AdService {
  InterstitialAd? _interstitial;

  Future<void> load() async {
    await InterstitialAd.load(
      adUnitId: Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/1033173712' // Google test ID
          : 'ca-app-pub-3940256099942544/4411468910',
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (e) => _interstitial = null,
      ),
    );
  }

  Future<void> showIfReady() async {
    if (_interstitial == null) return;
    await _interstitial!.show();
    _interstitial = null;            // consume
    load();                          // pre-load next
  }
}