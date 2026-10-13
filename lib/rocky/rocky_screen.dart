import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:web/web.dart' as web;

import 'voice.dart';
import 'words.dart';

const _accent = Color(0xFFFFB27A);
const _panel = Color(0xFF0D0F1A);
const _card = Color(0xFF1A1F33);

/// One color per note, low to high.
const noteColors = [
  Color(0xFFFF7A59),
  Color(0xFFFFC145),
  Color(0xFF7BD389),
  Color(0xFF4FB3FF),
  Color(0xFFB98CFF),
];

// ---------------------------------------------------------------------------
// Progress, saved in the browser
// ---------------------------------------------------------------------------

class RockyProgress {
  static const _key = 'rocky.progress.v1';

  int level = 1;
  int xp = 0;
  int bestStreak = 0;
  bool hints = true;
  final Map<String, int> mastery = {}; // word → 0..5

  List<EridianWord> get unlocked =>
      eridianWords.where((w) => w.level <= level).toList();

  void load() {
    try {
      final raw = web.window.localStorage.getItem(_key);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      level = ((m['level'] as num?)?.toInt() ?? 1).clamp(1, maxLevel);
      xp = (m['xp'] as num?)?.toInt() ?? 0;
      bestStreak = (m['bestStreak'] as num?)?.toInt() ?? 0;
      hints = m['hints'] as bool? ?? true;
      final saved = m['mastery'];
      if (saved is Map) {
        saved.forEach((k, v) {
          if (k is String && v is num) mastery[k] = v.toInt();
        });
      }
    } catch (_) {
      // Storage can be blocked (private browsing); start fresh.
    }
  }

  void save() {
    try {
      web.window.localStorage.setItem(
        _key,
        jsonEncode({
          'level': level,
          'xp': xp,
          'bestStreak': bestStreak,
          'hints': hints,
          'mastery': mastery,
        }),
      );
    } catch (_) {}
  }

  void reset() {
    level = 1;
    xp = 0;
    bestStreak = 0;
    mastery.clear();
    save();
  }
}

// ---------------------------------------------------------------------------
// Rounds
// ---------------------------------------------------------------------------

enum QuestionKind {
  /// Rocky says a word, you pick what it means.
  listen,

  /// You're shown a word, you pick how to say it.
  speak,
}

class Question {
  Question(this.kind, this.answer, this.options);
  final QuestionKind kind;
  final EridianWord answer;
  final List<EridianWord> options;
}

const int roundLength = 10;
const int passMark = 8;

List<Question> buildRound(RockyProgress p, math.Random rnd) {
  final pool = p.unlocked;
  final questions = <Question>[];
  EridianWord? last;
  for (var i = 0; i < roundLength; i++) {
    // Favor new words and words you keep missing.
    final weights = [
      for (final w in pool)
        (w.level == p.level ? 2.0 : 1.0) / (1 + (p.mastery[w.english] ?? 0)),
    ];
    EridianWord pick;
    do {
      var r = rnd.nextDouble() * weights.reduce((a, b) => a + b);
      var j = 0;
      while (r > weights[j] && j < pool.length - 1) {
        r -= weights[j];
        j++;
      }
      pick = pool[j];
    } while (identical(pick, last) && pool.length > 1);
    last = pick;

    final kind = p.level >= 2 && rnd.nextDouble() < 0.4
        ? QuestionKind.speak
        : QuestionKind.listen;
    final count = kind == QuestionKind.listen ? 4 : 3;
    final others = pool.where((w) => !identical(w, pick)).toList()
      ..shuffle(rnd);
    final options = [pick, ...others.take(count - 1)]..shuffle(rnd);
    questions.add(Question(kind, pick, options));
  }
  return questions;
}

const _cheers = [
  'Amaze! Amaze! Amaze!',
  'Yes! You learn fast, friend.',
  'Good good good.',
  'Correct. Rocky is happy.',
  'Fist my bump!',
];
const _groans = [
  'No no no.',
  'Bad. Listen again, friend.',
  'Hmm. Human ears are strange.',
  'Wrong. Rocky is patient.',
];

// ---------------------------------------------------------------------------
// The screen
// ---------------------------------------------------------------------------

class RockyScreen extends StatefulWidget {
  const RockyScreen({super.key});

  @override
  State<RockyScreen> createState() => _RockyScreenState();
}

