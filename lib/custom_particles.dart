import 'dart:math';
import 'package:flutter/material.dart';

class Particle {
  double x;
  double y;
  double vx;
  double vy;
  Color color;
  double size;
  double opacity;
  double rotation;
  double rotationSpeed;
  double gravity;

  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.size,
    this.opacity = 1.0,
    required this.rotation,
    required this.rotationSpeed,
    this.gravity = 0.15,
  });

  void update() {
    vy += gravity;
    x += vx;
    y += vy;
    rotation += rotationSpeed;
    // Slow decay
    if (opacity > 0.01) {
      opacity -= 0.005;
    } else {
      opacity = 0.0;
    }
  }
}

class Firework {
  double x;
  double y;
  double targetY;
  double vy;
  Color color;
  bool exploded = false;
  List<Particle> particles = [];
  final Random _rand = Random();

  Firework({
    required this.x,
    required this.y,
    required this.targetY,
    required this.color,
  }) : vy = -4 - Random().nextDouble() * 4;

  void update() {
    if (!exploded) {
      y += vy;
      if (y <= targetY) {
        explode();
      }
    } else {
      for (var p in particles) {
        p.update();
      }
      particles.removeWhere((p) => p.opacity <= 0.0);
    }
  }

  void explode() {
    exploded = true;
    final int count = 30 + _rand.nextInt(20);
    for (int i = 0; i < count; i++) {
      final angle = _rand.nextDouble() * 2 * pi;
      final speed = 1.0 + _rand.nextDouble() * 4.0;
      particles.add(Particle(
        x: x,
        y: y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        color: color,
        size: 3.0 + _rand.nextDouble() * 3.0,
        rotation: _rand.nextDouble() * 2 * pi,
        rotationSpeed: (_rand.nextDouble() - 0.5) * 0.2,
        gravity: 0.08,
      ));
    }
  }
}

class ConfettiParticle {
  double x;
  double y;
  double vx;
  double vy;
  double width;
  double height;
  double rotationX;
  double rotationY;
  double rotationSpeedX;
  double rotationSpeedY;
  Color color;

  ConfettiParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.width,
    required this.height,
    required this.rotationX,
    required this.rotationY,
    required this.rotationSpeedX,
    required this.rotationSpeedY,
    required this.color,
  });

  void update(Size size) {
    x += vx;
    y += vy;
    // Add simple swaying wind
    vx += sin(y * 0.05) * 0.02;
    rotationX += rotationSpeedX;
    rotationY += rotationSpeedY;

    // Reset if offscreen
    if (y > size.height) {
      y = -20;
      x = Random().nextDouble() * size.width;
      vy = 2.0 + Random().nextDouble() * 3.0;
    }
  }
}

class CelebrationPainter extends CustomPainter {
  final List<Firework> fireworks;
  final List<ConfettiParticle> confetti;

  CelebrationPainter({required this.fireworks, required this.confetti});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Fireworks
    for (var f in fireworks) {
      if (!f.exploded) {
        final paint = Paint()
          ..color = f.color.withOpacity(0.8)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(f.x, f.y), 4.0, paint);
      } else {
        for (var p in f.particles) {
          final paint = Paint()
            ..color = p.color.withOpacity(p.opacity)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(Offset(p.x, p.y), p.size, paint);
        }
      }
    }

    // 2. Draw Confetti
    for (var c in confetti) {
      final paint = Paint()
        ..color = c.color
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(c.x, c.y);
      canvas.rotate(c.rotationX);
      
      // Mimic 3D flip using scale
      final scaleX = sin(c.rotationY);
      canvas.scale(scaleX.abs(), 1.0);

      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: c.width, height: c.height),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CelebrationPainter oldDelegate) => true;
}

class CelebrationEffect extends StatefulWidget {
  const CelebrationEffect({super.key});

  @override
  State<CelebrationEffect> createState() => _CelebrationEffectState();
}

class _CelebrationEffectState extends State<CelebrationEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  final List<Firework> _fireworks = [];
  final List<ConfettiParticle> _confetti = [];
  final Random _rand = Random();
  
  // Theme colors matching DAoC Realms (Albion Red, Midgard Blue, Hibernia Green, Golden Norse)
  final List<Color> _colors = const [
    Color(0xFFFFD700), // Gold
    Color(0xFFE5C158), // Amber/Bronze
    Color(0xFFD32F2F), // Albion Red
    Color(0xFF1976D2), // Midgard Blue
    Color(0xFF388E3C), // Hibernia Green
    Color(0xFF8E24AA), // Magic Purple
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_updateSystem);

    _animController.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize confetti particles based on screen size
    if (_confetti.isEmpty) {
      final size = MediaQuery.of(context).size;
      for (int i = 0; i < 80; i++) {
        _confetti.add(ConfettiParticle(
          x: _rand.nextDouble() * size.width,
          y: _rand.nextDouble() * size.height - size.height,
          vx: (_rand.nextDouble() - 0.5) * 1.5,
          vy: 2.0 + _rand.nextDouble() * 4.0,
          width: 8.0 + _rand.nextDouble() * 8.0,
          height: 14.0 + _rand.nextDouble() * 10.0,
          rotationX: _rand.nextDouble() * 2 * pi,
          rotationY: _rand.nextDouble() * 2 * pi,
          rotationSpeedX: (_rand.nextDouble() - 0.5) * 0.1,
          rotationSpeedY: (_rand.nextDouble() - 0.5) * 0.15,
          color: _colors[_rand.nextInt(_colors.length)],
        ));
      }
    }
  }

  void _updateSystem() {
    final size = MediaQuery.of(context).size;

    setState(() {
      // 1. Spawning new fireworks occasionally
      if (_fireworks.length < 5 && _rand.nextDouble() < 0.05) {
        _fireworks.add(Firework(
          x: 50 + _rand.nextDouble() * (size.width - 100),
          y: size.height + 20,
          targetY: 50 + _rand.nextDouble() * (size.height * 0.5),
          color: _colors[_rand.nextInt(_colors.length)],
        ));
      }

      // Update active fireworks
      for (var f in _fireworks) {
        f.update();
      }

      // Clean up dead fireworks
      _fireworks.removeWhere((f) => f.exploded && f.particles.isEmpty);

      // Update active confetti
      for (var c in _confetti) {
        c.update(size);
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: CelebrationPainter(
            fireworks: _fireworks,
            confetti: _confetti,
          ),
        ),
      ),
    );
  }
}
