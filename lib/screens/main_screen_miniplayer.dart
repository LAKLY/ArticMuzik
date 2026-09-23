part of 'main_screen.dart';

class _MiniPlayer extends StatefulWidget {
  final Map<String, String> track;
  final VoidCallback onTap;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final bool isPlaying;
  final bool isLoading;

  const _MiniPlayer({
    required this.track,
    required this.onTap,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.isPlaying,
    required this.isLoading,
  });

  @override
  State<_MiniPlayer> createState() => __MiniPlayerState();
}

class __MiniPlayerState extends State<_MiniPlayer> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  
  bool _isDisposed = false;

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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() > 100) {
          try {
            HapticFeedback.lightImpact();
          } catch (e) {
            debugPrint('Haptic feedback error: $e');
          }
          
          if (velocity > 0) {
            widget.onPrevious();
          } else if (velocity < 0) {
            widget.onNext();
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      _buildCover(),
                      const SizedBox(width: 12),
                      _buildTrackInfo(),
                      _buildControlButtons(),
                    ],
                  ),
                ),
                const _MiniPlayerProgress(), // Обновлённый виджет прогресса
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: CachedNetworkImage(
        imageUrl: widget.track["cover"] ?? '',
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

  Widget _buildTrackInfo() {
    return Expanded(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
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
          key: ValueKey(widget.track["title"]),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.track["title"] ?? '',
              style: TextStyle(
                color: ArticTheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.track["artist"] ?? '',
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
          onTap: widget.onPrevious,
        ),
        const SizedBox(width: 4),
        _buildPlayButton(),
        const SizedBox(width: 4),
        _buildControlButton(
          icon: Icons.skip_next,
          onTap: widget.onNext,
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        try {
          HapticFeedback.lightImpact();
        } catch (e) {
          debugPrint('Haptic feedback error: $e');
        }
        onTap();
      },
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
    if (widget.isLoading && widget.track['trackId'] != null && widget.track['trackId']!.isNotEmpty) {
      return const SizedBox(
        width: 44,
        height: 44,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        try {
          HapticFeedback.lightImpact();
        } catch (e) {
          debugPrint('Haptic feedback error: $e');
        }
        widget.onPlayPause();
      },
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final scale = 1.0 + 0.06 * _pulseController.value;
          return Transform.scale(
            scale: scale,
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
          );
        },
      ),
    );
  }
}

// Новый виджет для прогресс-бара, обновляющийся только через StreamBuilder
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
            _formatTime(duration),
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
}