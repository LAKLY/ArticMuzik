part of 'main_screen.dart';

/// Состояние, от которого зависит отрисовка карточки трека.
@immutable
class _TrackUIState {
  final String? currentTrackId;
  final bool playing;

  const _TrackUIState(this.currentTrackId, this.playing);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TrackUIState &&
          currentTrackId == other.currentTrackId &&
          playing == other.playing;

  @override
  int get hashCode => Object.hash(currentTrackId, playing);
}

/// Высота карточки.
///   48 (cover) + 12*2 (padding) + 10 (margin) = 82
const double _kTrackTileExtent = 82.0;

class _LibraryTabs extends StatefulWidget {
  final List<Map<String, String>> allTracks;
  final List<Map<String, String>> cachedTracks;
  final LibrarySortMode sortMode;
  final ValueChanged<LibrarySortMode> onSortChanged;
  final VoidCallback onPlayAll;
  final VoidCallback onPlayShuffleAll;
  final Function(int) onSelectAllTrack;
  final Function(int) onSelectCachedTrack;
  final bool isLoading;
  final int? loadingIndex;
  final Function(Map<String, String>) onLongPressTrack;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onRefreshCached;
  final bool hasInternet;
  final VoidCallback onRetry;

  const _LibraryTabs({
    required this.allTracks,
    required this.cachedTracks,
    required this.sortMode,
    required this.onSortChanged,
    required this.onPlayAll,
    required this.onPlayShuffleAll,
    required this.onSelectAllTrack,
    required this.onSelectCachedTrack,
    required this.isLoading,
    required this.loadingIndex,
    required this.onLongPressTrack,
    required this.onRefresh,
    required this.onRefreshCached,
    required this.hasInternet,
    required this.onRetry,
  });

  @override
  State<_LibraryTabs> createState() => __LibraryTabsState();
}

