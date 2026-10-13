import 'dart:math' as math;

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

void main() => runApp(const HailMaryApp());

class HailMaryApp extends StatelessWidget {
  const HailMaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hail Mary',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF7A3D),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF05060C),
        useMaterial3: true,
      ),
      home: const AstrophageScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// The model
// ---------------------------------------------------------------------------

/// A simple Astrophage model: the fraction of sunlight the swarm blocks
/// doubles every [doublingMonths] months, starting from [startDimming].
class AstrophageModel {
  const AstrophageModel({
    required this.startDimming,
    required this.doublingMonths,
  });

  /// Fraction of the Sun's light blocked at year 0 (0.0001 = 0.01%).
  final double startDimming;

  /// How many months it takes the swarm to double in size.
  final double doublingMonths;

  static const double earthTempK = 288.0; // average surface temperature today
  static const double iceAgeDropC = 5.0; // roughly the last ice age

  /// How many times bigger the swarm is after [years].
  double growth(double years) =>
      math.pow(2, years * 12 / doublingMonths).toDouble();

  /// Fraction of sunlight blocked after [years], capped at 100%.
  double dimming(double years) =>
      math.min(1.0, startDimming * growth(years));

  /// Earth's average temperature drop in °C. A planet's temperature scales
  /// with the fourth root of the light it receives (Stefan–Boltzmann law).
  double tempDropC(double years) {
    final light = 1 - dimming(years);
    return earthTempK * (1 - math.pow(light, 0.25).toDouble());
  }

  /// Years until the Earth cools by [dropC] degrees, or null if it never does.
  double? yearsUntilDrop(double dropC) {
    final light = math.pow(1 - dropC / earthTempK, 4).toDouble();
    final targetDimming = 1 - light;
    if (targetDimming <= startDimming) return 0.0;
    final doublings = math.log(targetDimming / startDimming) / math.ln2;
    return doublings * doublingMonths / 12;
  }
}

// ---------------------------------------------------------------------------
// The screen
// ---------------------------------------------------------------------------

class AstrophageScreen extends StatefulWidget {
  const AstrophageScreen({super.key});

  @override
  State<AstrophageScreen> createState() => _AstrophageScreenState();
}

