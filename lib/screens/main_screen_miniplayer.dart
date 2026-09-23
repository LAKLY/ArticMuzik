part of 'main_screen.dart';

class _MiniPlayerHost extends StatelessWidget {
  const _MiniPlayerHost();

  @override
  Widget build(BuildContext context) {
    final handler = Provider.of<AppAudioHandler>(context, listen: false);

    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      initialData: handler.mediaItem.value,
      builder: (context, mediaSnap) {
        final item = mediaSnap.data;
        if (item == null) return const SizedBox.shrink();

        return StreamBuilder<PlaybackState>(
          stream: handler.playbackState,
          initialData: handler.playbackState.value,
          builder: (context, psSnap) {
            final ps = psSnap.data;
            final isPlaying = ps?.playing ?? false;
            final isLoading = ps?.processingState == AudioProcessingState.loading ||
                ps?.processingState == AudioProcessingState.buffering;

            return _MiniPlayer(
              item: item,
              isPlaying: isPlaying,
              isLoading: isLoading,
              onTap: () => _openFullPlayer(context, item),
              onPlayPause: handler.playOrPause,
              onNext: handler.skipToNext,
              onPrevious: handler.skipToPrevious,
            );
          },
        );
      },
    );
  }

  void _openFullPlayer(BuildContext context, MediaItem item) {
    final mainState = context.findAncestorStateOfType<_MainScreenState>();
    if (mainState != null) {
      mainState._openFullPlayer();
    }
  }
}

class _MiniPlayer extends StatefulWidget {
  final MediaItem item;
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onTap;
  final Future<void> Function() onPlayPause;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;

  const _MiniPlayer({
    required this.item,
    required this.isPlaying,
    required this.isLoading,
    required this.onTap,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
  });

  @override
  State<_MiniPlayer> createState() => __MiniPlayerState();
}

