import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import '../theme/artic_theme.dart';
import '../utils/color_utils.dart';
import '../screens/full_player_page.dart';
import '../services/audio_handler.dart';
import '../services/yandex/yandex_audio_provider.dart';
import '../services/yandex/yandex_auth_service.dart';
import '../utils/matrix_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/theme_notifier.dart';

part 'main_screen_library.dart';
part 'main_screen_miniplayer.dart';
part 'main_screen_search.dart';
part 'main_screen_settings.dart';

const double kHorizontalPadding = 16.0;
const double kVerticalPadding = 16.0;

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  late AppAudioHandler audioHandler;
  late YandexAudioProvider yandexProvider;
  int _currentTab = 0;
  late PageController _pageController;
  int? _loadingTrackIndex;

  bool _showMiniPlayer = false;
  Color _dominantColor = ArticTheme.accent;
  CancelToken? _colorCancelToken;
  MediaItem? _currentMediaItem;
  DateTime _lastLibraryUpdate = DateTime.now().subtract(const Duration(minutes: 1));
  DateTime _lastCacheUpdate = DateTime.now().subtract(const Duration(minutes: 1));

  bool _isSwitchingTrack = false;

  final PageStorageKey _libraryScrollKey = const PageStorageKey('library_list');

  StreamSubscription<MediaItem?>? _mediaItemSubscription;
  StreamSubscription<PlaybackState>? _playbackStateSubscription;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentTab);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    audioHandler = Provider.of<AppAudioHandler>(context);
    yandexProvider = Provider.of<YandexAudioProvider>(context);

    // Инициализация провайдера УЖЕ выполнена в SplashScreen,
    // поэтому здесь не вызываем yandexProvider.init()

    _mediaItemSubscription = audioHandler.mediaItem.listen(_onMediaItemChanged);
    _playbackStateSubscription = audioHandler.playbackState.listen(_onPlaybackStateChanged);

    _refreshDominantColor();

    final mediaItem = audioHandler.mediaItem.value;
    if (audioHandler.playbackState.value.playing && mediaItem != null) {
      setState(() {
        _currentMediaItem = mediaItem;
        _showMiniPlayer = true;
      });
    }
  }

  void _onMediaItemChanged(MediaItem? mediaItem) {
    if (mediaItem == null) return;
    if (_isSwitchingTrack) return;
    setState(() {
      _currentMediaItem = mediaItem;
      _showMiniPlayer = true;
    });
    _refreshDominantColor();
  }

  void _onPlaybackStateChanged(PlaybackState state) {
    setState(() {});
    if (state.playing && _currentMediaItem != null && !_showMiniPlayer) {
      setState(() => _showMiniPlayer = true);
    }
  }

  Future<void> _refreshDominantColor() async {
    final currentTrack = audioHandler.mediaItem.value;
    if (currentTrack == null) return;
    final coverUrl = currentTrack.artUri?.toString();
    if (coverUrl == null || coverUrl.isEmpty) return;
    _colorCancelToken?.cancel();
    _colorCancelToken = CancelToken();
    final color = await ColorUtils.extractDominantColor(
      coverUrl,
      fallback: ArticTheme.accent,
      cancelToken: _colorCancelToken,
    );
    if (mounted && _colorCancelToken?.isCancelled == false) {
      setState(() => _dominantColor = color);
    }
  }

  void _playPause() => audioHandler.playOrPause();
  void _nextTrack() => audioHandler.skipToNext();
  void _previousTrack() => audioHandler.skipToPrevious();

  void _changeTab(int newTab) {
    if (_currentTab == newTab) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    setState(() => _currentTab = newTab);
    _pageController.animateToPage(newTab,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
    if (newTab == 0 && DateTime.now().difference(_lastLibraryUpdate).inSeconds > 30) {
      _refreshFavorites();
    }
  }

  Future<void> _refreshFavorites() async {
    await yandexProvider.loadFavorites();
    _lastLibraryUpdate = DateTime.now();
  }

  Future<void> _refreshCached() async {
    await yandexProvider.reloadCachedTracks();
    _lastCacheUpdate = DateTime.now();
  }

  // ========== ФОРМИРОВАНИЕ ОЧЕРЕДИ ИЗ ДИАЛОГА ==========
  Future<void> _playTracksFromDialog(List<Map<String, String>> tracks, int selectedIndex) async {
    if (!mounted) return;
    setState(() => _isSwitchingTrack = true);

    final futures = tracks.map((track) async {
      final trackId = track['trackId']!;
      final url = await yandexProvider.getDirectUrl(trackId);
      if (url == null) return null;
      return MediaItem(
        id: url,
        album: "",
        title: track['title']!,
        artist: track['artist']!,
        artUri: Uri.parse(track['cover']!),
        extras: {'trackId': trackId},
      );
    }).toList();

    final items = (await Future.wait(futures)).whereType<MediaItem>().toList();

    if (!mounted) return;
    setState(() => _isSwitchingTrack = false);

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Не удалось загрузить треки")),
      );
      return;
    }

    final selectedTrackId = tracks[selectedIndex]['trackId']!;
    final startIdx = items.indexWhere((item) => item.extras?['trackId'] == selectedTrackId);
    if (startIdx == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Не удалось загрузить выбранный трек")),
      );
      return;
    }

    await audioHandler.ready;
    await audioHandler.setTracksAndPlay(items, startIdx);
    if (!mounted) return;
    setState(() => _showMiniPlayer = true);
  }

  // ========== ДИАЛОГИ И ДЕЙСТВИЯ С ТРЕКАМИ ==========
  Future<void> _showTrackOptions(Map<String, String> track) async {
    FocusScope.of(context).unfocus();

    final trackId = track["trackId"]!;
    final isFavorite = track["isFavorite"] == "true";
    final isPinned = track["cached"] == "true";

    final options = <String>[];
    if (isFavorite) {
      options.add("Удалить из избранного");
    } else {
      options.add("Добавить в избранное");
    }
    if (isPinned) {
      options.add("Удалить из кэша");
    } else {
      options.add("Закрепить в кэше");
    }
    options.add("Похожие треки");
    options.add("Треки исполнителя");
    options.add("Текст песни");

    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: ArticTheme.backgroundDarkest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((opt) => ListTile(
            title: Text(opt, style: TextStyle(color: ArticTheme.primary)),
            onTap: () => Navigator.pop(context, opt),
          )).toList(),
        ),
      ),
    );

    if (result == null) return;

    if (result == "Добавить в избранное") {
      final success = await yandexProvider.likeTrack(trackId);
      if (success && mounted) {
        setState(() => track["isFavorite"] = "true");
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Добавлено в избранное")));
      }
    } else if (result == "Удалить из избранного") {
      final success = await yandexProvider.unlikeTrack(trackId);
      if (success && mounted) {
        setState(() => track["isFavorite"] = "false");
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Удалено из избранного")));
      }
    } else if (result == "Закрепить в кэше") {
      final title = track["title"]!;
      final artist = track["artist"]!;
      final cover = track["cover"]!;
      await yandexProvider.pinTrackWithMetadata(trackId, title, artist, cover);
      if (!mounted) return;
      setState(() => track["cached"] = "true");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Трек закреплён в кэше")));
    } else if (result == "Удалить из кэша") {
      yandexProvider.unpinTrack(trackId);
      if (!mounted) return;
      setState(() => track["cached"] = "false");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Трек удалён из кэша")));
    } else if (result == "Похожие треки") {
      final similar = await yandexProvider.getSimilarTracks(trackId);
      if (!mounted) return;
      _showTracksDialog("Похожие треки", similar);
    } else if (result == "Треки исполнителя") {
      final artistName = await yandexProvider.getArtistNameFromTrack(trackId);
      if (artistName != null) {
        final artistTracks = await yandexProvider.getArtistTracks(artistName);
        if (!mounted) return;
        _showTracksDialog("Треки исполнителя: $artistName", artistTracks);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Не удалось найти исполнителя")));
      }
    } else if (result == "Текст песни") {
      final lyrics = await yandexProvider.getLyrics(trackId);
      if (!mounted) return;
      if (lyrics != null && lyrics.isNotEmpty) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: ArticTheme.backgroundDarkest,
            title: Text(track["title"]!, style: TextStyle(color: ArticTheme.primary)),
            content: SingleChildScrollView(child: Text(lyrics, style: TextStyle(color: ArticTheme.secondary))),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text("Закрыть", style: TextStyle(color: ArticTheme.accent)))],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Текст не найден")));
      }
    }
  }

  void _showTracksDialog(String title, List<Map<String, String>> tracks) {
    FocusScope.of(context).unfocus();

    showModalBottomSheet(
      context: context,
      backgroundColor: ArticTheme.backgroundDarkest,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(kHorizontalPadding),
              child: Text(title, style: TextStyle(color: ArticTheme.primary, fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: tracks.length,
                itemBuilder: (context, i) {
                  final track = tracks[i];
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: track["cover"]!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: Colors.white10),
                        errorWidget: (_, __, ___) => Container(color: Colors.white10, child: const Icon(Icons.music_note)),
                      ),
                    ),
                    title: Text(track["title"]!, style: TextStyle(color: ArticTheme.primary)),
                    subtitle: Text(track["artist"]!, style: TextStyle(color: ArticTheme.secondary)),
                    onTap: () async {
                      Navigator.pop(context);
                      await _playTracksFromDialog(tracks, i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========== ВЫБОР ТРЕКА ИЗ БИБЛИОТЕКИ ==========
  Future<void> _selectTrackFromLibrary(int index) async {
    final tracksList = yandexProvider.tracks;
    if (index >= tracksList.length) return;

    if (!mounted) return;
    setState(() {
      _isSwitchingTrack = true;
      _loadingTrackIndex = index;
    });

    final List<Future<Map<String, dynamic>?>> futures = [];
    for (final track in tracksList) {
      final trackId = track['trackId']!;
      futures.add(
        yandexProvider.getDirectUrl(trackId).then((url) {
          if (url == null || url.isEmpty) return null;
          return {
            'url': url,
            'title': track['title']!,
            'artist': track['artist']!,
            'cover': track['cover']!,
            'trackId': trackId,
          };
        }).catchError((e) {
          debugPrint('Ошибка получения ссылки для $trackId: $e');
          return null;
        }),
      );
    }

    final results = await Future.wait(futures);

    if (!mounted) {
      setState(() => _isSwitchingTrack = false);
      return;
    }

    final itemsAll = <MediaItem>[];
    for (final result in results) {
      if (result != null) {
        itemsAll.add(MediaItem(
          id: result['url']!,
          album: "",
          title: result['title']!,
          artist: result['artist']!,
          artUri: Uri.parse(result['cover']!),
          extras: {'trackId': result['trackId']!},
        ));
      }
    }

    setState(() => _isSwitchingTrack = false);

    if (itemsAll.isEmpty) {
      setState(() => _loadingTrackIndex = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Не удалось загрузить ни одного трека")),
      );
      return;
    }

    final selectedTrackId = tracksList[index]['trackId']!;
    int startIdx = itemsAll.indexWhere((item) => item.extras?['trackId'] == selectedTrackId);
    if (startIdx == -1) {
      setState(() => _loadingTrackIndex = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Не удалось загрузить выбранный трек")),
      );
      return;
    }

    setState(() {
      _currentMediaItem = itemsAll[startIdx];
      _showMiniPlayer = true;
      _loadingTrackIndex = null;
    });

    _refreshDominantColor();

    try {
      await audioHandler.ready;
      await audioHandler.setTracksAndPlay(itemsAll, startIdx);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingTrackIndex = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Ошибка воспроизведения: $e")),
      );
    }
  }

  // ========== ВЫБОР ТРЕКА ИЗ КЭША ==========
  Future<void> _selectCachedTrack(int index) async {
    final cachedTracks = yandexProvider.cachedTracks;
    if (index >= cachedTracks.length) return;

    if (!mounted) return;
    setState(() {
      _isSwitchingTrack = true;
      _loadingTrackIndex = index;
    });

    final trackData = cachedTracks[index];
    final trackUrl = trackData['url'];
    if (trackUrl == null || trackUrl.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isSwitchingTrack = false;
        _loadingTrackIndex = null;
      });
      return;
    }

    final items = cachedTracks.where((t) => t['url'] != null && t['url']!.isNotEmpty).map((t) {
      return MediaItem(
        id: t['url']!,
        album: "",
        title: t['title']!,
        artist: t['artist']!,
        artUri: Uri.parse(t['cover']!),
        extras: {'trackId': t['trackId']!},
      );
    }).toList();

    if (!mounted) return;
    setState(() => _isSwitchingTrack = false);

    final startIdx = items.indexWhere((item) => item.id == trackUrl);
    if (startIdx == -1) {
      setState(() => _loadingTrackIndex = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Не удалось загрузить выбранный трек")),
      );
      return;
    }

    setState(() {
      _currentMediaItem = items[startIdx];
      _showMiniPlayer = true;
      _loadingTrackIndex = null;
    });

    try {
      await audioHandler.ready;
      await audioHandler.setTracksAndPlay(items, startIdx);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingTrackIndex = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Ошибка воспроизведения: $e")),
      );
    }
  }

  void _openFullPlayer() {
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      PageRouteBuilder(
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => FullPlayerPage(initialDominantColor: _dominantColor),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mediaItemSubscription?.cancel();
    _playbackStateSubscription?.cancel();
    _colorCancelToken?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isPlaying = audioHandler.playbackState.value.playing;
    final isLoading = yandexProvider.isLoading ||
        audioHandler.playbackState.value.processingState == AudioProcessingState.loading ||
        audioHandler.playbackState.value.processingState == AudioProcessingState.buffering;

    final miniTrack = _currentMediaItem != null
        ? {
            'title': _currentMediaItem!.title,
            'artist': _currentMediaItem!.artist ?? '',
            'cover': _currentMediaItem!.artUri?.toString() ?? '',
            'url': _currentMediaItem!.id,
            'trackId': _currentMediaItem!.extras?['trackId'] as String? ?? '',
          }
        : (yandexProvider.tracks.isNotEmpty
            ? yandexProvider.tracks[0]
            : {"title": "Нет треков", "artist": "", "cover": "", "url": "", "trackId": ""});

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: RepaintBoundary(
        child: Stack(
          children: [
            RepaintBoundary(
              child: Container(decoration: BoxDecoration(gradient: ArticTheme.backgroundGradient)),
            ),
            const RepaintBoundary(
              child: MatrixBackground(opacity: 0.009, numberOfDrops: 25),
            ),
            RepaintBoundary(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.8,
                    colors: [
                      _dominantColor.withValues(alpha: 0.06),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: kHorizontalPadding, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _TabButton(
                          label: "Библиотека",
                          isActive: _currentTab == 0,
                          onTap: () => _changeTab(0),
                        ),
                        const SizedBox(width: 16),
                        _TabButton(
                          label: "Поиск",
                          isActive: _currentTab == 1,
                          onTap: () => _changeTab(1),
                        ),
                        const SizedBox(width: 16),
                        _TabButton(
                          label: "Настройки",
                          isActive: _currentTab == 2,
                          onTap: () => _changeTab(2),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const ClampingScrollPhysics(),
                    onPageChanged: (index) {
                      setState(() => _currentTab = index);
                      if (index == 0 && DateTime.now().difference(_lastLibraryUpdate).inSeconds > 30) {
                        _refreshFavorites();
                      }
                    },
                    children: [
                      _LibraryTabs(
                        allTracks: yandexProvider.tracks,
                        cachedTracks: yandexProvider.cachedTracks,
                        onSelectAllTrack: _selectTrackFromLibrary,
                        onSelectCachedTrack: _selectCachedTrack,
                        isLoading: yandexProvider.isLoading,
                        loadingIndex: _loadingTrackIndex,
                        onLongPressTrack: _showTrackOptions,
                        onRefresh: _refreshFavorites,
                        onRefreshCached: _refreshCached,
                        hasInternet: yandexProvider.hasInternet,
                        onRetry: () {
                          _refreshFavorites();
                          setState(() {});
                        },
                      ),
                      _SearchContent(
                        onPlay: () {
                          setState(() {
                            _showMiniPlayer = true;
                          });
                        },
                        onLongPressTrack: _showTrackOptions,
                        onRequestSwitchStart: () {
                          setState(() {
                            _isSwitchingTrack = true;
                          });
                        },
                        onRequestSwitchEnd: () {
                          setState(() {
                            _isSwitchingTrack = false;
                          });
                        },
                        currentTrackId: _currentMediaItem?.extras?['trackId'] as String?,
                      ),
                      const _SettingsContent(),
                    ],
                  ),
                ),
              ],
            ),
            if (_showMiniPlayer && miniTrack["title"] != "Нет треков")
              Positioned(
                left: kHorizontalPadding,
                right: kHorizontalPadding,
                bottom: 8 + bottomPadding,
                child: _MiniPlayer(
                  track: miniTrack,
                  onTap: _openFullPlayer,
                  onPlayPause: _playPause,
                  onNext: _nextTrack,
                  onPrevious: _previousTrack,
                  isPlaying: isPlaying,
                  isLoading: isLoading || _loadingTrackIndex != null,
                ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.2, end: 0),
              ),
          ],
        ),
      ),
    );
  }
}

// ========== КНОПКИ ВКЛАДОК ==========
class _TabButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? ArticTheme.accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? ArticTheme.accent : ArticTheme.primary.withValues(alpha: 0.6),
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}