class _RockyScreenState extends State<RockyScreen> {
  final _progress = RockyProgress()..load();
  final _voice = RockyVoice();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TALK TO ROCKY',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 4,
                              color: _accent,
                            ),
                          ),
                          Text(
                            'Learn Eridian, one chord at a time',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _Badge(
                      label: 'LEVEL',
                      value: '${_progress.level}/$maxLevel',
                    ),
                    const SizedBox(width: 8),
                    _Badge(label: 'XP', value: '${_progress.xp}'),
                  ],
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(text: 'Talk'),
                  Tab(text: 'Words'),
                ],
                indicatorColor: _accent,
                labelColor: _accent,
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _TalkTab(
                      progress: _progress,
                      voice: _voice,
                      onChanged: () => setState(() {}),
                    ),
                    _WordsTab(
                      progress: _progress,
                      voice: _voice,
                      onReset: () => setState(_progress.reset),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 2,
            color: Colors.white54,
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Talk tab: the quiz
// ---------------------------------------------------------------------------

class _TalkTab extends StatefulWidget {
  const _TalkTab({
    required this.progress,
    required this.voice,
    required this.onChanged,
  });

  final RockyProgress progress;
  final RockyVoice voice;
  final VoidCallback onChanged;

  @override
  State<_TalkTab> createState() => _TalkTabState();
}

class _TalkTabState extends State<_TalkTab> with AutomaticKeepAliveClientMixin {
  final _rnd = math.Random();

  List<Question>? _round;
  int _index = 0;
  EridianWord? _selected;
  bool _answered = false;
  int _correct = 0;
  int _streak = 0;
  int _earned = 0;
  bool _finished = false;
  List<EridianWord> _newWords = const [];

  String _bubble = 'Hello, friend. Learn my words, question?';
  int _mood = 0; // -1 sad, 0 calm, 1 happy
  int _speakToken = 0;
  double _speakSeconds = 0;
  List<Syllable> _speakSounds = const [];

  RockyProgress get _p => widget.progress;
  Question get _q => _round![_index];

  @override
  bool get wantKeepAlive => true;

  void _say(EridianWord w) {
    final secs = widget.voice.say(w.sounds);
    setState(() {
      _speakToken++;
      _speakSeconds = secs;
      _speakSounds = w.sounds;
    });
  }

  void _start() {
    setState(() {
      _round = buildRound(_p, _rnd);
      _index = 0;
      _correct = 0;
      _streak = 0;
      _earned = 0;
      _finished = false;
      _newWords = const [];
    });
    _ask();
  }

  void _ask() {
    setState(() {
      _selected = null;
      _answered = false;
      _mood = 0;
    });
    if (_q.kind == QuestionKind.listen) {
      _bubble = 'Listen…';
      _say(_q.answer);
    } else {
      setState(() => _bubble = 'Rocky waits. Say “${_q.answer.english}”.');
    }
  }

  void _pickListen(EridianWord w) {
    if (_answered) return;
    _selected = w;
    _submit();
  }

  void _pickSpeak(EridianWord w) {
    if (_answered) return;
    setState(() => _selected = w);
    _say(w);
  }

  void _submit() {
    final right = identical(_selected, _q.answer);
    final word = _q.answer.english;
    setState(() {
      _answered = true;
      if (right) {
        _correct++;
        _streak++;
        final gained = 10 + (_p.hints ? 0 : 10) + math.min(_streak, 5) * 2;
        _earned += gained;
        _p.xp += gained;
        _p.bestStreak = math.max(_p.bestStreak, _streak);
        _p.mastery[word] = math.min(5, (_p.mastery[word] ?? 0) + 1);
        _mood = 1;
        _bubble = _cheers[_rnd.nextInt(_cheers.length)];
      } else {
        _streak = 0;
        _p.mastery[word] = math.max(0, (_p.mastery[word] ?? 0) - 1);
        _mood = -1;
        _bubble =
            '${_groans[_rnd.nextInt(_groans.length)]} '
            'That was “$word”.';
      }
    });
    _p.save();
    widget.onChanged();
    _say(wordFor(right ? 'yes' : 'no'));
  }

  void _next() {
    if (_index + 1 < roundLength) {
      setState(() => _index++);
      _ask();
      return;
    }
    final passed = _correct >= passMark;
    setState(() {
      _finished = true;
      if (passed && _p.level < maxLevel) {
        _p.level++;
        _newWords = eridianWords.where((w) => w.level == _p.level).toList();
        _bubble = 'Amaze! Amaze! Amaze! New words for you, friend.';
        _mood = 1;
      } else if (passed) {
        _bubble = 'You speak Eridian like Rocky. Fist my bump!';
        _mood = 1;
      } else {
        _bubble =
            'Practice more, question? Get $passMark right to learn '
            'new words.';
        _mood = 0;
      }
    });
    _p.save();
    widget.onChanged();
    _say(wordFor(passed ? 'amaze' : 'friend'));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _SpeechBubble(text: _bubble),
        SizedBox(
          height: 190,
          child: RockyStage(
            speakToken: _speakToken,
            speakSeconds: _speakSeconds,
            sounds: _speakSounds,
            mood: _mood,
          ),
        ),
        const SizedBox(height: 8),
        if (_round == null)
          _buildHome()
        else if (_finished)
          _buildResult()
        else
          _buildQuestion(),
      ],
    );
  }

  Widget _buildHome() {
    final words = _p.unlocked;
    final mastered = words.where((w) => (_p.mastery[w.english] ?? 0) >= 3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Level ${_p.level} · ${words.length} words unlocked',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Rounds have $roundLength questions. Get $passMark right to '
                'unlock new words.',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: words.isEmpty ? 0 : mastered.length / words.length,
                  minHeight: 6,
                  color: _accent,
                  backgroundColor: Colors.white12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${mastered.length} of ${words.length} mastered · '
                'best streak ${_p.bestStreak}',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.graphic_eq),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Start talking', style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          value: _p.hints,
          onChanged: (v) {
            setState(() => _p.hints = v);
            _p.save();
          },
          title: const Text('Show note patterns'),
          subtitle: const Text('Turn off to play by ear for double XP.'),
        ),
        const _SoundTip(),
      ],
    );
  }

  Widget _buildQuestion() {
    final q = _q;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Question ${_index + 1} of $roundLength',
              style: const TextStyle(color: Colors.white70),
            ),
            const Spacer(),
            if (_streak >= 2) ...[
              const Icon(
                Icons.local_fire_department,
                size: 18,
                color: Color(0xFFFF8A5B),
              ),
              Text(
                ' $_streak',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
            ],
            Text('+$_earned XP', style: const TextStyle(color: _accent)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (_index + (_answered ? 1 : 0)) / roundLength,
            minHeight: 4,
            color: _accent,
            backgroundColor: Colors.white12,
          ),
        ),
        const SizedBox(height: 14),
        if (q.kind == QuestionKind.listen)
          ..._listenBody(q)
        else
          ..._speakBody(q),
        const SizedBox(height: 12),
        if (_answered)
          FilledButton(
            onPressed: _next,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _index + 1 < roundLength ? 'Next' : 'See results',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _listenBody(Question q) {
    return [
      Row(
        children: [
          const Expanded(
            child: Text(
              'What did Rocky say?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Hear it again',
            onPressed: () => _say(q.answer),
            icon: const Icon(Icons.replay),
          ),
        ],
      ),
      if (_p.hints || _answered)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Center(child: NotesView(q.answer, height: 46)),
        ),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.6,
        children: [
          for (final w in q.options)
            _ChoiceButton(
              state: _stateFor(w, q),
              onTap: () => _pickListen(w),
              child: Text(
                w.english,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    ];
  }

  List<Widget> _speakBody(Question q) {
    return [
      Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          children: [
            const TextSpan(text: 'How do you say '),
            TextSpan(
              text: '“${q.answer.english}”',
              style: const TextStyle(color: _accent),
            ),
            const TextSpan(text: '?'),
          ],
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        'Tap a sound to hear it, then say it to Rocky.',
        style: TextStyle(fontSize: 13, color: Colors.white54),
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < q.options.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _ChoiceButton(
            state: _stateFor(q.options[i], q),
            onTap: () => _pickSpeak(q.options[i]),
            child: Row(
              children: [
                const Icon(Icons.volume_up, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Sound ${String.fromCharCode(65 + i)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (_p.hints || _answered) NotesView(q.options[i], height: 30),
                if (_answered) ...[
                  const SizedBox(width: 8),
                  Text(
                    q.options[i].english,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
        ),
      if (!_answered)
        FilledButton.tonalIcon(
          onPressed: _selected == null ? null : _submit,
          icon: const Icon(Icons.record_voice_over),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Say it to Rocky', style: TextStyle(fontSize: 16)),
          ),
        ),
    ];
  }

  _ChoiceState _stateFor(EridianWord w, Question q) {
    if (_answered) {
      if (identical(w, q.answer)) return _ChoiceState.right;
      if (identical(w, _selected)) return _ChoiceState.wrong;
      return _ChoiceState.faded;
    }
    return identical(w, _selected) ? _ChoiceState.selected : _ChoiceState.idle;
  }

  Widget _buildResult() {
    final passed = _correct >= passMark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          child: Column(
            children: [
              Text(
                '$_correct / $roundLength',
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                passed ? 'Rocky understood you!' : 'Not quite fluent yet.',
                style: TextStyle(
                  fontSize: 16,
                  color: passed ? const Color(0xFF9BE39B) : Colors.white70,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '+$_earned XP',
                style: const TextStyle(
                  color: _accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (_newWords.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Level ${_p.level} unlocked: new words',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                for (final w in _newWords)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    onTap: () => _say(w),
                    leading: const Icon(Icons.volume_up),
                    title: Text(
                      w.english,
                      style: const TextStyle(fontSize: 15),
                    ),
                    trailing: NotesView(w, height: 28),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.replay),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Play again', style: TextStyle(fontSize: 16)),
          ),
        ),
        TextButton(
          onPressed: () => setState(() {
            _round = null;
            _bubble = 'Rocky is here when you want to talk.';
            _mood = 0;
          }),
          child: const Text('Back'),
        ),
      ],
    );
  }
}

enum _ChoiceState { idle, selected, right, wrong, faded }

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.state,
    required this.onTap,
    required this.child,
  });
  final _ChoiceState state;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final (bg, border) = switch (state) {
      _ChoiceState.idle => (_card, Colors.white12),
      _ChoiceState.selected => (const Color(0xFF3A2A22), _accent),
      _ChoiceState.right => (const Color(0xFF1E3A26), const Color(0xFF7BD389)),
      _ChoiceState.wrong => (const Color(0xFF3F1D1D), const Color(0xFFFF6B6B)),
      _ChoiceState.faded => (_card.withValues(alpha: 0.5), Colors.white10),
    };
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey(text),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _accent.withValues(alpha: 0.4)),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, height: 1.3),
        ),
      ),
    );
  }
}