class __MiniPlayerState extends State<_MiniPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  DateTime? _lastNextAt;
  DateTime? _lastPrevAt;
  DateTime? _lastPlayPauseAt;

  static const Duration _skipThrottle = Duration(milliseconds: 250);
  static const Duration _playPauseThrottle = Duration(milliseconds: 150);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    // Pulse только при playing
    if (widget.isPlaying) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _MiniPlayer old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isPlaying && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _safeHaptic() {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  void _handlePlayPause() {
    final now = DateTime.now();
    if (_lastPlayPauseAt != null &&
        now.difference(_lastPlayPauseAt!) < _playPauseThrottle) {
      return;
    }
    _lastPlayPauseAt = now;
    _safeHaptic();
    widget.onPlayPause();
  }

  void _handleNext() {
    final now = DateTime.now();
    if (_lastNextAt != null && now.difference(_lastNextAt!) < _skipThrottle) {
      return;
    }
    _lastNextAt = now;
    _safeHaptic();
    widget.onNext();
  }

  void _handlePrev() {
    final now = DateTime.now();
    if (_lastPrevAt != null && now.difference(_lastPrevAt!) < _skipThrottle) {
      return;
    }
    _lastPrevAt = now;
    _safeHaptic();
    widget.onPrevious();
  }

  void _onHorizontalDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 120) return;
    if (velocity > 0) {
      _handlePrev();
    } else {
      _handleNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    // НЕТ BackdropFilter, НЕТ ClipRRect на корне — они глушат hit-test.
    // GestureDetector только для drag, без onTap, чтобы не конкурировать с InkWell.
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onHorizontalDragEnd: _onHorizontalDrag,
      child: Container(
        decoration: BoxDecoration(
          gradient: ArticTheme.surfaceGradient,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: ArticTheme.accent.withValues(alpha: 0.35),
            width: 0.6,
          ),
          boxShadow: ArticTheme.glow(radius: 14),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _buildCover(),
                      const SizedBox(width: 12),
                      _buildTrackInfo(),
                      const SizedBox(width: 6),
                      _buildPrevButton(),
                      _buildPlayButton(),
                      _buildNextButton(),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const _MiniPlayerProgress(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover() {
    final cover = widget.item.artUri?.toString() ?? '';
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: ArticTheme.accent.withValues(alpha: 0.25),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: cover.isEmpty
            ? _placeholderCover()
            : CachedNetworkImage(
                imageUrl: cover,
                width: 46,
                height: 46,
                fit: BoxFit.cover,
                memCacheWidth: 92,
                memCacheHeight: 92,
                placeholder: (_, __) => _placeholderCover(),
                errorWidget: (_, __, ___) => _placeholderCover(),
              ),
      ),
    );
  }

  Widget _placeholderCover() {
    return Container(
      width: 46,
      height: 46,
      color: Colors.white10,
      child: const Icon(Icons.music_note, color: Colors.white38, size: 22),
    );
  }

  Widget _buildTrackInfo() {
    return Expanded(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.06, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: Column(
          key: ValueKey(widget.item.id),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.item.title,
              style: TextStyle(
                color: ArticTheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                letterSpacing: 0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              widget.item.artist ?? '',
              style: TextStyle(
                color: ArticTheme.secondary,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrevButton() {
    return SizedBox(
      width: 36,
      height: 36,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _handlePrev,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: ArticTheme.accent.withValues(alpha: 0.4),
                width: 1.0,
              ),
            ),
            child: Icon(
              Icons.skip_previous,
              color: ArticTheme.primary.withValues(alpha: 0.85),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNextButton() {
    return SizedBox(
      width: 36,
      height: 36,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _handleNext,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: ArticTheme.accent.withValues(alpha: 0.4),
                width: 1.0,
              ),
            ),
            child: Icon(
              Icons.skip_next,
              color: ArticTheme.primary.withValues(alpha: 0.85),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayButton() {
    // Кнопка ВСЕГДА кликабельна. Loader — overlay под IgnorePointer.
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Пульсирующий фон (не мешает тапу)
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final scale = 1.0 + 0.08 * _pulseController.value;
                return Transform.scale(
                  scale: widget.isPlaying ? scale : 1.0,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ArticTheme.accent.withValues(
                        alpha: 0.15 * _pulseController.value,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Кнопка
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: ArticTheme.accentGradient,
              boxShadow: ArticTheme.glow(radius: 12),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _handlePlayPause,
                child: Icon(
                  widget.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: ArticTheme.primary,
                  size: 24,
                ),
              ),
            ),
          ),
          // Лоадер поверх — не блокирует тап
          if (widget.isLoading)
            IgnorePointer(
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ArticTheme.backgroundDeep.withValues(alpha: 0.7),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniPlayerProgress extends StatelessWidget {
  const _MiniPlayerProgress();

  @override
  Widget build(BuildContext context) {
    final handler = Provider.of<AppAudioHandler>(context);
    return StreamBuilder<Duration>(
      stream: handler.positionStream,
      builder: (context, posSnap) {
        final position = posSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: handler.durationStream,
          builder: (context, durSnap) {
            final duration = durSnap.data ?? Duration.zero;
            final progress = duration.inSeconds > 0
                ? (position.inSeconds / duration.inSeconds).clamp(0.0, 1.0)
                : 0.0;
            return _ProgressBar(
              currentPosition: position,
              duration: duration,
              progress: progress,
            );
          },
        );
      },
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final Duration currentPosition;
  final Duration duration;
  final double progress;

  const _ProgressBar({
    required this.currentPosition,
    required this.duration,
    required this.progress,
  });

  String _formatTime(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            child: Text(
              _formatTime(currentPosition),
              style: TextStyle(
                fontSize: 9,
                fontFamily: 'StieglitzSP',
                color: ArticTheme.secondary.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 3,
                  child: Stack(
                    children: [
                      Container(
                        color: ArticTheme.secondary.withValues(alpha: 0.18),
                      ),
                      FractionallySizedBox(
                        widthFactor: progress.clamp(0.0, 1.0),
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: ArticTheme.accentGradient,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: ArticTheme.accent.withValues(alpha: 0.5),
                                blurRadius: 4,
                                spreadRadius: 0.5,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              _formatDuration(duration),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 9,
                fontFamily: 'StieglitzSP',
                color: ArticTheme.secondary.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d == Duration.zero) return '--:--';
    return _formatTime(d);
  }
}