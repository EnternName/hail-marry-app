import 'dart:math' as math;

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'rocky/rocky_screen.dart';

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
      home: const HomeShell(),
    );
  }
}

/// Bottom tabs: the Astrophage simulator and Talk to Rocky.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          // Pause the animation of whichever tab is hidden.
          TickerMode(enabled: _tab == 0, child: const AstrophageScreen()),
          TickerMode(enabled: _tab == 1, child: const RockyScreen()),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        height: 64,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.wb_sunny_outlined),
              selectedIcon: Icon(Icons.wb_sunny),
              label: 'Astrophage'),
          NavigationDestination(
              icon: Icon(Icons.graphic_eq),
              label: 'Talk to Rocky'),
        ],
      ),
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
  static const double defaultDoublingMonths = 12;
  static const double defaultStartLog = -4;
  static const double defaultYaw = 0.6;
  static const double defaultPitch = 0.45;

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _clock = 0; // seconds, drives the 3D motion

  double _doublingMonths = defaultDoublingMonths;
  double _startLog = defaultStartLog; // log10 of the starting dimming fraction
  double _years = 0;
  bool _playing = false;

  double _yaw = defaultYaw;
  double _pitch = defaultPitch;
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

  /// Puts the time, both sliders and the camera back to where they started.
  void _reset() {
    setState(() {
      _playing = false;
      _years = 0;
      _doublingMonths = defaultDoublingMonths;
      _startLog = defaultStartLog;
      _yaw = defaultYaw;
      _pitch = defaultPitch;
      _autoSpin = true;
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
                onReset: _reset,
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
    required this.onReset,
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
  final VoidCallback onReset;
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
              IconButton(
                tooltip: 'Reset everything',
                onPressed: onReset,
                icon: const Icon(Icons.restart_alt),
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

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
}

/// Tilts [v] by [inclination] around the x axis, then turns it by [node]
/// around the vertical axis.
Vec3 tilt(Vec3 v, double inclination, double node) {
  final ci = math.cos(inclination), si = math.sin(inclination);
  final y = v.y * ci - v.z * si;
  final z = v.y * si + v.z * ci;
  final cn = math.cos(node), sn = math.sin(node);
  return Vec3(v.x * cn + z * sn, y, -v.x * sn + z * cn);
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
    required this.flicker,
  });

  final double radius; // in Sun radii
  final double inclination;
  final double node;
  final double phase;
  final double speed;
  final double threshold; // appears once the swarm is this big (0..1)
  final double size;
  final double flicker; // how fast it shimmers

  Vec3 position(double t) {
    final a = phase + speed * t;
    // The orbit gently breathes in and out, and bobs above and below it.
    final r = radius * (1 + 0.05 * math.sin(t * 0.9 + phase * 3));
    final bob = 0.06 * math.sin(t * 1.3 + phase * 5);
    return tilt(Vec3(r * math.cos(a), bob, r * math.sin(a)), inclination, node);
  }
}

class Star {
  const Star({
    required this.dir,
    required this.size,
    required this.brightness,
    required this.color,
    required this.twinkle,
    required this.phase,
  });

  final Vec3 dir; // unit vector on the sky
  final double size;
  final double brightness;
  final Color color;
  final double twinkle; // twinkle speed
  final double phase;
}

class Nebula {
  const Nebula(
      {required this.dir,
      required this.radius,
      required this.color,
      required this.phase});
  final Vec3 dir;
  final double radius; // angular size
  final Color color;
  final double phase;
}

class Scene {
  Scene(this.particles, this.stars, this.nebulae);

  final List<SwarmParticle> particles;
  final List<Star> stars;
  final List<Nebula> nebulae;
  static const int count = 1600;

  // The Milky Way: a band of faint stars around a tilted great circle.
  static const double bandInclination = 1.05;
  static const double bandNode = 0.4;

  factory Scene.generate({required int seed}) {
    final rnd = math.Random(seed);
    final particles = List.generate(count, (i) {
      final r = 1.08 + math.pow(rnd.nextDouble(), 2.2).toDouble() * 1.1;
      return SwarmParticle(
        radius: r,
        inclination: (rnd.nextDouble() - 0.5) * math.pi,
        node: rnd.nextDouble() * math.pi * 2,
        phase: rnd.nextDouble() * math.pi * 2,
        speed: (0.5 + rnd.nextDouble() * 0.35) / math.pow(r, 1.5),
        threshold: i / count,
        size: 0.6 + rnd.nextDouble() * 1.3,
        flicker: 1.5 + rnd.nextDouble() * 3,
      );
    });

    const starColors = [
      Color(0xFFFFFFFF),
      Color(0xFFFFFFFF),
      Color(0xFFCAD8FF),
      Color(0xFFFFE6C0),
      Color(0xFFFFB89A),
    ];
    Vec3 randomDir() {
      final z = rnd.nextDouble() * 2 - 1;
      final t = rnd.nextDouble() * math.pi * 2;
      final s = math.sqrt(1 - z * z);
      return Vec3(s * math.cos(t), z, s * math.sin(t));
    }

    Vec3 bandDir() {
      final a = rnd.nextDouble() * math.pi * 2;
      final spread = (rnd.nextDouble() - 0.5) * rnd.nextDouble() * 0.5;
      final d = Vec3(math.cos(a), spread, math.sin(a));
      final len = math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z);
      return tilt(Vec3(d.x / len, d.y / len, d.z / len), bandInclination,
          bandNode);
    }

    final stars = <Star>[
      for (var i = 0; i < 2600; i++)
        Star(
          dir: randomDir(),
          size: 0.45 + math.pow(rnd.nextDouble(), 6).toDouble() * 1.6,
          brightness: 0.35 + rnd.nextDouble() * 0.6,
          color: starColors[rnd.nextInt(starColors.length)],
          twinkle: 0.6 + rnd.nextDouble() * 2.4,
          phase: rnd.nextDouble() * math.pi * 2,
        ),
      for (var i = 0; i < 2200; i++)
        Star(
          dir: bandDir(),
          size: 0.3 + rnd.nextDouble() * 0.45,
          brightness: 0.15 + rnd.nextDouble() * 0.35,
          color: const Color(0xFFDDE4FF),
          twinkle: 0.4 + rnd.nextDouble(),
          phase: rnd.nextDouble() * math.pi * 2,
        ),
    ];

    const nebulaColors = [
      Color(0xFF6A3DD8),
      Color(0xFF2F6BD8),
      Color(0xFFC0398F),
      Color(0xFF2FA8B8),
    ];
    final nebulae = <Nebula>[
      for (var i = 0; i < 9; i++)
        Nebula(
          dir: i < 6 ? bandDir() : randomDir(),
          radius: 0.25 + rnd.nextDouble() * 0.35,
          color: nebulaColors[i % nebulaColors.length],
          phase: rnd.nextDouble() * math.pi * 2,
        ),
    ];
    return Scene(particles, stars, nebulae);
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

  /// Turns [v] into camera space: x right, y down, z away from the viewer.
  Vec3 _rotate(Vec3 v) {
    final cy = math.cos(yaw), sy = math.sin(yaw);
    final x1 = v.x * cy + v.z * sy;
    final z1 = -v.x * sy + v.z * cy;
    final cp = math.cos(pitch), sp = math.sin(pitch);
    return Vec3(x1, v.y * cp - z1 * sp, v.y * sp + z1 * cp);
  }

  _Projected _project(Vec3 v) {
    final c = _rotate(v);
    final s = cameraDistance / (cameraDistance + c.z);
    return _Projected(
      _center + Offset(c.x, c.y) * (_unit * s),
      c.z,
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

    _paintSky(canvas, size);
    _paintShootingStar(canvas, size);

    final frac = _swarmFraction;
    final sunBrightness = 1 - dimming;

    // Planets on the ecliptic.
    final venusAngle = clock * 0.22;
    final earthAngle = clock * 0.14 + 1.8;
    final venus = Vec3(venusOrbit * math.cos(venusAngle), 0,
        venusOrbit * math.sin(venusAngle));
    final earth = Vec3(earthOrbit * math.cos(earthAngle), 0,
        earthOrbit * math.sin(earthAngle));
    final moonAngle = clock * 1.1;
    final moon = earth +
        Vec3(0.5 * math.cos(moonAngle), 0.08 * math.sin(moonAngle),
            0.5 * math.sin(moonAngle));

    _paintOrbitRing(canvas, venusOrbit);
    _paintOrbitRing(canvas, earthOrbit);

    // Collect everything that can be in front of or behind the Sun.
    final back = <void Function()>[];
    final front = <void Function()>[];

    void add(_Projected p, void Function() draw) {
      (p.depth > 0 ? back : front).add(draw);
    }

    // Swarm: glowing specks with short motion trails. New specks fade in
    // as the swarm grows.
    final swarmPaint = Paint()
      ..blendMode = BlendMode.plus
      ..strokeCap = StrokeCap.round;
    for (final particle in scene.particles) {
      if (particle.threshold > frac) break;
      final fadeIn = ((frac - particle.threshold) / 0.04).clamp(0.0, 1.0);
      final p = _project(particle.position(clock));
      final tail = _project(particle.position(clock - 0.3));
      final r = particle.size * p.scale * (_unit / 40) * (0.5 + 0.5 * fadeIn);
      final glow = (0.35 + 0.65 * p.scale.clamp(0.0, 1.2) / 1.2);
      final shimmer =
          0.6 + 0.4 * math.sin(clock * particle.flicker + particle.phase * 7);
      final alpha = 0.5 * glow * shimmer * fadeIn;
      final color =
          Color.fromRGBO(255, 90 + (particle.size * 30).round(), 40, 1);
      add(p, () {
        swarmPaint
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 1.1
          ..color = color.withValues(alpha: alpha * 0.3);
        canvas.drawLine(tail.offset, p.offset, swarmPaint);
        swarmPaint
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: alpha);
        canvas.drawCircle(p.offset, r, swarmPaint);
        if (particle.size > 1.6) {
          swarmPaint.color = color.withValues(alpha: alpha * 0.15);
          canvas.drawCircle(p.offset, r * 3, swarmPaint);
        }
      });
    }

    // Petrova line: Astrophage streaming from the Sun toward Venus.
    final streamCount = (220 * frac).round();
    final dir = Vec3(venus.x / venusOrbit, 0, venus.z / venusOrbit);
    final streamPaint = Paint()..blendMode = BlendMode.plus;
    for (var i = 0; i < streamCount; i++) {
      final s = (i / 220 + clock * 0.3) % 1.0;
      final along = 1.0 + s * (venusOrbit - 1.0);
      final swirl = clock * 2 + i * 0.7;
      final wobble = (math.sin(i * 12.9898) * 0.12 + 0.03 * math.sin(swirl)) *
          (1 - s);
      final lift = (math.cos(i * 78.233) * 0.12 + 0.03 * math.cos(swirl)) *
          (1 - s);
      final v = Vec3(dir.x * along - dir.z * wobble, lift,
          dir.z * along + dir.x * wobble);
      final p = _project(v);
      final flicker = 0.7 + 0.3 * math.sin(clock * 5 + i * 1.3);
      add(p, () {
        streamPaint.color =
            Color.fromRGBO(255, 70, 70, 0.5 * flicker * (1 - s * 0.6));
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
          haze: const Color(0xFF7FC4FF),
        ));
    final moonP = _project(moon);
    add(moonP, () => _paintPlanet(canvas, moonP, 0.08,
        const Color(0xFFD8D8D8), const Color(0xFF6A6A6A)));

    for (final d in back) {
      d();
    }
    _paintSun(canvas, sunBrightness);
    for (final d in front) {
      d();
    }
  }

  /// Deep space: a soft backdrop, colored nebulae, the Milky Way and
  /// twinkling stars, all fixed on a sky sphere that turns with the camera.
  void _paintSky(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          radius: 0.9,
          colors: [Color(0xFF0B1030), Color(0xFF05060C)],
        ).createShader(rect),
    );

    final focal = size.longestSide * 0.6;
    final skyCenter = size.center(Offset.zero);
    final bounds = rect.inflate(40);

    Offset? onSky(Vec3 dir) {
      final c = _rotate(dir);
      if (c.z < 0.1) return null;
      final o = skyCenter + Offset(c.x, c.y) * (focal / c.z);
      return bounds.contains(o) ? o : null;
    }

    for (final n in scene.nebulae) {
      final c = _rotate(n.dir);
      if (c.z < 0.15) continue;
      final o = skyCenter + Offset(c.x, c.y) * (focal / c.z);
      final r = n.radius * focal / c.z;
      if (!rect.inflate(r).contains(o)) continue;
      final a = 0.15 + 0.05 * math.sin(clock * 0.3 + n.phase);
      canvas.drawCircle(
        o,
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            n.color.withValues(alpha: a),
            n.color.withValues(alpha: a * 0.35),
            n.color.withValues(alpha: 0),
          ], stops: const [
            0.0,
            0.45,
            1.0
          ]).createShader(Rect.fromCircle(center: o, radius: r)),
      );
    }

    final paint = Paint();
    for (final s in scene.stars) {
      final o = onSky(s.dir);
      if (o == null) continue;
      final twinkle = 0.7 + 0.3 * math.sin(clock * s.twinkle + s.phase);
      final a = (s.brightness * twinkle).clamp(0.0, 1.0);
      paint.color = s.color.withValues(alpha: a);
      canvas.drawCircle(o, s.size, paint);
      if (s.size > 1.3) {
        // Bright stars get a soft halo...
        paint.color = s.color.withValues(alpha: a * 0.12);
        canvas.drawCircle(o, s.size * 4, paint);
      }
      if (s.size > 1.85) {
        // ...and the brightest few faint diffraction spikes.
        final spike = s.size * (3.5 + 1.5 * twinkle);
        paint
          ..strokeWidth = 0.6
          ..color = s.color.withValues(alpha: a * 0.35);
        canvas.drawLine(o.translate(-spike, 0), o.translate(spike, 0), paint);
        canvas.drawLine(o.translate(0, -spike), o.translate(0, spike), paint);
      }
    }
  }

  /// Every few seconds a meteor streaks across the sky.
  void _paintShootingStar(Canvas canvas, Size size) {
    const period = 5.5;
    const visible = 0.9; // seconds
    final n = (clock / period).floor();
    final t = clock - n * period;
    if (t > visible) return;
    final rnd = math.Random(n * 7919 + 13);
    final start = Offset(rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height * 0.6);
    final angle = 0.3 + rnd.nextDouble() * 0.6;
    final sign = rnd.nextBool() ? 1.0 : -1.0;
    final dir = Offset(math.cos(angle) * sign, math.sin(angle));
    final len = size.shortestSide * (0.3 + rnd.nextDouble() * 0.25);
    final p = t / visible;
    final head = start + dir * (len * p);
    final tail = start + dir * (len * math.max(0.0, p - 0.35));
    final fade = math.sin(p * math.pi);
    if (head == tail) return;
    canvas.drawLine(
      tail,
      head,
      Paint()
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.85 * fade),
        ]).createShader(Rect.fromPoints(tail, head)),
    );
    canvas.drawCircle(
        head, 1.8, Paint()..color = Colors.white.withValues(alpha: fade));
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

    // Corona: slowly turning rays that stretch and shrink.
    final rayPaint = Paint()..blendMode = BlendMode.plus;
    const rays = 16;
    for (var i = 0; i < rays; i++) {
      final a = i / rays * math.pi * 2 + clock * 0.06 * (i.isEven ? 1 : -1);
      final len = r * (1.7 + 0.6 * math.sin(clock * 0.8 + i * 1.7));
      final d = Offset(math.cos(a), math.sin(a));
      final side = Offset(-d.dy, d.dx) * (r * 0.2);
      final base = p.offset + d * (r * 0.85);
      rayPaint.shader = RadialGradient(
        colors: [
          mid.withValues(alpha: 0.28 * b),
          mid.withValues(alpha: 0),
        ],
        stops: [r / len, 1.0],
      ).createShader(Rect.fromCircle(center: p.offset, radius: len));
      canvas.drawPath(
        Path()
          ..moveTo(base.dx + side.dx, base.dy + side.dy)
          ..lineTo(p.offset.dx + d.dx * len, p.offset.dy + d.dy * len)
          ..lineTo(base.dx - side.dx, base.dy - side.dy)
          ..close(),
        rayPaint,
      );
    }

    // Glow, gently pulsing.
    final glowR = r * 3.2 * (1 + 0.06 * math.sin(clock * 1.6));
    canvas.drawCircle(
      p.offset,
      glowR,
      Paint()
        ..shader = RadialGradient(colors: [
          mid.withValues(alpha: 0.45 * b),
          mid.withValues(alpha: 0.0),
        ]).createShader(Rect.fromCircle(center: p.offset, radius: glowR)),
    );
    // Disc, with a hot spot that drifts across the surface.
    canvas.drawCircle(
      p.offset,
      r,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(0.18 * math.sin(clock * 0.7),
              0.18 * math.cos(clock * 0.5)),
          colors: [hot, mid, edge],
          stops: const [0.0, 0.65, 1.0],
        ).createShader(Rect.fromCircle(center: p.offset, radius: r)),
    );
  }

  void _paintPlanet(
      Canvas canvas, _Projected p, double radius, Color light, Color dark,
      {Color? haze}) {
    final r = radius * _unit * p.scale;
    if (haze != null) {
      // Thin atmosphere glow.
      canvas.drawCircle(
        p.offset,
        r * 1.35,
        Paint()
          ..shader = RadialGradient(colors: [
            haze.withValues(alpha: 0.35),
            haze.withValues(alpha: 0),
          ], stops: const [
            0.7,
            1.0
          ]).createShader(Rect.fromCircle(center: p.offset, radius: r * 1.35)),
      );
    }
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