class _SoundTip extends StatelessWidget {
  const _SoundTip();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.volume_up, size: 16, color: Colors.white54),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Turn your sound up. On iPhone, also flip the silent switch '
              'off, or Rocky stays quiet.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Words tab
// ---------------------------------------------------------------------------

class _WordsTab extends StatelessWidget {
  const _WordsTab({
    required this.progress,
    required this.voice,
    required this.onReset,
  });
  final RockyProgress progress;
  final RockyVoice voice;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (var level = 1; level <= maxLevel; level++) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
            child: Row(
              children: [
                Text(
                  'LEVEL $level',
                  style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 2,
                    color: Colors.white54,
                  ),
                ),
                if (level > progress.level) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.lock, size: 13, color: Colors.white38),
                ],
              ],
            ),
          ),
          for (final w in eridianWords.where((w) => w.level == level))
            _WordTile(
              word: w,
              locked: level > progress.level,
              mastery: progress.mastery[w.english] ?? 0,
              onPlay: () => voice.say(w.sounds),
            ),
        ],
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Start over?'),
                content: const Text(
                  'This clears your level, XP and word progress.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      onReset();
                      Navigator.pop(ctx);
                    },
                    child: const Text('Start over'),
                  ),
                ],
              ),
            ),
            child: const Text(
              'Reset progress',
              style: TextStyle(color: Colors.white38),
            ),
          ),
        ),
      ],
    );
  }
}

