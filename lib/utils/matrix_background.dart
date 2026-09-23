import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/artic_theme.dart';

class MatrixBackground extends StatefulWidget {
  final double opacity;
  final int numberOfDrops;

  const MatrixBackground({super.key, this.opacity = 0.006, this.numberOfDrops = 15});

  @override
  State<MatrixBackground> createState() => _MatrixBackgroundState();
}

class _MatrixBackgroundState extends State<MatrixBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_MatrixTelemetryDrop> _drops = [];
  final Random _random = Random();
  double _lastValue = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 15))..repeat();
    _initDrops();
    _lastValue = _controller.value;
  }

  void _initDrops() {
    for (int i = 0; i < widget.numberOfDrops; i++) {
      _drops.add(_MatrixTelemetryDrop(x: _random.nextDouble(), y: _random.nextDouble(), speed: 2.0 + _random.nextDouble() * 0.6));
    } 
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final double delta = (_controller.value - _lastValue + 1.0) % 1.0;
        _lastValue = _controller.value;

        for (var drop in _drops) {
          drop.y = (drop.y + drop.speed * delta) % 1.0;
        }

        return Stack(
          children: [
            // Слой 1: Статический (сетка, виньетка, сканлайны)
            RepaintBoundary(
              child: CustomPaint(painter: _StaticBackgroundPainter(), size: Size.infinite),
            ),
            // Слой 2: Динамический (только текст)
            RepaintBoundary(
              child: CustomPaint(painter: _DynamicTelemetryPainter(_drops, widget.opacity), size: Size.infinite),
            ),
          ],
        );
      },
    );
  }
}

// 1. Статический Painter (Рисуется один раз)
class _StaticBackgroundPainter extends CustomPainter {
  final Paint _dotPaint = Paint()..color = ArticTheme.intrigue.withValues(alpha: 0.04);
  final Paint _scanlinePaint = Paint()..color = Colors.black.withValues(alpha: 0.1)..strokeWidth = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Сетка
    for (double x = 0; x < size.width; x += 32.0) {
      for (double y = 0; y < size.height; y += 32.0) {
        canvas.drawCircle(Offset(x, y), 0.8, _dotPaint);
      }
    }
    // Scanlines
    for (double y = 0; y < size.height; y += 6.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), _scanlinePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false; // Никогда не перерисовывать
}

// 2. Динамический Painter (Рисует только текст)
class _DynamicTelemetryPainter extends CustomPainter {
  final List<_MatrixTelemetryDrop> drops;
  final double opacity;
  final TextPainter _tp = TextPainter(textDirection: TextDirection.ltr);
  
  // Кэшированные стили
  final TextStyle baseStyle = const TextStyle(fontSize: 10, fontFamily: 'GhastlyPanic', fontWeight: FontWeight.w600);

  _DynamicTelemetryPainter(this.drops, this.opacity);

  @override
  void paint(Canvas canvas, Size size) {
    for (final drop in drops) {
      final double posX = (drop.x * size.width / 32.0).floor() * 32.0;
      final double posY = drop.y * size.height;
      
      _drawChromaticText(canvas, drop.text, posX, posY, drop.isAccent);
    }
  }

  void _drawChromaticText(Canvas canvas, String text, double x, double y, bool isAccent) {
    final color = (isAccent ? ArticTheme.burntCrimson : ArticTheme.babyBarnOwl).withValues(alpha: opacity);
    
    // Переиспользуем TextPainter
    _tp.text = TextSpan(text: text, style: baseStyle.copyWith(color: color));
    _tp.layout();
    
    // Хроматическая аберрация (смещение каналов)
    _tp.paint(canvas, Offset(x + 1, y)); // Red
    _tp.paint(canvas, Offset(x, y));     // Green
    _tp.paint(canvas, Offset(x - 1, y)); // Blue
  }

  @override
  bool shouldRepaint(covariant _DynamicTelemetryPainter oldDelegate) => true;
}

class _MatrixTelemetryDrop {
  double x, y, speed;
  String text = "DATA_STREAM"; // Для примера
  bool isAccent = false;
  _MatrixTelemetryDrop({required this.x, required this.y, required this.speed});
}