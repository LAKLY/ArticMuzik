part of 'main_screen.dart';

class _MiniPlayerHost extends StatefulWidget {
  const _MiniPlayerHost();

  @override
  State<_MiniPlayerHost> createState() => _MiniPlayerHostState();
}

class _MiniPlayerHostState extends State<_MiniPlayerHost> {
  AppAudioHandler? _handler;
  StreamSubscription<MediaItem?>? _mediaSub;
  StreamSubscription<PlaybackState>? _playbackSub;

  MediaItem? _item;
  bool _isPlaying = false;
  bool _isLoading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final handler = Provider.of<AppAudioHandler>(context, listen: false);
    if (_handler == handler && _mediaSub != null) return;
    _handler = handler;

    _mediaSub?.cancel();
    _playbackSub?.cancel();

    _item = handler.mediaItem.value;
    _applyPlayback(handler.playbackState.value);

    _mediaSub = handler.mediaItem.listen((item) {
      if (!mounted) return;
      setState(() => _item = item);
    });
    _playbackSub = handler.playbackState.listen((ps) {
      if (!mounted) return;
      _applyPlayback(ps);
    });
  }

  void _applyPlayback(PlaybackState? ps) {
    final isPlaying = ps?.playing ?? false;
    final isLoading =
        ps?.processingState == AudioProcessingState.loading ||
            ps?.processingState == AudioProcessingState.buffering;
    if (isPlaying != _isPlaying || isLoading != _isLoading) {
      setState(() {
        _isPlaying = isPlaying;
        _isLoading = isLoading;
      });
    }
  }

  @override
  void dispose() {
    _mediaSub?.cancel();
    _playbackSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handler = _handler;
    final item = _item;
    if (handler == null || item == null) return const SizedBox.shrink();

    return _MiniPlayer(
      item: item,
      isPlaying: _isPlaying,
      isLoading: _isLoading,
      onTap: () => _openFullPlayer(context),
      onLongPress: () => _showOptions(context, handler),
      onPlayPause: handler.playOrPause,
      onNext: handler.skipToNext,
      onPrevious: handler.skipToPrevious,
    );
  }

  void _openFullPlayer(BuildContext context) {
    final mainState = context.findAncestorStateOfType<_MainScreenState>();
    mainState?._openFullPlayer();
  }

  void _showOptions(BuildContext context, AppAudioHandler handler) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ArticTheme.backgroundDarkest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Мини-плеер',
                style: TextStyle(
                  color: ArticTheme.primary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.queue_music,
                  color: ArticTheme.accent, size: 22),
              title: Text('Открыть очередь',
                  style: TextStyle(color: ArticTheme.primary)),
              onTap: () {
                Navigator.pop(ctx);
                QueueSheet.show(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.play_arrow,
                  color: ArticTheme.accent, size: 22),
              title: Text('Открыть полный плеер',
                  style: TextStyle(color: ArticTheme.primary)),
              onTap: () {
                Navigator.pop(ctx);
                _openFullPlayer(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.clear_all,
                  color: Colors.redAccent, size: 22),
              title: Text('Очистить очередь',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(ctx);
                await handler.clearQueue();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Очередь очищена')),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _MiniPlayer extends StatefulWidget {
  final MediaItem item;
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Future<void> Function() onPlayPause;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;

  const _MiniPlayer({
    required this.item,
    required this.isPlaying,
    required this.isLoading,
    required this.onTap,
    required this.onLongPress,
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

  static const double _coverSize = 46.0;
  static const double _buttonSize = 36.0;
  static const double _barHeight = 4.0;
  static const double _cornerRadius = 14.0;
  static const double _buttonInset = 6.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
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
    final rightReserved = _buttonSize + _buttonInset + 4;

    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onHorizontalDragEnd: _onHorizontalDrag,
      child: Container(
        decoration: BoxDecoration(
          gradient: ArticTheme.surfaceGradient,
          borderRadius: BorderRadius.circular(_cornerRadius),
          border: Border(
            top: BorderSide(
              color: ArticTheme.accent.withValues(alpha: 0.35),
              width: 0.6,
            ),
            left: BorderSide(
              color: ArticTheme.accent.withValues(alpha: 0.35),
              width: 0.6,
            ),
            right: BorderSide(
              color: ArticTheme.accent.withValues(alpha: 0.35),
              width: 0.6,
            ),
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_cornerRadius),
            child: InkWell(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      8,
                      8,
                      8,
                      14 + _barHeight,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildCover(),
                        const SizedBox(width: 12),
                        Expanded(child: _buildTrackText()),
                        SizedBox(width: rightReserved),
                      ],
                    ),
                  ),
                  Positioned(
                    top: _buttonInset,
                    right: _buttonInset,
                    child: _buildPlayButton(),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: _barHeight + 2,
                    child: const _MiniPlayerTimeLabels(),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: _barHeight,
                    child: const _MiniPlayerProgressLine(),
                  ),
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
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: ArticTheme.accent.withValues(alpha: 0.22),
            blurRadius: 6,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: cover.isEmpty
            ? _placeholderCover()
            : CachedNetworkImage(
                imageUrl: cover,
                width: _coverSize,
                height: _coverSize,
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
      width: _coverSize,
      height: _coverSize,
      color: Colors.white10,
      child: const Icon(Icons.music_note, color: Colors.white38, size: 22),
    );
  }

  Widget _buildTrackText() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
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
        key: ValueKey('mini_${widget.item.id}'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            widget.item.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ArticTheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: 15,
              letterSpacing: 0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          Text(
            widget.item.artist ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ArticTheme.secondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildPlayButton() {
    return SizedBox(
      width: _buttonSize,
      height: _buttonSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final scale = 1.0 + 0.20 * _pulseController.value;
                return Transform.scale(
                  scale: widget.isPlaying ? scale : 1.0,
                  child: Container(
                    width: _buttonSize,
                    height: _buttonSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ArticTheme.accent.withValues(
                          alpha: 0.35 * _pulseController.value,
                        ),
                        width: 1.0,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            width: _buttonSize,
            height: _buttonSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.transparent,
              border: Border.all(
                color: ArticTheme.accent.withValues(alpha: 0.85),
                width: 1.3,
              ),
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
                  size: 19,
                ),
              ),
            ),
          ),
          if (widget.isLoading)
            IgnorePointer(
              child: Container(
                width: _buttonSize,
                height: _buttonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ArticTheme.backgroundDeep.withValues(alpha: 0.6),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white70),
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

class _MiniPlayerProgressLine extends StatelessWidget {
  const _MiniPlayerProgressLine();

  @override
  Widget build(BuildContext context) {
    final handler = Provider.of<AppAudioHandler>(context, listen: false);
    return StreamBuilder<Duration>(
      stream: handler.positionStream,
      builder: (context, posSnap) {
        final position = posSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: handler.durationStream,
          builder: (context, durSnap) {
            final duration = durSnap.data ?? Duration.zero;
            final progress = duration.inMilliseconds > 0
                ? (position.inMilliseconds / duration.inMilliseconds)
                    .clamp(0.0, 1.0)
                : 0.0;
            return CustomPaint(
              painter: _CenterProgressPainter(
                progress: progress,
                background: ArticTheme.secondary.withValues(alpha: 0.20),
                fill: ArticTheme.accent,
                glow: ArticTheme.accent.withValues(alpha: 0.55),
              ),
              size: Size.infinite,
            );
          },
        );
      },
    );
  }
}

class _MiniPlayerTimeLabels extends StatelessWidget {
  const _MiniPlayerTimeLabels();

  static const TextStyle _style = TextStyle(
    fontSize: 9,
    fontFamily: 'StieglitzSP',
    color: Colors.white60,
    letterSpacing: 0.3,
  );

  String _fmt(Duration d) {
    if (d == Duration.zero) return '--:--';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final handler = Provider.of<AppAudioHandler>(context, listen: false);
    return StreamBuilder<Duration>(
      stream: handler.positionStream,
      builder: (context, posSnap) {
        final position = posSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: handler.durationStream,
          builder: (context, durSnap) {
            final duration = durSnap.data ?? Duration.zero;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(position), style: _style),
                Text(_fmt(duration), style: _style),
              ],
            );
          },
        );
      },
    );
  }
}

class _CenterProgressPainter extends CustomPainter {
  final double progress;
  final Color background;
  final Color fill;
  final Color glow;

  _CenterProgressPainter({
    required this.progress,
    required this.background,
    required this.fill,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = background,
    );

    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;

    final centerX = size.width / 2;
    final halfWidth = (size.width / 2) * p;

    final rect = Rect.fromLTWH(
      centerX - halfWidth,
      0,
      halfWidth * 2,
      size.height,
    );

    canvas.drawRect(
      rect,
      Paint()
        ..color = glow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    canvas.drawRect(rect, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(covariant _CenterProgressPainter old) =>
      old.progress != progress ||
      old.fill != fill ||
      old.background != background ||
      old.glow != glow;
}