class _WordTile extends StatelessWidget {
  const _WordTile({
    required this.word,
    required this.locked,
    required this.mastery,
    required this.onPlay,
  });

  final EridianWord word;
  final bool locked;
  final int mastery;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: locked ? 0.35 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          onTap: locked ? null : onPlay,
          leading: Icon(
            locked ? Icons.lock : Icons.volume_up,
            color: locked ? Colors.white38 : _accent,
          ),
          title: Text(
            locked ? '???' : word.english,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: locked
              ? Text('Unlocks at level ${word.level}')
              : Text(word.hint, style: const TextStyle(fontSize: 12)),
          trailing: locked
              ? null
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    NotesView(word, height: 26),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < 5; i++)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(left: 3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < mastery ? _accent : Colors.white12,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Note pattern: a tiny piano roll for one word
// ---------------------------------------------------------------------------

class NotesView extends StatelessWidget {
  const NotesView(this.word, {super.key, this.height = 40});
  final EridianWord word;
  final double height;

  @override
  Widget build(BuildContext context) {
    final unit = height * 0.32;
    final gap = unit * 0.3;
    final sounds = word.sounds;
    final width =
        sounds.fold<double>(
          0,
          (w, s) => w + (s.long ? unit * 2.2 : unit) + gap,
        ) -
        gap;
    return CustomPaint(
      size: Size(width, height),
      painter: _NotesPainter(sounds, unit, gap),
    );
  }
}

class _NotesPainter extends CustomPainter {
  _NotesPainter(this.sounds, this.unit, this.gap);
  final List<Syllable> sounds;
  final double unit;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final barH = size.height / 5;
    var x = 0.0;
    for (final s in sounds) {
      final w = s.long ? unit * 2.2 : unit;
      final y = (4 - s.note) * barH;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y + barH * 0.1, w, barH * 0.8),
          Radius.circular(barH * 0.4),
        ),
        Paint()..color = noteColors[s.note],
      );
      x += w + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _NotesPainter old) =>
      old.sounds != sounds || old.unit != unit;
}

