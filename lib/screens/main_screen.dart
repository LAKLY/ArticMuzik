import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import '../theme/artic_theme.dart';
import '../utils/color_utils.dart';
import '../screens/full_player_page.dart';
import '../services/audio_handler.dart';
import '../services/yandex/yandex_audio_provider.dart';
import '../services/yandex/yandex_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/theme_notifier.dart';
import 'storage_manager_screen.dart';
import 'downloads_screen.dart';
import 'history_screen.dart';
import 'queue_sheet.dart';

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

  /// Notifier'ы вместо полей + setState. Обновляются из подписок,
  /// не пересобирают MainScreen. Слушают их только конкретные виджеты
  /// (фон и SearchContent).
  final ValueNotifier<MediaItem?> _mediaItemNotifier =
      ValueNotifier<MediaItem?>(null);
  final ValueNotifier<Color> _dominantColorNotifier =
      ValueNotifier<Color>(ArticTheme.accent);

  StreamSubscription<MediaItem?>? _mediaItemSubscription;
  StreamSubscription<String>? _playbackErrorsSubscription;
  String? _lastDominantColorCover;
  CancelToken? _colorCancelToken;
  bool _depsInitialized = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentTab);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_depsInitialized) return;
    _depsInitialized = true;

    audioHandler = Provider.of<AppAudioHandler>(context, listen: false);
    yandexProvider = Provider.of<YandexAudioProvider>(context, listen: false);

    // Единственная подписка MainScreen — обновляем ValueNotifier'ы.
    // setState не вызывается, MainScreen.build не пересобирается.
    _mediaItemSubscription = audioHandler.mediaItem.listen((item) {
      _mediaItemNotifier.value = item;
      _refreshDominantColor();
    });
    _playbackErrorsSubscription =
        audioHandler.playbackErrors.listen(_onPlaybackError);

    // Стартовое значение
    _mediaItemNotifier.value = audioHandler.mediaItem.value;
    _refreshDominantColor();
  }

  void _onPlaybackError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _refreshDominantColor() async {
    final currentTrack = audioHandler.mediaItem.value;
    if (currentTrack == null) return;
    final coverUrl = currentTrack.artUri?.toString();
    if (coverUrl == null || coverUrl.isEmpty) return;
    if (coverUrl == _lastDominantColorCover) return;
    _lastDominantColorCover = coverUrl;

    _colorCancelToken?.cancel();
    _colorCancelToken = CancelToken();
    final color = await ColorUtils.extractDominantColor(
      coverUrl,
      fallback: ArticTheme.accent,
      cancelToken: _colorCancelToken,
    );
    if (mounted && _colorCancelToken?.isCancelled == false) {
      _dominantColorNotifier.value = color;
    }
  }

  void _changeTab(int newTab) {
    if (_currentTab == newTab) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    _pageController.animateToPage(
      newTab,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _refreshFavorites() async {
    await yandexProvider.loadFavorites();
  }

  Future<void> _refreshCached() async {
    await yandexProvider.reloadCachedTracks();
  }

  // ========== ФОРМИРОВАНИЕ ОЧЕРЕДИ ==========

  /// Лениво: URL тянем только для стартового + 2 соседей.
  /// Остальные — плейсхолдеры. AudioHandler подтянет их при skipToNext.
  Future<void> _playTracksFromDialog(
      List<Map<String, String>> tracks, int selectedIndex) async {
    if (!mounted) return;
    await _playLazyQueue(tracks, selectedIndex);
  }

  Future<void> _playLazyQueue(
      List<Map<String, String>> tracks, int selectedIndex) async {
    if (tracks.isEmpty) return;

    final preload = <int>{
      selectedIndex,
      if (selectedIndex + 1 < tracks.length) selectedIndex + 1,
      if (selectedIndex + 2 < tracks.length) selectedIndex + 2,
    };

    // Сначала подтянем URL для окна preload — параллельно.
    final urlMap = <int, String>{};
    await Future.wait(preload.map((i) async {
      final t = tracks[i];
      final url = await yandexProvider.getDirectUrl(t['trackId']!);
      if (url != null && url.isNotEmpty) urlMap[i] = url;
    }));

    // Стартовый обязательно должен быть
    final startUrl = urlMap[selectedIndex];
    if (startUrl == null || startUrl.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Не удалось загрузить трек")),
      );
      return;
    }

    final items = <MediaItem>[];
    for (int i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      final trackId = t['trackId']!;
      final url = urlMap[i];
      items.add(
        MediaItem(
          id: url ?? 'pending:$trackId',
          album: "",
          title: t['title'] ?? '',
          artist: t['artist'] ?? '',
          artUri: (t['cover'] ?? '').isNotEmpty
              ? Uri.parse(t['cover']!)
              : null,
          extras: {'trackId': trackId},
        ),
      );
    }

    await audioHandler.ready;
    await audioHandler.setTracksAndPlay(items, selectedIndex);
  }

  // ========== ДИАЛОГИ И ДЕЙСТВИЯ С ТРЕКАМИ ==========
  Future<void> _showTrackOptions(Map<String, String> track) async {
    FocusScope.of(context).unfocus();

    final trackId = track["trackId"]!;
    final isFavorite = track["isFavorite"] == "true";
    final isPinned = track["cached"] == "true";

    final options = <String>[];
    options.add("Играть следующим");
    options.add("В конец очереди");
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
          children: options
              .map((opt) => ListTile(
                    title:
                        Text(opt, style: TextStyle(color: ArticTheme.primary)),
                    onTap: () => Navigator.pop(context, opt),
                  ))
              .toList(),
        ),
      ),
    );

    if (result == null) return;

    if (result == "Играть следующим") {
      final url = await yandexProvider.getDirectUrl(trackId);
      if (url == null || url.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Не удалось загрузить трек")));
        return;
      }
      final mediaItem = MediaItem(
        id: url,
        album: "",
        title: track["title"]!,
        artist: track["artist"]!,
        artUri: Uri.parse(track["cover"]!),
        extras: {'trackId': trackId},
      );
      await audioHandler.playNext(mediaItem);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Играет следующим")));
      return;
    } else if (result == "В конец очереди") {
      final url = await yandexProvider.getDirectUrl(trackId);
      if (url == null || url.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Не удалось загрузить трек")));
        return;
      }
      final mediaItem = MediaItem(
        id: url,
        album: "",
        title: track["title"]!,
        artist: track["artist"]!,
        artUri: Uri.parse(track["cover"]!),
        extras: {'trackId': trackId},
      );
      await audioHandler.addToQueueEnd(mediaItem);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Добавлено в конец очереди")));
      return;
    } else if (result == "Добавить в избранное") {
      final success = await yandexProvider.likeTrack(trackId);
      if (success && mounted) {
        setState(() => track["isFavorite"] = "true");
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Добавлено в избранное")));
      }
    } else if (result == "Удалить из избранного") {
      final success = await yandexProvider.unlikeTrack(trackId);
      if (success && mounted) {
        setState(() => track["isFavorite"] = "false");
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Удалено из избранного")));
      }
    } else if (result == "Закрепить в кэше") {
      final title = track["title"]!;
      final artist = track["artist"]!;
      final cover = track["cover"]!;
      await yandexProvider.pinTrackWithMetadata(trackId, title, artist, cover);
      if (!mounted) return;
      setState(() => track["cached"] = "true");
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Трек закреплён в кэше")));
    } else if (result == "Удалить из кэша") {
      await yandexProvider.unpinTrack(trackId);
      if (!mounted) return;
      setState(() => track["cached"] = "false");
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Трек удалён из кэша")));
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
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Не удалось найти исполнителя")));
      }
    } else if (result == "Текст песни") {
      final lyrics = await yandexProvider.getLyrics(trackId);
      if (!mounted) return;
      if (lyrics != null && lyrics.isNotEmpty) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: ArticTheme.backgroundDarkest,
            title: Text(track["title"]!,
                style: TextStyle(color: ArticTheme.primary)),
            content: SingleChildScrollView(
                child: Text(lyrics,
                    style: TextStyle(color: ArticTheme.secondary))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Закрыть",
                      style: TextStyle(color: ArticTheme.accent)))
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Текст не найден")));
      }
    }
  }

  void _showTracksDialog(String title, List<Map<String, String>> tracks) {
    FocusScope.of(context).unfocus();

    showModalBottomSheet(
      context: context,
      backgroundColor: ArticTheme.backgroundDarkest,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(kHorizontalPadding),
              child: Text(title,
                  style: TextStyle(
                      color: ArticTheme.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
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
                        placeholder: (_, __) =>
                            Container(color: Colors.white10),
                        errorWidget: (_, __, ___) => Container(
                            color: Colors.white10,
                            child: const Icon(Icons.music_note)),
                      ),
                    ),
                    title: Text(track["title"]!,
                        style: TextStyle(color: ArticTheme.primary)),
                    subtitle: Text(track["artist"]!,
                        style: TextStyle(color: ArticTheme.secondary)),
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
    setState(() => _loadingTrackIndex = index);

    try {
      await _playLazyQueue(tracksList, index);
    } catch (e) {
      debugPrint('selectTrack error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Ошибка воспроизведения: $e")),
      );
    } finally {
      if (mounted) setState(() => _loadingTrackIndex = null);
    }
  }

  // ========== PLAY ALL / SHUFFLE ALL ==========
  /// Играть всю библиотеку с начала.
  Future<void> _playLibraryAll() async {
    final list = yandexProvider.tracks;
    if (list.isEmpty) return;
    await _playLazyQueue(list, 0);
  }

  /// Играть всю библиотеку вперемешку.
  Future<void> _playLibraryShuffle() async {
    final list = List<Map<String, String>>.from(yandexProvider.tracks);
    if (list.isEmpty) return;
    list.shuffle();
    await _playLazyQueue(list, 0);
  }

  // ========== ВЫБОР ТРЕКА ИЗ КЭША ==========
  Future<void> _selectCachedTrack(int index) async {
    final cachedTracks = yandexProvider.cachedTracks;
    if (index >= cachedTracks.length) return;

    if (!mounted) return;
    setState(() => _loadingTrackIndex = index);

    final trackData = cachedTracks[index];
    final trackUrl = trackData['url'];
    if (trackUrl == null || trackUrl.isEmpty) {
      if (!mounted) return;
      setState(() => _loadingTrackIndex = null);
      return;
    }

    final items = cachedTracks
        .where((t) => t['url'] != null && t['url']!.isNotEmpty)
        .map((t) {
      return MediaItem(
        id: t['url']!,
        album: "",
        title: t['title']!,
        artist: t['artist']!,
        artUri: Uri.parse(t['cover']!),
        extras: {'trackId': t['trackId']!},
      );
    }).toList();

    final startIdx = items.indexWhere((item) => item.id == trackUrl);
    if (startIdx == -1) {
      if (!mounted) return;
      setState(() => _loadingTrackIndex = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Не удалось загрузить выбранный трек")),
      );
      return;
    }

    try {
      await audioHandler.ready;
      await audioHandler.setTracksAndPlay(items, startIdx);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Ошибка воспроизведения: $e")),
      );
    } finally {
      if (mounted) setState(() => _loadingTrackIndex = null);
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
        pageBuilder: (_, __, ___) => FullPlayerPage(
            initialDominantColor: _dominantColorNotifier.value),
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
    _playbackErrorsSubscription?.cancel();
    _colorCancelToken?.cancel();
    _pageController.dispose();
    _mediaItemNotifier.dispose();
    _dominantColorNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: RepaintBoundary(
        child: Stack(
          children: [
            RepaintBoundary(
              child: Container(
                  decoration:
                      BoxDecoration(gradient: ArticTheme.backgroundGradient)),
            ),
            // Доминант-цвет — только для фона. Обновляется без
            // перестройки MainScreen.
            RepaintBoundary(
              child: ValueListenableBuilder<Color>(
                valueListenable: _dominantColorNotifier,
                builder: (context, color, _) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.8,
                        colors: [
                          color.withValues(alpha: 0.06),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: kHorizontalPadding, vertical: 8),
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
                if (!yandexProvider.hasInternet) const _OfflineBanner(),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const ClampingScrollPhysics(),
                    allowImplicitScrolling: false,
                    onPageChanged: (index) {
                      setState(() => _currentTab = index);
                    },
                    children: [
                      // Селектор по sortMode: пересобирает _LibraryTabs
                      // только при смене режима сортировки.
                      Selector<YandexAudioProvider, LibrarySortMode>(
                        selector: (_, p) => p.sortMode,
                        builder: (context, sortMode, _) {
                          return _LibraryTabs(
                            allTracks: yandexProvider.tracks,
                            cachedTracks: yandexProvider.cachedTracks,
                            sortMode: sortMode,
                            onSortChanged: yandexProvider.setSortMode,
                            onPlayAll: _playLibraryAll,
                            onPlayShuffleAll: _playLibraryShuffle,
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
                          );
                        },
                      ),
                      _SearchContent(
                        onPlay: () {},
                        onLongPressTrack: _showTrackOptions,
                        onRequestSwitchStart: () {},
                        onRequestSwitchEnd: () {},
                        mediaItemListenable: _mediaItemNotifier,
                      ),
                      const _SettingsContent(),
                    ],
                  ),
                ),
              ],
            ),
            // MiniPlayer рендерится всегда. Внутри сам проверит,
            // есть ли активный трек, и покажет себя / скроется.
            Positioned(
              left: kHorizontalPadding,
              right: kHorizontalPadding,
              bottom: 8 + bottomPadding,
              child: const _MiniPlayerHost(),
            ),
          ],
        ),
      ),
    );
  }
}

// ========== БАННЕР ОФЛАЙН ==========
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: kHorizontalPadding, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: ArticTheme.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ArticTheme.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 14, color: ArticTheme.accent),
          const SizedBox(width: 6),
          Text(
            'Офлайн — доступны только сохранённые треки',
            style: TextStyle(color: ArticTheme.accent, fontSize: 11),
          ),
        ],
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
          color: isActive
              ? ArticTheme.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive
                ? ArticTheme.accent
                : ArticTheme.primary.withValues(alpha: 0.6),
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}