class __LibraryTabsState extends State<_LibraryTabs>
    with TickerProviderStateMixin {
  late TabController _tabController;
  int _lastSelectedTab = 0;

  /// Состояние свёрнутой/развёрнутой панели управления.
  /// По умолчанию — свёрнута.
  bool _toolbarExpanded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    if (!widget.hasInternet) {
      _tabController.index = 1;
      _lastSelectedTab = 1;
    }

    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;

    final newIndex = _tabController.index;

    if (newIndex == 0 && !widget.hasInternet) {
      _tabController.index = _lastSelectedTab;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нет интернета, доступен только офлайн-режим'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      _lastSelectedTab = newIndex;

      if (newIndex == 1) {
        widget.onRefreshCached();
      }
    }
  }

  @override
  void didUpdateWidget(_LibraryTabs oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.hasInternet && _tabController.index == 0) {
      _tabController.index = 1;
      _lastSelectedTab = 1;
    }
  }

  void _toggleToolbar() {
    HapticFeedback.selectionClick();
    setState(() => _toolbarExpanded = !_toolbarExpanded);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // --- Верхняя полоса: TabBar + стрелочка ---
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TabBar(
                controller: _tabController,
                labelColor: ArticTheme.accent,
                unselectedLabelColor: ArticTheme.secondary,
                indicatorColor: ArticTheme.accent,
                tabs: const [
                  Tab(text: 'ВСЕ'),
                  Tab(text: 'КЭШ'),
                ],
              ),
            ),
            // Маленькая стрелочка. Крутится при раскрытии.
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _ToolbarChevron(
                expanded: _toolbarExpanded,
                onTap: _toggleToolbar,
              ),
            ),
          ],
        ),

        // --- Свёртываемая панель управления ---
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _toolbarExpanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 8, 4),
                  child: Row(
                    children: [
                      _SortMenu(
                        mode: widget.sortMode,
                        onChanged: widget.onSortChanged,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Играть всё',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.play_circle_outline,
                          color: ArticTheme.primary.withValues(alpha: 0.9),
                        ),
                        onPressed: widget.onPlayAll,
                      ),
                      IconButton(
                        tooltip: 'Играть вперемешку',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.shuffle,
                          color: ArticTheme.primary.withValues(alpha: 0.9),
                        ),
                        onPressed: widget.onPlayShuffleAll,
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const ClampingScrollPhysics(),
            children: [
              widget.hasInternet
                  ? _TrackList(
                      key: const PageStorageKey('all_tracks_list'),
                      tracks: widget.allTracks,
                      onSelectTrack: widget.onSelectAllTrack,
                      isLoading: widget.isLoading,
                      loadingIndex: widget.loadingIndex,
                      onLongPressTrack: widget.onLongPressTrack,
                      onRefresh: widget.onRefresh,
                    )
                  : _buildNoInternetWidget(),
              _TrackList(
                key: const PageStorageKey('cached_tracks_list'),
                tracks: widget.cachedTracks,
                onSelectTrack: widget.onSelectCachedTrack,
                isLoading: false,
                loadingIndex: widget.loadingIndex,
                onLongPressTrack: widget.onLongPressTrack,
                onRefresh: widget.onRefreshCached,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNoInternetWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, color: ArticTheme.secondary, size: 48),
          const SizedBox(height: 16),
          Text(
            'Нет подключения к интернету',
            style: TextStyle(color: ArticTheme.secondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: widget.onRetry,
            style: ElevatedButton.styleFrom(backgroundColor: ArticTheme.accent),
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

/// Кнопка-стрелочка. Плавно вращается при изменении [expanded].
class _ToolbarChevron extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;

  const _ToolbarChevron({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: AnimatedRotation(
          turns: expanded ? 0.5 : 0.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: ArticTheme.primary.withValues(alpha: 0.75),
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// Компактное меню сортировки.
class _SortMenu extends StatelessWidget {
  final LibrarySortMode mode;
  final ValueChanged<LibrarySortMode> onChanged;

  const _SortMenu({required this.mode, required this.onChanged});

  IconData _icon() {
    switch (mode) {
      case LibrarySortMode.dateAdded:
        return Icons.schedule;
      case LibrarySortMode.title:
        return Icons.sort_by_alpha;
      case LibrarySortMode.artist:
        return Icons.person_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<LibrarySortMode>(
      tooltip: 'Сортировка',
      initialValue: mode,
      onSelected: onChanged,
      color: ArticTheme.backgroundDarkest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (_) => LibrarySortMode.values.map((m) {
        return PopupMenuItem<LibrarySortMode>(
          value: m,
          child: Row(
            children: [
              if (m == mode)
                Icon(Icons.check, color: ArticTheme.accent, size: 18)
              else
                const SizedBox(width: 18),
              const SizedBox(width: 10),
              Text(m.label, style: TextStyle(color: ArticTheme.primary)),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: ArticTheme.backgroundDarkest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ArticTheme.accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon(), size: 16, color: ArticTheme.accent),
            const SizedBox(width: 6),
            Text(
              mode.label,
              style: TextStyle(
                color: ArticTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackList extends StatefulWidget {
  final List<Map<String, String>> tracks;
  final Function(int) onSelectTrack;
  final bool isLoading;
  final int? loadingIndex;
  final Function(Map<String, String>) onLongPressTrack;
  final Future<void> Function() onRefresh;

  const _TrackList({
    super.key,
    required this.tracks,
    required this.onSelectTrack,
    this.isLoading = false,
    this.loadingIndex,
    required this.onLongPressTrack,
    required this.onRefresh,
  });

  @override
  State<_TrackList> createState() => _TrackListState();
}

class _TrackListState extends State<_TrackList>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final ValueNotifier<_TrackUIState> _uiNotifier;

  StreamSubscription<MediaItem?>? _mediaSub;
  StreamSubscription<bool>? _playingSub;
  bool _subsInitialized = false;

  @override
  void initState() {
    super.initState();
    _uiNotifier = ValueNotifier<_TrackUIState>(
      const _TrackUIState(null, false),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_subsInitialized) return;
    _subsInitialized = true;

    final handler = Provider.of<AppAudioHandler>(context, listen: false);

    final initial = handler.mediaItem.value;
    _uiNotifier.value = _TrackUIState(
      initial?.extras?['trackId'] as String?,
      handler.playbackState.value.playing,
    );

    _mediaSub = handler.mediaItem.listen((item) {
      final prev = _uiNotifier.value;
      final next = _TrackUIState(
        item?.extras?['trackId'] as String?,
        prev.playing,
      );
      if (next != prev) _uiNotifier.value = next;
    });

    _playingSub = handler.playbackState
        .map((s) => s.playing)
        .distinct()
        .listen((playing) {
      final prev = _uiNotifier.value;
      final next = _TrackUIState(prev.currentTrackId, playing);
      if (next != prev) _uiNotifier.value = next;
    });
  }

  @override
  void dispose() {
    _mediaSub?.cancel();
    _playingSub?.cancel();
    _uiNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.isLoading && widget.tracks.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.all(kVerticalPadding),
        itemExtent: _kTrackTileExtent,
        itemCount: 8,
        itemBuilder: (_, __) => const _SkeletonItem(),
      );
    }

    if (widget.tracks.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      color: ArticTheme.accent,
      child: ListView.builder(
        key: widget.key,
        padding: const EdgeInsets.all(kVerticalPadding),
        itemExtent: _kTrackTileExtent,
        itemCount: widget.tracks.length,
        itemBuilder: (context, index) {
          final track = widget.tracks[index];
          return _TrackTile(
            key: ValueKey(track['trackId']),
            track: track,
            trackIndex: index,
            uiState: _uiNotifier,
            loadingIndex: widget.loadingIndex,
            onTap: () => widget.onSelectTrack(index),
            onLongPress: () => widget.onLongPressTrack(track),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_off, size: 64, color: ArticTheme.secondary),
          const SizedBox(height: 16),
          Text("Нет треков", style: TextStyle(color: ArticTheme.secondary)),
          const SizedBox(height: 8),
          Text(
            "Добавьте треки в избранное в Яндекс.Музыке",
            style: TextStyle(
              color: ArticTheme.secondary.withValues(alpha: 0.5),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: widget.onRefresh,
            style: ElevatedButton.styleFrom(backgroundColor: ArticTheme.accent),
            child: Text("Обновить", style: TextStyle(color: ArticTheme.primary)),
          ),
        ],
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  final Map<String, String> track;
  final int trackIndex;
  final ValueListenable<_TrackUIState> uiState;
  final int? loadingIndex;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _TrackTile({
    super.key,
    required this.track,
    required this.trackIndex,
    required this.uiState,
    required this.loadingIndex,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onLongPress: onLongPress,
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      splashColor: ArticTheme.accent.withValues(alpha: 0.3),
      highlightColor: ArticTheme.accent.withValues(alpha: 0.1),
      child: ValueListenableBuilder<_TrackUIState>(
        valueListenable: uiState,
        builder: (context, state, _) {
          final isCurrent = state.currentTrackId == track['trackId'];
          final isPlaying = state.playing && isCurrent;
          final isLoading = loadingIndex == trackIndex;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: isCurrent
                  ? LinearGradient(
                      colors: [
                        ArticTheme.backgroundDarkest.withValues(alpha: 0.5),
                        Colors.transparent,
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
              borderRadius: BorderRadius.circular(20),
              border: isCurrent
                  ? Border.all(color: ArticTheme.accent, width: 1.2)
                  : null,
              color: isCurrent
                  ? null
                  : ArticTheme.backgroundDarkest.withValues(alpha: 0.6),
            ),
            child: Row(
              children: [
                _TileArt(url: track["cover"] ?? ''),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              track["title"] ?? '',
                              style: TextStyle(
                                color: isCurrent
                                    ? ArticTheme.primary
                                    : ArticTheme.primary
                                        .withValues(alpha: 0.9),
                                fontWeight: FontWeight.w500,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (track["isFavorite"] == "true")
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(Icons.favorite,
                                  size: 16, color: ArticTheme.accent),
                            ),
                          if (track["cached"] == "true")
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(Icons.download_done,
                                  size: 16, color: ArticTheme.secondary),
                            ),
                        ],
                      ),
                      Text(
                        track["artist"] ?? '',
                        style: TextStyle(
                          color: ArticTheme.secondary,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: isLoading
                      ? const CircularProgressIndicator(strokeWidth: 2.5)
                      : isCurrent && isPlaying
                          ? Icon(Icons.equalizer,
                              color: ArticTheme.primary, size: 28)
                          : Icon(Icons.play_circle_outline,
                              color: ArticTheme.accent.withValues(alpha: 0.7),
                              size: 28),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TileArt extends StatelessWidget {
  final String url;
  const _TileArt({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: url.isEmpty
          ? const _MusicPlaceholder()
          : CachedNetworkImage(
              imageUrl: url,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              memCacheWidth: 96,
              memCacheHeight: 96,
              placeholder: (_, __) => const _MusicPlaceholder(),
              errorWidget: (_, __, ___) => const _MusicPlaceholder(),
            ),
    );
  }
}

class _SkeletonItem extends StatelessWidget {
  const _SkeletonItem();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ArticTheme.backgroundDarkest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                    width: double.infinity, height: 16, color: Colors.white10),
                const SizedBox(height: 8),
                Container(width: 100, height: 12, color: Colors.white10),
              ],
            ),
          ),
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
                color: Colors.white10, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

class _MusicPlaceholder extends StatelessWidget {
  const _MusicPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      color: Colors.white10,
      child: const Icon(Icons.music_note, color: Colors.white38),
    );
  }
}