// ---------------------------------------------------------------------------
// Rocky himself
// ---------------------------------------------------------------------------

class RockyStage extends StatefulWidget {
  const RockyStage({
    super.key,
    required this.speakToken,
    required this.speakSeconds,
    required this.sounds,
    required this.mood,
  });

  /// Changes every time Rocky starts saying something.
  final int speakToken;
  final double speakSeconds;
  final List<Syllable> sounds;
  final int mood;

  @override
  State<RockyStage> createState() => _RockyStageState();
}

class _RockyStageState extends State<RockyStage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _t = 0;
  double _talkStart = -10;
  double _talkUntil = -10;
  double _talk = 0; // eased 0..1

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final t = elapsed.inMicroseconds / 1e6;
      final dt = t - _t;
      final target = t < _talkUntil ? 1.0 : 0.0;
      setState(() {
        _t = t;
        _talk += (target - _talk) * math.min(1.0, dt * 10);
      });
    })..start();
  }

  @override
  void didUpdateWidget(RockyStage old) {
    super.didUpdateWidget(old);
    if (old.speakToken != widget.speakToken) {
      _talkStart = _t;
      _talkUntil = _t + widget.speakSeconds;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: RockyPainter(
        t: _t,
        talk: _talk,
        talkTime: _t - _talkStart,
        sounds: widget.sounds,
        mood: widget.mood,
      ),
    );
  }
}

class RockyPainter extends CustomPainter {
  RockyPainter({
    required this.t,
    required this.talk,
    required this.talkTime,
    required this.sounds,
    required this.mood,
  });

  final double t;
  final double talk;
  final double talkTime;
  final List<Syllable> sounds;
  final int mood;

