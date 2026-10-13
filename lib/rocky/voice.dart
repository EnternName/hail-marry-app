import 'package:web/web.dart' as web;

import 'words.dart';

/// Plays Eridian words as soft chords through the browser's Web Audio API.
class RockyVoice {
  web.AudioContext? _ctx;

  /// Low pentatonic scale, so Rocky sounds big and a little whale-like.
  static const List<double> scale = [196.0, 220.0, 261.63, 293.66, 329.63];

  static const double shortNote = 0.2;
  static const double longNote = 0.45;
  static const double gap = 0.06;

  /// Plays [sounds] and returns how long it takes, in seconds.
  double say(List<Syllable> sounds) {
    try {
      final ctx = _ctx ??= web.AudioContext();
      // Browsers start audio paused until the first tap.
      if (ctx.state == 'suspended') ctx.resume();
      var t = ctx.currentTime + 0.05;
      for (final s in sounds) {
        final d = s.long ? longNote : shortNote;
        _chord(ctx, scale[s.note], t, d);
        t += d + gap;
      }
      return t - ctx.currentTime;
    } catch (_) {
      return duration(sounds);
    }
  }

  static double duration(List<Syllable> sounds) =>
      sounds.fold(0.05, (t, s) => t + (s.long ? longNote : shortNote) + gap);

  void _chord(web.AudioContext ctx, double freq, double t, double d) {
    // Root, fifth and octave, each sliding up into pitch a little.
    const voices = [
      (1.0, 'triangle', 0.22),
      (1.5, 'sine', 0.1),
      (2.0, 'sine', 0.06),
    ];
    for (final (ratio, type, volume) in voices) {
      final osc = ctx.createOscillator()..type = type;
      final f = freq * ratio;
      osc.frequency
        ..setValueAtTime(f * 0.96, t)
        ..linearRampToValueAtTime(f, t + 0.05);
      final gain = ctx.createGain();
      gain.gain
        ..setValueAtTime(0.0001, t)
        ..exponentialRampToValueAtTime(volume, t + 0.025)
        ..setValueAtTime(volume, t + d * 0.6)
        ..exponentialRampToValueAtTime(0.0001, t + d);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(t);
      osc.stop(t + d + 0.05);
    }
  }
}
