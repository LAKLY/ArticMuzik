part of 'main_screen.dart';

/// Хост mini-player'а — сам подписывается на потоки handler'а.
/// Родитель передаёт только onTap (открыть full player).
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
  bool _isDisposed = false;

  // Throttle: не чаще, чем раз в 350мс для next/prev
  DateTime? _lastSkipAt;
  static const Duration _skipThrottle = Duration(milliseconds: 350);

  // То же для паузы
  DateTime? _lastPlayPauseAt;
  static const Duration _playPauseThrottle = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _pulseController.dispose();
    super.dispose();
  }

  void _safeHaptic() {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  Future<void> _handleNext() async {
    final now = DateTime.now();
    if (_lastSkipAt != null && now.difference(_lastSkipAt!) < _skipThrottle) {
      return;
    }
    _lastSkipAt = now;
    _safeHaptic();
    await widget.onNext();
  }

  Future<void> _handlePrevious() async {
    final now = DateTime.now();
    if (_lastSkipAt != null && now.difference(_lastSkipAt!) < _skipThrottle) {
      return;
    }
    _lastSkipAt = now;
    _safeHaptic();
    await widget.onPrevious();
  }

  Future<void> _handlePlayPause() async {
    final now = DateTime.now();
    if (_lastPlayPauseAt != null &&
        now.difference(_lastPlayPauseAt!) < _playPauseThrottle) {
      return;
    }
    _lastPlayPauseAt = now;
    _safeHaptic();
    await widget.onPlayPause();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() > 100) {
          if (velocity > 0) {
            _handlePrevious();
          } else {
            _handleNext();
          }
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              gradient: ArticTheme.surfaceGradient,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: ArticTheme.accent.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      _buildCover(),
                      const SizedBox(width: 12),
                      _buildTrackInfo(),
                      _buildControlButtons(),
                    ],
                  ),
                ),
                const _MiniPlayerProgress(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover() {
    final cover = widget.item.artUri?.toString() ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: cover.isEmpty
          ? _placeholderCover()
          : CachedNetworkImage(
              imageUrl: cover,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              memCacheWidth: 96,
              memCacheHeight: 96,
              placeholder: (_, __) => _placeholderCover(),
              errorWidget: (_, __, ___) => _placeholderCover(),
            ),
    );
  }

  Widget _placeholderCover() {
    return Container(
      width: 48,
      height: 48,
      color: Colors.white10,
      child: const Icon(Icons.music_note, color: Colors.white38),
    );
  }

  Widget _buildTrackInfo() {
    return Expanded(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.05, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: Column(
          key: ValueKey(widget.item.id),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.item.title,
              style: TextStyle(
                color: ArticTheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.item.artist ?? '',
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
    );
  }

  Widget _buildControlButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildControlButton(
          icon: Icons.skip_previous,
          onTap: _handlePrevious,
        ),
        const SizedBox(width: 4),
        _buildPlayButton(),
        const SizedBox(width: 4),
        _buildControlButton(
          icon: Icons.skip_next,
          onTap: _handleNext,
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Future<void> Function() onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Icon(
          icon,
          color: ArticTheme.primary.withValues(alpha: 0.7),
          size: 32,
        ),
      ),
    );
  }

  Widget _buildPlayButton() {
    if (widget.isLoading) {
      return const SizedBox(
        width: 44,
        height: 44,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _handlePlayPause,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final scale = 1.0 + 0.06 * _pulseController.value;
          return Transform.scale(scale: scale, child: child);
        },
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: ArticTheme.accentGradient,
            boxShadow: ArticTheme.glow(radius: 16),
          ),
          child: Icon(
            widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: ArticTheme.primary,
            size: 26,
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(
            _formatTime(currentPosition),
            style: TextStyle(
              fontSize: 9,
              fontFamily: 'StieglitzSP',
              color: ArticTheme.secondary.withValues(alpha: 0.6),
            ),
          ),
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: ArticTheme.secondary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(1),
              ),
              child: FractionallySizedBox(
                widthFactor: progress,
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: ArticTheme.accentGradient,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
          ),
          Text(
            _formatDuration(duration),
            style: TextStyle(
              fontSize: 9,
              fontFamily: 'StieglitzSP',
              color: ArticTheme.secondary.withValues(alpha: 0.6),
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