  static const _shell = Color(0xFF8A7B6A);
  static const _shellDark = Color(0xFF4E4339);
  static const _leg = Color(0xFF5E5248);

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width * 0.2, size.height * 0.3);
    final ground = size.height * 0.92;
    final happyHop = mood > 0 ? (math.sin(t * 9).abs() * r * 0.18) : 0.0;
    final droop = mood < 0 ? r * 0.12 : 0.0;
    final bob =
        math.sin(t * 2) * r * 0.03 +
        talk * math.sin(t * 22) * r * 0.03 -
        happyHop +
        droop;
    final center = Offset(size.width / 2, ground - r * 1.55 + bob);

    // Shadow.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, ground + 2),
        width: r * 3.6,
        height: r * 0.35,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );

    _paintLegs(canvas, center, r, ground);
    _paintShell(canvas, center, r);
    _paintVoice(canvas, center, r);
  }

  void _paintLegs(Canvas canvas, Offset c, double r, double ground) {
    const angles = [160.0, 125.0, 90.0, 55.0, 20.0];
    final paint = Paint()
      ..color = _leg
      ..strokeWidth = r * 0.16
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final joint = Paint()..color = _shellDark;
    for (var i = 0; i < angles.length; i++) {
      final a = angles[i] * math.pi / 180;
      final ca = math.cos(a);
      final hip = c + Offset(ca * r * 0.75, math.sin(a) * r * 0.55);
      // Feet tap while Rocky talks, and dance when he's happy.
      final tap =
          (talk * 0.12 + (mood > 0 ? 0.15 : 0)) *
          math.sin(t * 14 + i * 1.9).abs();
      final foot = Offset(c.dx + ca * r * 2.0, ground - tap * r);
      final knee = Offset(
        hip.dx + ca * r * 0.95,
        hip.dy - r * 0.25 * ca.abs() + r * 0.1,
      );
      canvas.drawPath(
        Path()
          ..moveTo(hip.dx, hip.dy)
          ..lineTo(knee.dx, knee.dy)
          ..lineTo(foot.dx, foot.dy),
        paint,
      );
      canvas.drawCircle(knee, r * 0.11, joint);
      canvas.drawCircle(foot, r * 0.09, joint);
    }
  }

  void _paintShell(Canvas canvas, Offset c, double r) {
    // Rounded pentagon carapace.
    final pts = [
      for (var k = 0; k < 5; k++)
        c +
            Offset(
                  math.cos(-math.pi / 2 + k * 2 * math.pi / 5),
                  math.sin(-math.pi / 2 + k * 2 * math.pi / 5) * 0.8,
                ) *
                r,
    ];
    Offset mid(int i) => (pts[i % 5] + pts[(i + 1) % 5]) / 2;
    final path = Path()..moveTo(mid(0).dx, mid(0).dy);
    for (var k = 1; k <= 5; k++) {
      final v = pts[k % 5];
      final m = mid(k);
      path.quadraticBezierTo(v.dx, v.dy, m.dx, m.dy);
    }
    path.close();
    final bounds = Rect.fromCircle(center: c, radius: r);
    canvas.drawPath(
      path,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.5),
          radius: 0.9,
          colors: [Color(0xFFB3A390), _shell, _shellDark],
          stops: [0.0, 0.55, 1.0],
        ).createShader(bounds),
    );
    // Rocky texture.
    final rnd = math.Random(7);
    final spot = Paint();
    canvas.save();
    canvas.clipPath(path);
    for (var i = 0; i < 14; i++) {
      final o =
          c +
          Offset(
            (rnd.nextDouble() - 0.5) * 1.6 * r,
            (rnd.nextDouble() - 0.5) * 1.3 * r,
          );
      spot.color = (i.isEven ? _shellDark : const Color(0xFFC4B5A2)).withValues(
        alpha: 0.35,
      );
      canvas.drawCircle(o, r * (0.05 + rnd.nextDouble() * 0.09), spot);
    }
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _shellDark,
    );
  }

  void _paintVoice(Canvas canvas, Offset c, double r) {
    // Eridians have no eyes or mouth: the voice comes from a vent on top.
    final vent = c + Offset(0, -r * 0.42);
    canvas.drawOval(
      Rect.fromCenter(
        center: vent,
        width: r * 0.42,
        height: r * (0.1 + 0.1 * talk),
      ),
      Paint()..color = const Color(0xFF2A221C),
    );
    if (talk < 0.02) return;

    // Sound rings.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var k = 0; k < 3; k++) {
      final phase = (t * 1.6 + k / 3) % 1.0;
      ring.color = const Color(0xFFFFE0B0)
          .withValues(alpha: (1 - phase) * 0.55 * talk);
      final rr = r * (0.3 + phase * 0.9);
      canvas.drawArc(
        Rect.fromCircle(center: vent, radius: rr),
        -math.pi * 0.85,
        math.pi * 0.7,
        false,
        ring,
      );
    }

    // Colored note bubbles float up, one per note in the word.
    if (sounds.isEmpty) return;
    final dot = Paint();
    for (var i = 0; i < sounds.length; i++) {
      final age = talkTime - i * 0.25;
      if (age < 0 || age > 1.6) continue;
      final p = age / 1.6;
      final side = (i.isEven ? -1 : 1) * (0.25 + 0.15 * i) * r;
      final o =
          vent +
          Offset(
            side * p + math.sin(age * 6) * r * 0.05,
            -p * r * 1.3 - r * 0.15,
          );
      dot.color = noteColors[sounds[i].note].withValues(alpha: 1 - p);
      canvas.drawCircle(o, r * (0.09 + (sounds[i].long ? 0.05 : 0)), dot);
    }
  }

  @override
  bool shouldRepaint(covariant RockyPainter old) => true;
}