class _AstrophageScreenState extends State<AstrophageScreen>
    with SingleTickerProviderStateMixin {
  static const double maxYears = 30;

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _clock = 0; // seconds, drives the 3D motion

  double _doublingMonths = 12;
  double _startLog = -4; // log10 of the starting dimming fraction
  double _years = 0;
  bool _playing = false;

  double _yaw = 0.6;
  double _pitch = 0.45;
  bool _autoSpin = true;

  final _scene = Scene.generate(seed: 42);

  AstrophageModel get _model => AstrophageModel(
        startDimming: math.pow(10, _startLog).toDouble(),
        doublingMonths: _doublingMonths,
      );

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    setState(() {
      _clock += dt;
      if (_autoSpin) _yaw += dt * 0.12;
      if (_playing) {
        _years += dt * 2.0; // two simulated years per second
        if (_years >= maxYears) {
          _years = maxYears;
          _playing = false;
        }
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      if (!_playing && _years >= maxYears) _years = 0;
      _playing = !_playing;
    });
  }

  @override
  Widget build(BuildContext context) {
    final model = _model;
    final dimming = model.dimming(_years);
    final drop = model.tempDropC(_years);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 11,
              child: GestureDetector(
                onPanStart: (_) => _autoSpin = false,
                onPanUpdate: (d) => setState(() {
                  _yaw += d.delta.dx * 0.008;
                  _pitch = (_pitch + d.delta.dy * 0.008).clamp(-1.4, 1.4);
                }),
                onDoubleTap: () => setState(() => _autoSpin = !_autoSpin),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: OrbitPainter(
                          scene: _scene,
                          clock: _clock,
                          dimming: dimming,
                          tempDropC: drop,
                          yaw: _yaw,
                          pitch: _pitch,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      top: 12,
                      right: 16,
                      child: _Header(years: _years),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 8,
                      child: _Stats(model: model, years: _years),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 9,
              child: _Controls(
                years: _years,
                maxYears: maxYears,
                playing: _playing,
                doublingMonths: _doublingMonths,
                startLog: _startLog,
                model: model,
                onPlay: _togglePlay,
                onYears: (v) => setState(() {
                  _years = v;
                  _playing = false;
                }),
                onDoubling: (v) => setState(() => _doublingMonths = v),
                onStart: (v) => setState(() => _startLog = v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overlay widgets
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.years});
  final double years;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ASTROPHAGE',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                  color: Color(0xFFFFB27A),
                ),
              ),
              Text(
                'Drag to rotate · double-tap to spin',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text('YEAR',
                style: TextStyle(
                    fontSize: 10, letterSpacing: 2, color: Colors.white54)),
            Text(
              years.toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.model, required this.years});
  final AstrophageModel model;
  final double years;

  @override
  Widget build(BuildContext context) {
    final dimming = model.dimming(years);
    final drop = model.tempDropC(years);
    final growth = model.growth(years);

    return Row(
      children: [
        _StatTile(
          label: 'SUNLIGHT',
          value: '${_pct(1 - dimming)}%',
          color: Color.lerp(const Color(0xFFFFE08A), const Color(0xFFB0472A),
              (dimming * 8).clamp(0.0, 1.0))!,
        ),
        _StatTile(
          label: 'EARTH COOLS',
          value: '−${drop.toStringAsFixed(drop < 10 ? 2 : 1)}°C',
          color: drop >= AstrophageModel.iceAgeDropC
              ? const Color(0xFF8FD3FF)
              : Colors.white,
        ),
        _StatTile(
          label: 'SWARM SIZE',
          value: '×${_bigNumber(growth)}',
          color: const Color(0xFFFF8A5B),
        ),
      ],
    );
  }

  static String _pct(double f) {
    final p = f * 100;
    if (p >= 99.995) return '100';
    if (p >= 99) return p.toStringAsFixed(2);
    return p.toStringAsFixed(1);
  }
}

String _bigNumber(double n) {
  if (n < 1000) return n.toStringAsFixed(n < 10 ? 1 : 0);
  if (n < 1e6) return '${(n / 1e3).toStringAsFixed(1)}k';
  if (n < 1e9) return '${(n / 1e6).toStringAsFixed(1)}M';
  if (n < 1e12) return '${(n / 1e9).toStringAsFixed(1)}B';
  final exp = (math.log(n) / math.ln10).floor();
  return '10^$exp';
}

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 9, letterSpacing: 1.5, color: Colors.white54)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.years,
    required this.maxYears,
    required this.playing,
    required this.doublingMonths,
    required this.startLog,
    required this.model,
    required this.onPlay,
    required this.onYears,
    required this.onDoubling,
    required this.onStart,
  });

  final double years;
  final double maxYears;
  final bool playing;
  final double doublingMonths;
  final double startLog;
  final AstrophageModel model;
  final VoidCallback onPlay;
  final ValueChanged<double> onYears;
  final ValueChanged<double> onDoubling;
  final ValueChanged<double> onStart;

  @override
  Widget build(BuildContext context) {
    final drop = model.tempDropC(years);
    final iceAge = model.yearsUntilDrop(AstrophageModel.iceAgeDropC);
    final startPct = model.startDimming * 100;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0F1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Row(
            children: [
              IconButton.filled(
                onPressed: onPlay,
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              ),
              Expanded(
                child: Slider(
                  value: years.clamp(0.0, maxYears),
                  max: maxYears,
                  onChanged: onYears,
                ),
              ),
            ],
          ),
          _Verdict(dropC: drop),
          const SizedBox(height: 12),
          _LabeledSlider(
            label: 'Doubling time',
            valueText: '${doublingMonths.round()} months',
            help: 'How fast the Astrophage swarm doubles.',
            value: doublingMonths,
            min: 1,
            max: 36,
            divisions: 35,
            onChanged: onDoubling,
          ),
          _LabeledSlider(
            label: 'Sunlight blocked at year 0',
            valueText: '${_trim(startPct)}%',
            help: 'How big the infection is when we first notice it.',
            value: startLog,
            min: -6,
            max: -2,
            divisions: 40,
            onChanged: onStart,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F33),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              iceAge == null
                  ? 'This swarm never cools Earth into an ice age.'
                  : 'At this rate, Earth cools 5°C — ice-age territory — '
                      'in ${iceAge.toStringAsFixed(1)} years.',
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'How it works: Astrophage soaks up sunlight, so the Sun looks '
            'dimmer from Earth. The swarm grows exponentially, and a planet\'s '
            'temperature follows the fourth root of the light it gets '
            '(Stefan–Boltzmann). A simple model to play with, not the '
            'book\'s exact numbers.',
            style: TextStyle(fontSize: 12, color: Colors.white54, height: 1.4),
          ),
        ],
      ),
    );
  }

  static String _trim(double v) {
    if (v >= 0.1) return v.toStringAsFixed(2);
    if (v >= 0.001) return v.toStringAsFixed(4);
    return v.toStringAsFixed(5);
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.dropC});
  final double dropC;

  @override
  Widget build(BuildContext context) {
    final String text;
    final Color color;
    if (dropC < 0.5) {
      text = 'Barely measurable. Only astronomers notice.';
      color = const Color(0xFF9BE39B);
    } else if (dropC < 2) {
      text = 'Harvests start failing around the world.';
      color = const Color(0xFFFFE08A);
    } else if (dropC < 5) {
      text = 'Severe climate collapse. Mass famine.';
      color = const Color(0xFFFF9A5B);
    } else {
      text = 'Ice-age conditions. Civilization at risk.';
      color = const Color(0xFF8FD3FF);
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 15, fontWeight: FontWeight.w600)),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.valueText,
    required this.help,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueText;
  final String help;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              Text(valueText,
                  style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFFFFB27A),
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(help,
              style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The 3D scene
// ---------------------------------------------------------------------------

class Vec3 {
  const Vec3(this.x, this.y, this.z);
  final double x, y, z;
}

class SwarmParticle {
  const SwarmParticle({
    required this.radius,
    required this.inclination,
    required this.node,
    required this.phase,
    required this.speed,
    required this.threshold,
    required this.size,
  });

  final double radius; // in Sun radii
  final double inclination;
  final double node;
  final double phase;
  final double speed;
  final double threshold; // appears once the swarm is this big (0..1)
  final double size;

  Vec3 position(double t) {
    final a = phase + speed * t;
    // Circle in the orbital plane.
    var x = radius * math.cos(a);
    var y = 0.0;
    var z = radius * math.sin(a);
    // Tilt the orbit.
    final ci = math.cos(inclination), si = math.sin(inclination);
    final y1 = y * ci - z * si;
    final z1 = y * si + z * ci;
    y = y1;
    z = z1;
    // Spin the tilted orbit around the vertical axis.
    final cn = math.cos(node), sn = math.sin(node);
    final x2 = x * cn + z * sn;
    final z2 = -x * sn + z * cn;
    return Vec3(x2, y, z2);
  }
}

class Scene {
  Scene(this.particles, this.stars);

  final List<SwarmParticle> particles;
  final List<Offset> stars; // normalized 0..1 positions
  static const int count = 1600;

  factory Scene.generate({required int seed}) {
    final rnd = math.Random(seed);
    final particles = List.generate(count, (i) {
      final r = 1.08 + math.pow(rnd.nextDouble(), 2.2).toDouble() * 1.1;
      return SwarmParticle(
        radius: r,
        inclination: (rnd.nextDouble() - 0.5) * math.pi,
        node: rnd.nextDouble() * math.pi * 2,
        phase: rnd.nextDouble() * math.pi * 2,
        speed: (0.35 + rnd.nextDouble() * 0.25) / math.pow(r, 1.5),
        threshold: i / count,
        size: 0.6 + rnd.nextDouble() * 1.3,
      );
    });
    final stars = List.generate(
        180, (_) => Offset(rnd.nextDouble(), rnd.nextDouble()));
    return Scene(particles, stars);
  }
}

class _Projected {
  _Projected(this.offset, this.depth, this.scale);
  final Offset offset;
  final double depth;
  final double scale;
}

class OrbitPainter extends CustomPainter {
  OrbitPainter({
    required this.scene,
    required this.clock,
    required this.dimming,
    required this.tempDropC,
    required this.yaw,
    required this.pitch,
  });

  final Scene scene;
  final double clock;
  final double dimming;
  final double tempDropC;
  final double yaw;
  final double pitch;

  static const double cameraDistance = 11;
  static const double venusOrbit = 3.0;
  static const double earthOrbit = 4.3;

  late Offset _center;
  late double _unit;

  _Projected _project(Vec3 v) {
    final cy = math.cos(yaw), sy = math.sin(yaw);
    final x1 = v.x * cy + v.z * sy;
    final z1 = -v.x * sy + v.z * cy;
    final cp = math.cos(pitch), sp = math.sin(pitch);
    final y2 = v.y * cp - z1 * sp;
    final z2 = v.y * sp + z1 * cp;
    final s = cameraDistance / (cameraDistance + z2);
    return _Projected(
      _center + Offset(x1, y2) * (_unit * s),
      z2,
      s,
    );
  }

  /// How much of the swarm is visible, on a log scale:
  /// 0.001% blocked → a few specks, 10% blocked → the full swarm.
  double get _swarmFraction {
    if (dimming <= 0) return 0;
    final f = (math.log(dimming) / math.ln10 + 5.5) / 4.5;
    return f.clamp(0.02, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _center = size.center(Offset.zero).translate(0, size.height * 0.02);
    _unit = math.min(size.width, size.height) * 0.105;

    _paintStars(canvas, size);

    final frac = _swarmFraction;
    final sunBrightness = 1 - dimming;

    // Planets on the ecliptic.
    final venusAngle = clock * 0.22;
    final earthAngle = clock * 0.14 + 1.8;
    final venus = Vec3(venusOrbit * math.cos(venusAngle), 0,
        venusOrbit * math.sin(venusAngle));
    final earth = Vec3(earthOrbit * math.cos(earthAngle), 0,
        earthOrbit * math.sin(earthAngle));

    _paintOrbitRing(canvas, venusOrbit);
    _paintOrbitRing(canvas, earthOrbit);

    // Collect everything that can be in front of or behind the Sun.
    final back = <void Function()>[];
    final front = <void Function()>[];

    void add(_Projected p, void Function() draw) {
      (p.depth > 0 ? back : front).add(draw);
    }

    // Swarm.
    final swarmPaint = Paint();
    for (final particle in scene.particles) {
      if (particle.threshold > frac) break;
      final p = _project(particle.position(clock));
      final r = particle.size * p.scale * (_unit / 40);
      final glow = (0.35 + 0.65 * p.scale.clamp(0.0, 1.2) / 1.2);
      add(p, () {
        swarmPaint.color = Color.fromRGBO(
            255, 90 + (particle.size * 30).round(), 40, 0.55 * glow);
        canvas.drawCircle(p.offset, r, swarmPaint);
      });
    }

    // Petrova line: Astrophage streaming from the Sun toward Venus.
    final streamCount = (220 * frac).round();
    final dir = Vec3(venus.x / venusOrbit, 0, venus.z / venusOrbit);
    final streamPaint = Paint();
    for (var i = 0; i < streamCount; i++) {
      final s = (i / 220 + clock * 0.25) % 1.0;
      final along = 1.0 + s * (venusOrbit - 1.0);
      final wobble = math.sin(i * 12.9898) * 0.12 * (1 - s);
      final lift = math.cos(i * 78.233) * 0.12 * (1 - s);
      final v = Vec3(dir.x * along - dir.z * wobble, lift,
          dir.z * along + dir.x * wobble);
      final p = _project(v);
      add(p, () {
        streamPaint.color =
            Color.fromRGBO(255, 70, 70, 0.55 * (1 - s * 0.6));
        canvas.drawCircle(p.offset, 1.1 * p.scale * (_unit / 40), streamPaint);
      });
    }

    // Planets.
    final venusP = _project(venus);
    add(venusP, () => _paintPlanet(canvas, venusP, 0.22,
        const Color(0xFFE8D6A8), const Color(0xFF8A7650)));
    final earthP = _project(earth);
    final iceMix = (tempDropC / 8).clamp(0.0, 1.0);
    add(earthP, () => _paintPlanet(
          canvas,
          earthP,
          0.26,
          Color.lerp(const Color(0xFF4FA3FF), const Color(0xFFEAF6FF), iceMix)!,
          Color.lerp(const Color(0xFF1C4E9A), const Color(0xFF9DB7C9), iceMix)!,
        ));

    for (final d in back) {
      d();
    }
    _paintSun(canvas, sunBrightness);
    for (final d in front) {
      d();
    }
  }

  void _paintStars(Canvas canvas, Size size) {
    final paint = Paint();
    for (var i = 0; i < scene.stars.length; i++) {
      final s = scene.stars[i];
      final twinkle = 0.35 + 0.35 * math.sin(clock * 1.3 + i * 2.1);
      paint.color = Colors.white.withValues(alpha: twinkle.clamp(0.1, 0.8));
      canvas.drawCircle(Offset(s.dx * size.width, s.dy * size.height),
          i % 7 == 0 ? 1.3 : 0.7, paint);
    }
  }

  void _paintOrbitRing(Canvas canvas, double radius) {
    final path = Path();
    for (var i = 0; i <= 96; i++) {
      final a = i / 96 * math.pi * 2;
      final p = _project(Vec3(radius * math.cos(a), 0, radius * math.sin(a)));
      if (i == 0) {
        path.moveTo(p.offset.dx, p.offset.dy);
      } else {
        path.lineTo(p.offset.dx, p.offset.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.08),
    );
  }

  void _paintSun(Canvas canvas, double brightness) {
    final p = _project(const Vec3(0, 0, 0));
    final r = _unit * p.scale;
    final b = brightness.clamp(0.0, 1.0);
    final hot = Color.lerp(const Color(0xFF7A2A10), const Color(0xFFFFF4C8), b)!;
    final mid = Color.lerp(const Color(0xFF4A1508), const Color(0xFFFFB347), b)!;
    final edge = Color.lerp(const Color(0xFF2A0A04), const Color(0xFFE8641E), b)!;

    // Glow.
    canvas.drawCircle(
      p.offset,
      r * 3.2,
      Paint()
        ..shader = RadialGradient(colors: [
          mid.withValues(alpha: 0.45 * b),
          mid.withValues(alpha: 0.0),
        ]).createShader(Rect.fromCircle(center: p.offset, radius: r * 3.2)),
    );
    // Disc.
    canvas.drawCircle(
      p.offset,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [hot, mid, edge],
          stops: const [0.0, 0.7, 1.0],
        ).createShader(Rect.fromCircle(center: p.offset, radius: r)),
    );
  }

  void _paintPlanet(Canvas canvas, _Projected p, double radius, Color light,
      Color dark) {
    final r = radius * _unit * p.scale;
    // Lit from the Sun's side.
    final toSun = (_project(const Vec3(0, 0, 0)).offset - p.offset);
    final len = toSun.distance == 0 ? 1.0 : toSun.distance;
    final focal = Alignment(toSun.dx / len * 0.6, toSun.dy / len * 0.6);
    canvas.drawCircle(
      p.offset,
      r,
      Paint()
        ..shader = RadialGradient(
          center: focal,
          radius: 1.1,
          colors: [light, dark, const Color(0xFF05060C)],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(Rect.fromCircle(center: p.offset, radius: r)),
    );
  }

  @override
  bool shouldRepaint(covariant OrbitPainter old) => true;
}
