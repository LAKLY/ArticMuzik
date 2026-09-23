import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../theme/artic_theme.dart';
import '../services/audio_handler.dart';
import '../services/yandex/yandex_audio_provider.dart';
import '../utils/color_utils.dart';
import 'queue_sheet.dart';

class FullPlayerPage extends StatefulWidget {
  final Color initialDominantColor;
  const FullPlayerPage({super.key, required this.initialDominantColor});

  @override
  State<FullPlayerPage> createState() => _FullPlayerPageState();
}

class _FullPlayerPageState extends State<FullPlayerPage>
    with TickerProviderStateMixin {
  late AppAudioHandler audioHandler;
  late YandexAudioProvider yandexProvider;
  late AnimationController _gridController;
  late AnimationController _glitchController;

  MediaItem? _currentMediaItem;
  Color _dominantColor = ArticTheme.accent;
  CancelToken? _colorCancelToken;

  StreamSubscription<MediaItem?>? _mediaItemSubscription;
  StreamSubscription<PlaybackState>? _playbackStateSubscription;

  LoopMode _loopMode = LoopMode.off;
  bool _isShuffle = false;
  bool _showLyrics = false;
  String? _lyrics;
  bool _isLiked = false;
  bool _isPlaying = false;
  bool _flashVisible = false;
  bool _isDisposed = false;

  Timer? _sleepTimer;
  DateTime? _sleepUntil;

  @override
  void initState() {
    super.initState();

    _gridController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();

    _glitchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _dominantColor = widget.initialDominantColor;

    audioHandler = Provider.of<AppAudioHandler>(context, listen: false);
    yandexProvider = Provider.of<YandexAudioProvider>(context, listen: false);
    _currentMediaItem = audioHandler.mediaItem.value;

    _loadLikeStatusAsync();
    _loadLoopMode();
    _isShuffle = audioHandler.shuffleEnabled;

    _mediaItemSubscription = audioHandler.mediaItem.listen((mediaItem) {
      if (_isDisposed || mediaItem == null) return;
      if (_currentMediaItem?.id != mediaItem.id) {
        if (mounted) {
          setState(() {
            _currentMediaItem = mediaItem;
            _showLyrics = false;
            _lyrics = null;
          });
          _showGlitch();
          _refreshDominantColor(mediaItem.artUri.toString());
        }
        _loadLikeStatusAsync();
      }
    });

    _playbackStateSubscription = audioHandler.playbackState.listen((state) {
      if (!_isDisposed && mounted) {
        setState(() => _isPlaying = state.playing);
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _mediaItemSubscription?.cancel();
    _playbackStateSubscription?.cancel();
    _gridController.dispose();
    _glitchController.dispose();
    _colorCancelToken?.cancel();
    _sleepTimer?.cancel();
    super.dispose();
  }

  void _showGlitch() {
    if (_isDisposed) return;
    _glitchController.forward(from: 0.0);
    setState(() => _flashVisible = true);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!_isDisposed && mounted) {
        setState(() => _flashVisible = false);
      }
    });
  }

  void _loadLikeStatusAsync() async {
    final trackId = _currentMediaItem?.extras?['trackId'] as String?;
    if (trackId == null || _isDisposed) return;
    try {
      final isFav = await yandexProvider.isTrackFavorite(trackId);
      if (!_isDisposed && mounted) {
        setState(() => _isLiked = isFav);
      }
    } catch (e) {
      debugPrint('Error loading like status: $e');
    }
  }

  void _loadLoopMode() {
    if (_isDisposed) return;
    _loopMode = audioHandler.getLoopMode();
    if (mounted) setState(() {});
  }

  void _toggleLoopMode() {
    if (_isDisposed) return;
    setState(() {
      switch (_loopMode) {
        case LoopMode.off:
          _loopMode = LoopMode.one;
          break;
        case LoopMode.one:
          _loopMode = LoopMode.all;
          break;
        case LoopMode.all:
          _loopMode = LoopMode.off;
          break;
      }
    });
    audioHandler.setLoopMode(_loopMode);
  }

  void _toggleShuffle() async {
    if (_isDisposed) return;
    final newValue = !audioHandler.shuffleEnabled;
    await audioHandler.setShuffleEnabled(newValue);
    if (!_isDisposed && mounted) {
      setState(() => _isShuffle = newValue);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newValue ? 'Перемешивание включено' : 'Перемешивание выключено'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  // ---------- SLEEP TIMER ----------

  void _showSleepTimerMenu() {
    final active = _sleepTimer != null;
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
                active ? 'Таймер сна активен' : 'Таймер сна',
                style: TextStyle(
                  color: ArticTheme.primary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (active)
              ListTile(
                leading: Icon(Icons.timer_off,
                    color: ArticTheme.accent, size: 22),
                title: Text('Выключить таймер',
                    style: TextStyle(color: ArticTheme.primary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _cancelSleepTimer();
                },
              ),
            _sleepTile(ctx, '15 минут', 15),
            _sleepTile(ctx, '30 минут', 30),
            _sleepTile(ctx, '60 минут', 60),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sleepTile(BuildContext ctx, String label, int minutes) {
    return ListTile(
      leading: Icon(Icons.bedtime_outlined,
          color: ArticTheme.accent, size: 22),
      title: Text(label, style: TextStyle(color: ArticTheme.primary)),
      onTap: () {
        Navigator.pop(ctx);
        _setSleepTimer(minutes);
      },
    );
  }

  void _setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _sleepUntil = DateTime.now().add(Duration(minutes: minutes));
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      audioHandler.pause();
      if (mounted) {
        setState(() {
          _sleepTimer = null;
          _sleepUntil = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Таймер сна: воспроизведение остановлено')),
        );
      }
    });
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Таймер сна: $minutes мин'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepUntil = null;
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Таймер сна выключен')),
      );
    }
  }

  // ---------- LIKE / LYRICS / COLOR ----------

  void _toggleLike() async {
    if (_isDisposed) return;
    final trackId = _currentMediaItem?.extras?['trackId'] as String?;
    if (trackId == null) return;
    bool success;
    if (_isLiked) {
      success = await yandexProvider.unlikeTrack(trackId);
      if (success && !_isDisposed && mounted) {
        setState(() => _isLiked = false);
      }
    } else {
      success = await yandexProvider.likeTrack(trackId);
      if (success && !_isDisposed && mounted) {
        setState(() => _isLiked = true);
      }
    }
    if (success && !_isDisposed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isLiked
              ? 'Добавлено в избранное'
              : 'Удалено из избранного'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _fetchLyrics() async {
    if (_isDisposed) return;
    final trackId = _currentMediaItem?.extras?['trackId'] as String?;
    if (trackId == null) return;
    try {
      final lyrics = await yandexProvider.getLyrics(trackId);
      if (!_isDisposed && mounted) {
        setState(() {
          _lyrics = lyrics;
          _showLyrics = true;
        });
      }
    } catch (e) {
      if (!_isDisposed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки текста: $e')),
        );
      }
    }
  }

  Future<void> _refreshDominantColor(String coverUrl) async {
    if (_isDisposed) return;
    _colorCancelToken?.cancel();
    _colorCancelToken = CancelToken();
    final color = await ColorUtils.extractDominantColor(
      coverUrl,
      fallback: ArticTheme.accent,
      cancelToken: _colorCancelToken,
    );
    if (!_isDisposed && mounted && _colorCancelToken?.isCancelled == false) {
      setState(() => _dominantColor = color);
    }
  }

  IconData _loopIcon() {
    switch (_loopMode) {
      case LoopMode.off:
        return Icons.repeat;
      case LoopMode.one:
        return Icons.repeat_one;
      case LoopMode.all:
        return Icons.repeat;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentMediaItem == null) {
      return Scaffold(
        backgroundColor: ArticTheme.backgroundDeep,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final title = _currentMediaItem!.title;
    final artist = _currentMediaItem!.artist ?? '';
    final coverUrl = _currentMediaItem!.artUri?.toString() ?? '';
    final trackId = _currentMediaItem!.extras?['trackId'] as String? ?? '';

    return Scaffold(
      backgroundColor: ArticTheme.backgroundDeep,
      appBar: _buildGlitchAppBar(),
      body: SafeArea(
        child: Stack(
          children: [
            _AnimatedGrid(controller: _gridController),
            _DynamicGradient(dominantColor: _dominantColor),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: (_showLyrics && _lyrics != null && _lyrics!.isNotEmpty)
                  ? _LyricsView(
                      key: ValueKey('lyrics_$trackId'),
                      lyrics: _lyrics!,
                      title: title,
                      onBack: () => setState(() => _showLyrics = false),
                    )
                  : _PlayerContent(
                      key: ValueKey('player_$trackId'),
                      title: title,
                      artist: artist,
                      coverUrl: coverUrl,
                      isPlaying: _isPlaying,
                      onSeek: (val) =>
                          audioHandler.seek(Duration(seconds: val.toInt())),
                      onPlayPause: audioHandler.playOrPause,
                      onPrevious: audioHandler.skipToPrevious,
                      onNext: audioHandler.skipToNext,
                      onToggleLike: _toggleLike,
                      isLiked: _isLiked,
                      onToggleLoop: _toggleLoopMode,
                      loopMode: _loopMode,
                      onFetchLyrics: _fetchLyrics,
                      glitchController: _glitchController,
                    ),
            ),
            IgnorePointer(
              ignoring: !_flashVisible,
              child: AnimatedOpacity(
                opacity: _flashVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: Container(color: Colors.black.withValues(alpha: 0.5)),
              ),
            )
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildGlitchAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.keyboard_arrow_down, color: ArticTheme.primary),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        _NeonIconButton(
          icon: _isLiked ? Icons.favorite : Icons.favorite_border,
          color: ArticTheme.accent,
          onPressed: _toggleLike,
        ),
        _NeonIconButton(
          icon: _isShuffle ? Icons.shuffle_on : Icons.shuffle,
          color: _isShuffle ? ArticTheme.accent : ArticTheme.primary,
          onPressed: _toggleShuffle,
        ),
        _NeonIconButton(
          icon: _loopIcon(),
          color: ArticTheme.primary,
          onPressed: _toggleLoopMode,
        ),
        _NeonIconButton(
          icon: Icons.bedtime_outlined,
          color: _sleepTimer != null ? ArticTheme.accent : ArticTheme.primary,
          onPressed: _showSleepTimerMenu,
        ),
        _NeonIconButton(
          icon: Icons.queue_music,
          color: ArticTheme.primary,
          onPressed: () => QueueSheet.show(context),
        ),
        _NeonIconButton(
          icon: Icons.lyrics,
          color: ArticTheme.primary,
          onPressed: _fetchLyrics,
        ),
      ],
    );
  }
}

// ============ WIDGETS ============
// (все виджеты ниже — без изменений; _AnimatedGrid, _DynamicGradient,
//  _PlayerContent, _MonospaceText, _GlitchCover, _NeonCoverImage,
//  _SpectrumAnalyzer, _TerminalSliderWithStream, _TerminalSlider,
//  _ControlButtons, _GeometricButton, _TerminalInfo, _TerminalBadge,
//  _LyricsView, _NeonIconButton)

class _AnimatedGrid extends StatelessWidget {
  final AnimationController controller;
  const _AnimatedGrid({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final shift = controller.value * 50;
        return CustomPaint(
          painter: _GridPainter(shift: shift),
          size: Size.infinite,
        );
      },
    );
  }
}

class _GridPainter extends CustomPainter {
  final double shift;
  _GridPainter({required this.shift});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ArticTheme.accent.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;
    const spacing = 40.0;
    final startX = shift % spacing;
    for (double x = startX; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    final startY = (shift * 0.5) % spacing;
    for (double y = startY; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.shift != shift;
}

class _DynamicGradient extends StatelessWidget {
  final Color dominantColor;
  const _DynamicGradient({required this.dominantColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.9,
          colors: [
            dominantColor.withValues(alpha: 0.1),
            Colors.transparent,
            ArticTheme.backgroundDeep.withValues(alpha: 0.95),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

class _PlayerContent extends StatelessWidget {
  final String title;
  final String artist;
  final String coverUrl;
  final bool isPlaying;
  final Function(double) onSeek;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleLike;
  final bool isLiked;
  final VoidCallback onToggleLoop;
  final LoopMode loopMode;
  final VoidCallback onFetchLyrics;
  final AnimationController glitchController;

  const _PlayerContent({
    super.key,
    required this.title,
    required this.artist,
    required this.coverUrl,
    required this.isPlaying,
    required this.onSeek,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleLike,
    required this.isLiked,
    required this.onToggleLoop,
    required this.loopMode,
    required this.onFetchLyrics,
    required this.glitchController,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform.translate(
              offset: const Offset(0, -15),
              child: _GlitchCover(
                coverUrl: coverUrl,
                isPlaying: isPlaying,
                glitchController: glitchController,
              ),
            ),
            const SizedBox(height: 12),
            _MonospaceText(title: title, artist: artist, isPlaying: isPlaying),
            const SizedBox(height: 8),
            _SpectrumAnalyzer(isActive: isPlaying),
            const SizedBox(height: 8),
            _TerminalSliderWithStream(onSeek: onSeek),
            const SizedBox(height: 12),
            _ControlButtons(
              isPlaying: isPlaying,
              onPlayPause: onPlayPause,
              onPrevious: onPrevious,
              onNext: onNext,
            ),
            const SizedBox(height: 12),
            _TerminalInfo(),
          ],
        ),
      ),
    );
  }
}

class _MonospaceText extends StatelessWidget {
  final String title;
  final String artist;
  final bool isPlaying;
  const _MonospaceText({
    required this.title,
    required this.artist,
    required this.isPlaying,
  });

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  @override
  Widget build(BuildContext context) {
    final truncatedTitle = _truncate(title, 30);
    final truncatedArtist = _truncate(artist, 20);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: Column(
        key: ValueKey('${truncatedTitle}_$truncatedArtist'),
        children: [
          Animate(
            effects: const [
              FadeEffect(duration: Duration(milliseconds: 300)),
              ScaleEffect(
                  begin: Offset(0.98, 0.98),
                  end: Offset(1, 1),
                  curve: Curves.easeOut)
            ],
            child: Text(
              truncatedTitle.toUpperCase(),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                fontFamily: 'StieglitzSP',
                letterSpacing: 1.2,
              ).copyWith(color: ArticTheme.primary),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            truncatedArtist,
            style: TextStyle(
              fontSize: 72,
              fontFamily: 'GhastlyPanic',
              color: ArticTheme.secondary,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlitchCover extends StatelessWidget {
  final String coverUrl;
  final bool isPlaying;
  final AnimationController glitchController;
  const _GlitchCover({
    required this.coverUrl,
    required this.isPlaying,
    required this.glitchController,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: glitchController,
      builder: (context, _) {
        final glitchOffset = glitchController.value * 6.0;
        return Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (glitchController.isAnimating)
                Positioned(
                  left: glitchOffset,
                  child: _NeonCoverImage(
                    coverUrl: coverUrl,
                    opacity: 0.4,
                    colorFilter:
                        const ColorFilter.mode(Colors.red, BlendMode.modulate),
                    isPlaying: isPlaying,
                  ),
                ),
              _NeonCoverImage(
                coverUrl: coverUrl,
                opacity: 1.0,
                colorFilter: null,
                isPlaying: isPlaying,
              ),
              if (glitchController.isAnimating)
                Positioned(
                  left: -glitchOffset,
                  child: _NeonCoverImage(
                    coverUrl: coverUrl,
                    opacity: 0.4,
                    colorFilter: const ColorFilter.mode(
                        Colors.blue, BlendMode.modulate),
                    isPlaying: isPlaying,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _NeonCoverImage extends StatelessWidget {
  final String coverUrl;
  final double opacity;
  final ColorFilter? colorFilter;
  final bool isPlaying;

  const _NeonCoverImage({
    required this.coverUrl,
    required this.opacity,
    this.colorFilter,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: ArticTheme.accent.withValues(alpha: 0.6),
            blurRadius: 24,
            spreadRadius: 4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: coverUrl,
              fit: BoxFit.cover,
              color: colorFilter != null ? Colors.white : null,
              colorBlendMode: colorFilter != null ? BlendMode.modulate : null,
            ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: ArticTheme.accent, width: 1.5),
              ),
            ),
            if (isPlaying)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: RadialGradient(
                    colors: [
                      Colors.transparent,
                      ArticTheme.accent.withValues(alpha: 0.3)
                    ],
                    radius: 0.8,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SpectrumAnalyzer extends StatefulWidget {
  final bool isActive;
  const _SpectrumAnalyzer({required this.isActive});

  @override
  State<_SpectrumAnalyzer> createState() => __SpectrumAnalyzerState();
}

class __SpectrumAnalyzerState extends State<_SpectrumAnalyzer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<double> _bars = List.filled(12, 0.2);
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_updateBars);
    if (widget.isActive) _controller.repeat();
  }

  void _updateBars() {
    if (!widget.isActive) return;
    for (int i = 0; i < _bars.length; i++) {
      final target = 0.2 + _random.nextDouble() * 0.8;
      _bars[i] = _bars[i] * 0.7 + target * 0.3;
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant _SpectrumAnalyzer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
      for (int i = 0; i < _bars.length; i++) {
        _bars[i] = 0.05;
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_bars.length, (i) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 4,
            height: _bars[i] * 30,
            decoration: BoxDecoration(
              color: ArticTheme.accent.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _TerminalSliderWithStream extends StatelessWidget {
  final Function(double) onSeek;

  const _TerminalSliderWithStream({required this.onSeek});

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
            return _TerminalSlider(
              currentPosition: position,
              duration: duration,
              onSeek: onSeek,
            );
          },
        );
      },
    );
  }
}

class _TerminalSlider extends StatelessWidget {
  final Duration currentPosition;
  final Duration duration;
  final Function(double) onSeek;

  const _TerminalSlider({
    required this.currentPosition,
    required this.duration,
    required this.onSeek,
  });

  String _formatTime(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final maxVal = duration.inSeconds.toDouble();
    final safeMax = maxVal > 0 ? maxVal : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: ArticTheme.accent,
              inactiveTrackColor: ArticTheme.secondary.withValues(alpha: 0.3),
              thumbColor: ArticTheme.primary,
            ),
            child: Slider(
              value: currentPosition.inSeconds
                  .toDouble()
                  .clamp(0.0, safeMax > 0 ? safeMax : 1.0),
              min: 0,
              max: safeMax > 0 ? safeMax : 1.0,
              onChanged: (val) => onSeek(val),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatTime(currentPosition),
                  style: const TextStyle(
                          fontFamily: 'StieglitzSP', fontSize: 12)
                      .copyWith(color: ArticTheme.secondary),
                ),
                Text(
                  _formatTime(duration),
                  style: const TextStyle(
                          fontFamily: 'StieglitzSP', fontSize: 12)
                      .copyWith(color: ArticTheme.secondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlButtons extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  const _ControlButtons({
    required this.isPlaying,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _GeometricButton(
          icon: Icons.skip_previous,
          onTap: onPrevious,
          size: 48,
        ),
        const SizedBox(width: 40),
        _GeometricButton(
          icon: isPlaying ? Icons.pause : Icons.play_arrow,
          onTap: onPlayPause,
          size: 72,
          isPrimary: true,
        ),
        const SizedBox(width: 40),
        _GeometricButton(
          icon: Icons.skip_next,
          onTap: onNext,
          size: 48,
        ),
      ],
    );
  }
}

class _GeometricButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool isPrimary;
  const _GeometricButton({
    required this.icon,
    required this.onTap,
    required this.size,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.0, end: 1.0),
        duration: const Duration(milliseconds: 120),
        curve: Curves.elasticOut,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isPrimary ? ArticTheme.accent : Colors.transparent,
            border: isPrimary
                ? null
                : Border.all(color: ArticTheme.accent, width: 1.5),
            boxShadow: isPrimary ? ArticTheme.glow() : null,
          ),
          child: Icon(icon, color: ArticTheme.primary, size: size * 0.5),
        ),
      ),
    );
  }
}

class _TerminalInfo extends StatelessWidget {
  const _TerminalInfo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: ArticTheme.backgroundDarkest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ArticTheme.secondary.withValues(alpha: 0.3)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _TerminalBadge(label: "STATUS", value: "PLAYING"),
          _TerminalBadge(label: "QUALITY", value: "HQ"),
          _TerminalBadge(label: "SOURCE", value: "Yandex Music"),
        ],
      ),
    );
  }
}

class _TerminalBadge extends StatelessWidget {
  final String label;
  final String value;
  const _TerminalBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontFamily: 'StieglitzSP', fontSize: 9)
              .copyWith(color: ArticTheme.secondary),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'StieglitzSP',
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ).copyWith(color: ArticTheme.primary),
        ),
      ],
    );
  }
}

class _LyricsView extends StatelessWidget {
  final String lyrics;
  final String title;
  final VoidCallback onBack;
  const _LyricsView({
    super.key,
    required this.lyrics,
    required this.title,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ArticTheme.backgroundDeep, ArticTheme.backgroundDarkest],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                      fontFamily: 'StieglitzSP', fontSize: 18)
                  .copyWith(color: ArticTheme.primary),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Text(
                  lyrics,
                  style: const TextStyle(
                    fontFamily: 'StieglitzSP',
                    fontSize: 14,
                    height: 1.6,
                  ).copyWith(color: ArticTheme.secondary),
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.arrow_downward, color: ArticTheme.accent),
              onPressed: onBack,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _NeonIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  const _NeonIconButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.0, end: 1.0),
      duration: const Duration(milliseconds: 150),
      curve: Curves.elasticOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: IconButton(
        icon: Icon(icon, color: color),
        onPressed: onPressed,
        splashRadius: 22,
      ),
    );
  }
}