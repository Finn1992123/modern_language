import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'assignment_session.dart';
import 'assignment_word_preview.dart';

enum HangmanMode { solo, versus }

class _LevelOption {
  const _LevelOption(this.label, this.databaseLevel);

  final String label;
  final String databaseLevel;
}

const _levelOptions = <_LevelOption>[
  _LevelOption('Junior A', 'Pre-A1'),
  _LevelOption('Junior B', 'A1'),
  _LevelOption('Senior A', 'A1'),
  _LevelOption('Senior B', 'A2'),
  _LevelOption('Senior C', 'A2'),
  _LevelOption('Senior D', 'B1'),
  _LevelOption('Pre-Lower', 'B1+'),
  _LevelOption('Lower', 'B2'),
  _LevelOption('Advanced', 'C1'),
  _LevelOption('Proficiency', 'C2'),
];

class HangmanHomePage extends StatefulWidget {
  const HangmanHomePage({
    super.key,
    required this.studentId,
    required this.classId,
    required this.languageLabel,
    this.assignmentSession,
  });

  final String studentId;
  final String classId;
  final String languageLabel;
  final AssignmentSession? assignmentSession;

  @override
  State<HangmanHomePage> createState() => _HangmanHomePageState();
}

class _HangmanHomePageState extends State<HangmanHomePage> {
  _LevelOption? _selectedLevel;
  late final Future<List<AssignmentPreviewWord>>? _assignmentWordsFuture;
  bool _startingAssignment = false;

  @override
  void initState() {
    super.initState();
    _assignmentWordsFuture = widget.assignmentSession == null
        ? null
        : _loadAssignmentWords(widget.assignmentSession!);
  }

  Future<List<AssignmentPreviewWord>> _loadAssignmentWords(
    AssignmentSession session,
  ) async {
    final usesPersonalWords =
        session.settings['personal_words'] == true ||
        session.settings['unit'] == '__personal__';
    final rows = usesPersonalWords
        ? await Supabase.instance.client.rpc(
            'get_student_assignment_vocabulary_words',
            params: {
              'input_assignment_id': session.assignmentId,
              'input_student_id': session.studentId,
              'input_class_id': session.classId,
            },
          )
        : await Supabase.instance.client.rpc(
            'get_student_study_vocabulary',
            params: {
              'input_student_id': session.studentId,
              'input_class_id': session.classId,
            },
          );
    if (rows is! List) return const [];

    final unit = session.settings['unit']?.toString().trim() ?? '';
    final level = session.settings['level']?.toString().trim() ?? '';
    final unitOrder = (session.settings['unit_order'] as num?)?.toInt();
    final completedWords = session.completedSourceKeys
        .map((word) => word.trim().toUpperCase())
        .toSet();
    final uniqueWords = <String, AssignmentPreviewWord>{};
    for (final value in rows) {
      if (value is! Map) continue;
      final row = Map<String, dynamic>.from(value);
      final word = row['word']?.toString().trim() ?? '';
      final translation = row['translation_gr']?.toString().trim() ?? '';
      final rowUnit = row['unit']?.toString().trim() ?? '';
      final rowLevel = row['level']?.toString().trim() ?? '';
      final rowUnitOrder = (row['unit_order'] as num?)?.toInt();
      final normalizedWord = word.toUpperCase();
      final characters = normalizedWord.split('');
      final letterCount = characters
          .where((character) => RegExp(r'^[A-Z]$').hasMatch(character))
          .length;
      final isPlayable = characters.every(
        (character) =>
            RegExp(r'^[A-Z]$').hasMatch(character) || " -'".contains(character),
      );
      if (word.isEmpty || letterCount < 2 || !isPlayable) continue;
      if (!usesPersonalWords) {
        if (unit.isNotEmpty && rowUnit != unit) continue;
        if (level.isNotEmpty && rowLevel != level) continue;
        if (unitOrder != null && rowUnitOrder != unitOrder) continue;
      }
      if (completedWords.contains(normalizedWord)) continue;
      uniqueWords.putIfAbsent(
        normalizedWord,
        () => AssignmentPreviewWord(
          id: row['id']?.toString() ?? word,
          word: word,
          translation: translation.isEmpty ? '—' : translation,
          partOfSpeech: row['part_of_speech']?.toString().trim(),
        ),
      );
    }
    return uniqueWords.values.toList();
  }

