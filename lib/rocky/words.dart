/// Rocky's vocabulary. Eridians talk in chords, so every word here is a
/// short run of notes from a five-note scale (0 = lowest, 4 = highest).
library;

class Syllable {
  const Syllable(this.note, this.long);
  final int note; // 0..4
  final bool long;
}

class EridianWord {
  const EridianWord(this.english, this.pattern, this.level, this.hint);

  final String english;

  /// Notes as digits, `_` after a digit makes that note long: '1_3' is a
  /// long 1 followed by a short 3.
  final String pattern;

  /// The level that unlocks this word.
  final int level;

  /// A short tip shown in the word list.
  final String hint;

  List<Syllable> get sounds {
    final out = <Syllable>[];
    for (var i = 0; i < pattern.length; i++) {
      final note = int.parse(pattern[i]);
      final long = i + 1 < pattern.length && pattern[i + 1] == '_';
      if (long) i++;
      out.add(Syllable(note, long));
    }
    return out;
  }
}

const int maxLevel = 6;

const List<EridianWord> eridianWords = [
  // Level 1: the basics.
  EridianWord('yes', '24', 1, 'Two notes going up.'),
  EridianWord('no', '42', 1, 'The opposite of yes: two notes going down.'),
  EridianWord('good', '024', 1, 'Climbs all the way up.'),
  EridianWord('bad', '420', 1, 'Falls all the way down.'),
  // Level 2: getting friendly.
  EridianWord('friend', '1_3_', 2, 'Two long, warm notes.'),
  EridianWord(
    'question',
    '04_',
    2,
    'Rocky puts this at the end of a sentence to ask something.',
  ),
  EridianWord(
    'amaze',
    '444',
    2,
    'Usually said three times: amaze amaze amaze!',
  ),
  EridianWord('help', '2_0', 2, 'A long note, then a drop.'),
  // Level 3: who and where.
  EridianWord('human', '13', 3, 'What Rocky calls Grace\'s kind.'),
  EridianWord('Rocky', '31_', 3, 'His name, as Grace hears it.'),
  EridianWord('star', '4_', 3, 'One long high note.'),
  EridianWord('ship', '303', 3, 'Bounces on a middle note.'),
  // Level 4: the science.
  EridianWord('Astrophage', '0123', 4, 'Four steps up, like it is growing.'),
  EridianWord('Taumoeba', '3210', 4, 'Four steps down: it eats Astrophage.'),
  EridianWord('science', '141', 4, 'Low, high, low.'),
  EridianWord('danger', '0_0_', 4, 'Two long low warnings.'),
  // Level 5: feelings.
  EridianWord('happy', '234', 5, 'Three bright steps up.'),
  EridianWord('sad', '1_0_', 5, 'Two long notes sinking.'),
  EridianWord('sleep', '21_', 5, 'Drifts down and holds.'),
  EridianWord('food', '12', 5, 'A quick little step up.'),
  // Level 6: home.
  EridianWord('fist my bump', '404', 6, 'Rocky\'s favorite human greeting.'),
  EridianWord('home', '03', 6, 'A jump up from the bottom.'),
  EridianWord('Earth', '30', 6, 'A jump down to the bottom.'),
  EridianWord('Erid', '0_3_', 6, 'Rocky\'s planet: two long notes.'),
];

EridianWord wordFor(String english) =>
    eridianWords.firstWhere((w) => w.english == english);