  Future<void> _startAssignment(List<AssignmentPreviewWord> words) async {
    final session = widget.assignmentSession;
    if (session == null || _startingAssignment) return;
    setState(() => _startingAssignment = true);
    final level = session.settings['level']?.toString() ?? '';
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _HangmanGamePage(
          level: _LevelOption(level, level),
          mode: HangmanMode.solo,
          languageLabel: widget.languageLabel,
          studentId: widget.studentId,
          classId: widget.classId,
          unit: session.settings['unit']?.toString(),
          assignmentSession: session,
          assignmentWords: words,
        ),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  void _start(HangmanMode mode) {
    final level = _selectedLevel;
    if (level == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Επίλεξε πρώτα ένα επίπεδο.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _HangmanGamePage(
          level: level,
          mode: mode,
          languageLabel: widget.languageLabel,
          studentId: widget.studentId,
          classId: widget.classId,
          unit: null,
          assignmentSession: null,
          assignmentWords: null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assignmentWordsFuture = _assignmentWordsFuture;
    if (assignmentWordsFuture != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F7FF),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          title: const Text(
            'Προετοιμασία Hangman',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          centerTitle: true,
        ),
        body: FutureBuilder<List<AssignmentPreviewWord>>(
          future: assignmentWordsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || (snapshot.data?.isEmpty ?? true)) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text(
                    'Δεν μπορέσαμε να φορτώσουμε τις λέξεις της άσκησης.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final words = snapshot.data!;
            return SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                children: [
                  AssignmentWordPreview(
                    words: words,
                    onCompleted: () => _startAssignment(words),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 74,
        leadingWidth: 78,
        leading: Padding(
          padding: const EdgeInsets.only(left: 14, top: 8, bottom: 8),
          child: Material(
            color: Colors.white.withValues(alpha: 0.92),
            shape: const CircleBorder(),
            elevation: 6,
            shadowColor: const Color(0x26D52323),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              customBorder: const CircleBorder(),
              child: const SizedBox(
                width: 58,
                height: 58,
                child: Icon(
                  Icons.close_rounded,
                  color: Color(0xFFE32636),
                  size: 43,
                  weight: 900,
                ),
              ),
            ),
          ),
        ),
        title: const Text(
          'Κρεμάλα',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Center(
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(36),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A4D4AAD),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Transform.scale(
                  scale: 1.3,
                  alignment: Alignment.center,
                  child: Image.asset(
                    'lib/img/hangmanicon.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Επίπεδο',
              style: TextStyle(
                color: Color(0xFF29265F),
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                for (final level in _levelOptions)
                  ChoiceChip(
                    label: Text(level.label),
                    selected: identical(_selectedLevel, level),
                    onSelected: (_) => setState(() => _selectedLevel = level),
                    selectedColor: const Color(0xFF4D4AAD),
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: identical(_selectedLevel, level)
                          ? const Color(0xFF4D4AAD)
                          : const Color(0xFFD9D7F2),
                    ),
                    labelStyle: TextStyle(
                      color: identical(_selectedLevel, level)
                          ? Colors.white
                          : const Color(0xFF4D4AAD),
                      fontWeight: FontWeight.w800,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            _ModeButton(
              label: 'Play alone',
              icon: Icons.person_rounded,
              color: const Color(0xFF18A8EF),
              onPressed: () => _start(HangmanMode.solo),
            ),
            const SizedBox(height: 12),
            _ModeButton(
              label: '1 vs 1',
              icon: Icons.people_alt_rounded,
              color: const Color(0xFF4D4AAD),
              onPressed: () => _start(HangmanMode.versus),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 27),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        minimumSize: const Size.fromHeight(58),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _HangmanGamePage extends StatefulWidget {
  const _HangmanGamePage({
    required this.level,
    required this.mode,
    required this.languageLabel,
    required this.studentId,
    required this.classId,
    required this.unit,
    required this.assignmentSession,
    required this.assignmentWords,
  });

  final _LevelOption level;
  final HangmanMode mode;
  final String languageLabel;
  final String studentId;
  final String classId;
  final String? unit;
  final AssignmentSession? assignmentSession;
  final List<AssignmentPreviewWord>? assignmentWords;

  @override
  State<_HangmanGamePage> createState() => _HangmanGamePageState();
}

class _HangmanGamePageState extends State<_HangmanGamePage> {
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  final _random = Random();

  late Future<List<AssignmentPreviewWord>> _wordsFuture = _loadWords();
  List<AssignmentPreviewWord> _words = const [];
  int _wordIndex = 0;
  Set<int> _revealedPositions = <int>{};
  Set<String> _guessedLetters = <String>{};
  List<String> _wrongLetters = <String>[];
  int _mistakes = 0;
  int _soloScore = 0;
  int _activePlayer = 0;
  final List<int> _playerScores = [0, 0];
  bool _changingWord = false;
  bool _gameFinished = false;
  Timer? _nextWordTimer;
  late int _assignmentProgress = widget.assignmentSession?.progressValue ?? 0;

  String get _currentWord => _words[_wordIndex].word;

  @override
  void dispose() {
    _nextWordTimer?.cancel();
    super.dispose();
  }

  Future<List<AssignmentPreviewWord>> _loadWords() async {
    final assignmentWords = widget.assignmentWords;
    if (assignmentWords != null) {
      final completedWords =
          widget.assignmentSession?.completedSourceKeys
              .map((word) => word.trim().toUpperCase())
              .toSet() ??
          const <String>{};
      final words = assignmentWords
          .map(
            (word) => AssignmentPreviewWord(
              id: word.id,
              word: word.word.trim().toUpperCase(),
              translation: word.translation,
              partOfSpeech: word.partOfSpeech,
            ),
          )
          .where(
            (word) =>
                !completedWords.contains(word.word) &&
                word.word.split('').where(_isLetter).length >= 2 &&
                word.word.split('').every(_isPlayableCharacter),
          )
          .toList();
      return words..shuffle(_random);
    }

    final rows = await Supabase.instance.client.rpc(
      'get_student_study_vocabulary',
      params: {
        'input_student_id': widget.studentId,
        'input_class_id': widget.classId,
      },
    );
    if (rows is! List) return const [];
    final uniqueWords = <String, AssignmentPreviewWord>{};
    for (final value in rows) {
      if (value is! Map) continue;
      final row = Map<String, dynamic>.from(value);
      final word = row['word']?.toString().trim().toUpperCase() ?? '';
      final language = row['language']?.toString().trim() ?? '';
      final level = row['level']?.toString().trim() ?? '';
      if (level != widget.level.databaseLevel) continue;
      if (widget.languageLabel.trim().isNotEmpty &&
          language.toLowerCase() != widget.languageLabel.trim().toLowerCase()) {
        continue;
      }
      final letters = word.split('').where(_isLetter).length;
      if (letters >= 2 && word.split('').every(_isPlayableCharacter)) {
        uniqueWords.putIfAbsent(
          word,
          () => AssignmentPreviewWord(
            id: row['id']?.toString() ?? '',
            word: word,
            translation: row['translation_gr']?.toString().trim() ?? '',
            partOfSpeech: row['part_of_speech']?.toString().trim(),
          ),
        );
      }
    }

    return uniqueWords.values.toList()..shuffle(_random);
  }

  static bool _isLetter(String character) {
    return RegExp(r'^[A-Z]$').hasMatch(character);
  }

  static bool _isPlayableCharacter(String character) {
    return _isLetter(character) || " -'".contains(character);
  }

  void _initializeGame(List<AssignmentPreviewWord> words) {
    _words = words;
    _wordIndex = 0;
    _soloScore = 0;
    _activePlayer = 0;
    _playerScores
      ..clear()
      ..addAll([0, 0]);
    _gameFinished = false;
    _prepareWord();
  }

  void _prepareWord() {
    final characters = _currentWord.split('');
    _revealedPositions = {
      for (var i = 0; i < characters.length; i++)
        if (!_isLetter(characters[i])) i,
    };
    final firstLetterIndex = characters.indexWhere(_isLetter);
    if (firstLetterIndex >= 0) {
      _revealedPositions.add(firstLetterIndex);
    }
    _guessedLetters = <String>{};
    _wrongLetters = <String>[];
    _mistakes = 0;
    _changingWord = false;
  }

  void _selectLetter(String letter) {
    if (_changingWord || _gameFinished || _guessedLetters.contains(letter)) {
      return;
    }

    final characters = _currentWord.split('');
    final matches = <int>{
      for (var i = 0; i < characters.length; i++)
        if (characters[i] == letter) i,
    };

    setState(() {
      _guessedLetters.add(letter);
      if (matches.isEmpty) {
        _wrongLetters.add(letter);
        _mistakes++;
      } else {
        _revealedPositions.addAll(matches);
      }
    });

    if (_mistakes >= 6) {
      _finishGame();
    } else if (_wordSolved) {
      _completeWord();
    }
  }

  bool get _wordSolved {
    final characters = _currentWord.split('');
    for (var i = 0; i < characters.length; i++) {
      if (_isLetter(characters[i]) && !_revealedPositions.contains(i)) {
        return false;
      }
    }
    return true;
  }

  void _completeWord() {
    final completedWord = _currentWord;
    setState(() {
      _changingWord = true;
      if (widget.mode == HangmanMode.solo) {
        _soloScore++;
      } else {
        _playerScores[_activePlayer]++;
      }
    });

    final session = widget.assignmentSession;
    if (session != null) {
      if (session.settings['personal_words'] == true ||
          session.settings['unit'] == '__personal__') {
        unawaited(_recordPersonalWordSuccess(_words[_wordIndex].id));
      }
      _assignmentProgress++;
      final reachedTarget = _assignmentProgress >= session.targetValue;
      unawaited(
        session
            .saveProgress(
              progress: _assignmentProgress,
              scorePercentage:
                  (_assignmentProgress / session.targetValue) * 100,
              finishAttempt: false,
              sourceKey: completedWord,
            )
            .then((passed) {
              if (!mounted || (!passed && !reachedTarget)) return;
              _showAssignmentSuccess();
            })
            .catchError((Object error) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Δεν αποθηκεύτηκε η λέξη: $error')),
                );
              }
            }),
      );
      if (reachedTarget) {
        _gameFinished = true;
        return;
      }
    }

    _nextWordTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted || _gameFinished) {
        return;
      }
      setState(() {
        _wordIndex++;
        if (_wordIndex >= _words.length) {
          _words.shuffle(_random);
          _wordIndex = 0;
        }
        if (widget.mode == HangmanMode.versus) {
          _activePlayer = 1 - _activePlayer;
        }
        _prepareWord();
      });
    });
  }

  void _finishGame() {
    _gameFinished = true;
    if (widget.mode == HangmanMode.solo) {
      unawaited(_recordHangmanMistake());
    }
    final assignmentSession = widget.assignmentSession;
    final assignmentFinishFuture = assignmentSession?.saveProgress(
      progress: _assignmentProgress,
      scorePercentage:
          (_assignmentProgress / assignmentSession.targetValue) * 100,
      finishAttempt: true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final versus = widget.mode == HangmanMode.versus;
          final winner = 2 - _activePlayer;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
            icon: Icon(
              versus
                  ? Icons.emoji_events_rounded
                  : Icons.sentiment_dissatisfied,
              size: 54,
              color: versus ? const Color(0xFFFFB300) : const Color(0xFFE74C3C),
            ),
            title: Text(
              versus ? 'Congratulations Player $winner!' : 'You lost',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            content: Text(
              versus
                  ? 'Player $winner wins ${_playerScores[winner - 1]} - ${_playerScores[_activePlayer]}.'
                  : 'Η λέξη ήταν $_currentWord.\nScore: $_soloScore',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              OutlinedButton.icon(
                onPressed: () async {
                  await assignmentFinishFuture;
                  if (!dialogContext.mounted || !mounted) return;
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.home_rounded),
                label: const Text('Home'),
              ),
              if (assignmentSession == null)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    setState(() {
                      _words.shuffle(_random);
                      _initializeGame(_words);
                    });
                  },
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Retry'),
                ),
            ],
          );
        },
      );
    });
  }

  Future<void> _recordHangmanMistake() async {
    if (widget.assignmentSession == null) return;
    final word = _words[_wordIndex];
    if (word.id.isEmpty) return;
    try {
      await Supabase.instance.client.rpc(
        'record_student_vocabulary_mistake',
        params: {
          'input_student_id': widget.studentId,
          'input_class_id': widget.classId,
          'input_vocabulary_word_id': word.id,
          'input_source': 'hangman',
          'input_wrong_answer': null,
        },
      );
    } catch (_) {
      // Η αποθήκευση της λανθασμένης λέξης δεν διακόπτει το παιχνίδι.
    }
  }

  Future<void> _recordPersonalWordSuccess(String vocabularyWordId) async {
    final session = widget.assignmentSession;
    if (session == null || vocabularyWordId.isEmpty) return;
    try {
      await Supabase.instance.client.rpc(
        'record_personal_vocabulary_assignment_successes',
        params: {
          'input_assignment_id': session.assignmentId,
          'input_student_id': widget.studentId,
          'input_class_id': widget.classId,
          'input_vocabulary_word_ids': [vocabularyWordId],
        },
      );
    } catch (_) {
      // Η πρόοδος της άσκησης δεν διακόπτεται αν αποτύχει ο συγχρονισμός.
    }
  }

  void _showAssignmentSuccess() {
    _gameFinished = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.emoji_events_rounded,
          color: Color(0xFFFFB300),
          size: 58,
        ),
        title: const Text(
          'Η άσκηση ολοκληρώθηκε!',
          textAlign: TextAlign.center,
        ),
        content: Text(
          'Βρήκες $_assignmentProgress/${widget.assignmentSession!.targetValue} λέξεις.\n'
          'Βαθμός: 100%',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Επιστροφή στις ασκήσεις'),
          ),
        ],
      ),
    );
  }

  void _retryLoading() {
    setState(() {
      _wordsFuture = _loadWords();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text(
          widget.level.label,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<List<AssignmentPreviewWord>>(
        future: _wordsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _LoadProblem(
              message: 'Δεν μπορέσαμε να φορτώσουμε τις λέξεις.',
              onRetry: _retryLoading,
            );
          }
          final words = snapshot.data ?? const <AssignmentPreviewWord>[];
          if (words.isEmpty) {
            return _LoadProblem(
              message:
                  'Δεν βρέθηκαν ενεργές λέξεις για ${widget.level.databaseLevel}.',
              onRetry: _retryLoading,
            );
          }
          if (_words.isEmpty) {
            _initializeGame(words);
          }
          return _buildGame();
        },
      ),
    );
  }

  Widget _buildGame() {
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (widget.mode == HangmanMode.solo)
            Align(
              alignment: Alignment.centerRight,
              child: _ScorePill(label: 'Score', score: _soloScore),
            )
          else
            _VersusScoreboard(
              activePlayer: _activePlayer,
              scores: _playerScores,
            ),
          const SizedBox(height: 10),
          Container(
            height: 225,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x164D4AAD),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: _mistakes.toDouble()),
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutBack,
                    builder: (context, value, child) => CustomPaint(
                      painter: HangmanPainter(mistakes: value),
                      size: Size.infinite,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Wrong',
                        style: TextStyle(
                          color: Color(0xFF77739C),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          for (final letter in _wrongLetters)
                            Text(
                              letter,
                              style: const TextStyle(
                                color: Color(0xFFE74C3C),
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _WordDisplay(
            word: _currentWord,
            revealedPositions: _revealedPositions,
          ),
          const SizedBox(height: 22),
          if (_changingWord)
            const Center(
              child: Text(
                'Great! Next word…',
                style: TextStyle(
                  color: Color(0xFF18A8EF),
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            )
          else
            _Keyboard(
              alphabet: _alphabet,
              selectedLetters: _guessedLetters,
              wrongLetters: _wrongLetters.toSet(),
              onLetterPressed: _selectLetter,
            ),
        ],
      ),
    );
  }
}

class _LoadProblem extends StatelessWidget {
  const _LoadProblem({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 52),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Δοκιμή ξανά'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.label, required this.score});

  final String label;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF4D4AAD),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '$label  $score',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _VersusScoreboard extends StatelessWidget {
  const _VersusScoreboard({required this.activePlayer, required this.scores});

  final int activePlayer;
  final List<int> scores;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PlayerScore(
            name: 'Player 1',
            score: scores[0],
            active: activePlayer == 0,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'VS',
            style: TextStyle(
              color: Color(0xFF77739C),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Expanded(
          child: _PlayerScore(
            name: 'Player 2',
            score: scores[1],
            active: activePlayer == 1,
          ),
        ),
      ],
    );
  }
}

class _PlayerScore extends StatelessWidget {
  const _PlayerScore({
    required this.name,
    required this.score,
    required this.active,
  });

  final String name;
  final int score;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF4D4AAD) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD9D7F2)),
      ),
      child: Column(
        children: [
          Text(
            name,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFF4D4AAD),
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            '$score',
            style: TextStyle(
              color: active ? const Color(0xFF65D3FF) : const Color(0xFF18A8EF),
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _WordDisplay extends StatelessWidget {
  const _WordDisplay({required this.word, required this.revealedPositions});

  final String word;
  final Set<int> revealedPositions;

  @override
  Widget build(BuildContext context) {
    final characters = word.split('');
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 12,
      children: [
        for (var i = 0; i < characters.length; i++)
          if (characters[i] == ' ')
            const SizedBox(width: 18, height: 42)
          else
            SizedBox(
              width: 28,
              height: 42,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(
                              scale: CurvedAnimation(
                                parent: animation,
                                curve: Curves.elasticOut,
                              ),
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            ),
                        child: Text(
                          revealedPositions.contains(i) ? characters[i] : '',
                          key: ValueKey(revealedPositions.contains(i)),
                          style: const TextStyle(
                            color: Color(0xFF29265F),
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4D4AAD),
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _Keyboard extends StatelessWidget {
  const _Keyboard({
    required this.alphabet,
    required this.selectedLetters,
    required this.wrongLetters,
    required this.onLetterPressed,
  });

  final String alphabet;
  final Set<String> selectedLetters;
  final Set<String> wrongLetters;
  final ValueChanged<String> onLetterPressed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final keyWidth = ((constraints.maxWidth - 48) / 7).clamp(34.0, 48.0);
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 9,
          children: [
            for (final letter in alphabet.split(''))
              SizedBox(
                width: keyWidth,
                height: 46,
                child: FilledButton(
                  onPressed: selectedLetters.contains(letter)
                      ? null
                      : () => onLetterPressed(letter),
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: const Color(0xFF4D4AAD),
                    disabledBackgroundColor: wrongLetters.contains(letter)
                        ? const Color(0xFFF3B4AD)
                        : const Color(0xFFDAD8EA),
                    disabledForegroundColor: wrongLetters.contains(letter)
                        ? const Color(0xFFA9271A)
                        : const Color(0xFF77739C),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    letter,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class HangmanPainter extends CustomPainter {
  const HangmanPainter({required this.mistakes});

  final double mistakes;

  @override
  void paint(Canvas canvas, Size size) {
    final scaffold = Paint()
      ..color = const Color(0xFF9A5A25)
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final body = Paint()
      ..color = const Color(0xFF29265F)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final baseY = size.height * 0.9;
    final postX = size.width * 0.22;
    final topY = size.height * 0.12;
    final beamEndX = size.width * 0.72;
    final ropeEndY = size.height * 0.3;
    canvas.drawLine(
      Offset(size.width * 0.08, baseY),
      Offset(size.width * 0.75, baseY),
      scaffold,
    );
    canvas.drawLine(Offset(postX, baseY), Offset(postX, topY), scaffold);
    canvas.drawLine(Offset(postX, topY), Offset(beamEndX, topY), scaffold);
    canvas.drawLine(
      Offset(beamEndX, topY),
      Offset(beamEndX, ropeEndY),
      scaffold..strokeWidth = 5,
    );

    final headCenter = Offset(beamEndX, size.height * 0.39);
    final headRadius = size.shortestSide * 0.085;
    final headProgress = mistakes.clamp(0.0, 1.0);
    if (headProgress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: headCenter, radius: headRadius),
        -pi / 2,
        pi * 2 * headProgress,
        false,
        body,
      );
    }

    final neck = Offset(headCenter.dx, headCenter.dy + headRadius);
    final hip = Offset(headCenter.dx, size.height * 0.69);
    _drawAnimatedLine(canvas, body, neck, hip, _partProgress(2));
    _drawAnimatedLine(
      canvas,
      body,
      Offset(headCenter.dx, size.height * 0.51),
      Offset(size.width * 0.55, size.height * 0.62),
      _partProgress(3),
    );
    _drawAnimatedLine(
      canvas,
      body,
      Offset(headCenter.dx, size.height * 0.51),
      Offset(size.width * 0.88, size.height * 0.62),
      _partProgress(4),
    );
    _drawAnimatedLine(
      canvas,
      body,
      hip,
      Offset(size.width * 0.58, size.height * 0.84),
      _partProgress(5),
    );
    _drawAnimatedLine(
      canvas,
      body,
      hip,
      Offset(size.width * 0.83, size.height * 0.84),
      _partProgress(6),
    );
  }

  double _partProgress(int part) => (mistakes - (part - 1)).clamp(0.0, 1.0);

  void _drawAnimatedLine(
    Canvas canvas,
    Paint paint,
    Offset start,
    Offset end,
    double progress,
  ) {
    if (progress <= 0) {
      return;
    }
    canvas.drawLine(start, Offset.lerp(start, end, progress)!, paint);
  }

  @override
  bool shouldRepaint(covariant HangmanPainter oldDelegate) {
    return oldDelegate.mistakes != mistakes;
  }
}
