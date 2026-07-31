import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'assignment_session.dart';

enum IdentifyTheTenseMode { timeAttack, survival }

const _tenseLabels = <String>[
  'Present simple',
  'Present continuous',
  'Present perfect',
  'Present perfect continuous',
  'Past simple',
  'Past continuous',
  'Past perfect',
  'Past perfect continuous',
  'Future simple',
  'Future continuous',
  'Future perfect',
  'Future perfect continuous',
  'Passive voice',
  'Reported speech',
  'Conditional',
];

class IdentifyTheTenseHomePage extends StatefulWidget {
  const IdentifyTheTenseHomePage({
    super.key,
    required this.studentId,
    required this.classId,
    this.assignmentSession,
  });

  final String studentId;
  final String classId;
  final AssignmentSession? assignmentSession;

  @override
  State<IdentifyTheTenseHomePage> createState() =>
      _IdentifyTheTenseHomePageState();
}

class _IdentifyTheTenseHomePageState extends State<IdentifyTheTenseHomePage> {
  IdentifyTheTenseMode _leaderboardMode = IdentifyTheTenseMode.timeAttack;
  late Future<List<_LeaderboardEntry>> _leaderboardFuture = _loadLeaderboard();

  @override
  void initState() {
    super.initState();
    if (widget.assignmentSession != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startAssignment();
      });
    }
  }

  Future<void> _startAssignment() async {
    final session = widget.assignmentSession;
    if (session == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _IdentifyTheTenseGamePage(
          studentId: widget.studentId,
          classId: widget.classId,
          mode: IdentifyTheTenseMode.timeAttack,
          assignmentSession: session,
        ),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<List<_LeaderboardEntry>> _loadLeaderboard() async {
    final rows = await Supabase.instance.client.rpc(
      'get_tense_game_leaderboard',
      params: {'input_mode': _leaderboardMode.name, 'input_limit': 100},
    );
    if (rows is! List) {
      return const [];
    }
    return rows
        .whereType<Map>()
        .map((row) => _LeaderboardEntry.fromRow(Map<String, dynamic>.from(row)))
        .toList();
  }

  void _selectLeaderboardMode(IdentifyTheTenseMode mode) {
    if (_leaderboardMode == mode) {
      return;
    }
    setState(() {
      _leaderboardMode = mode;
      _leaderboardFuture = _loadLeaderboard();
    });
  }

  void _refreshLeaderboard() {
    setState(() {
      _leaderboardFuture = _loadLeaderboard();
    });
  }

  Future<void> _start(IdentifyTheTenseMode mode) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _IdentifyTheTenseGamePage(
          studentId: widget.studentId,
          classId: widget.classId,
          mode: mode,
          assignmentSession: null,
        ),
      ),
    );
    if (mounted) {
      _refreshLeaderboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 72,
        leadingWidth: 76,
        leading: Padding(
          padding: const EdgeInsets.only(left: 14, top: 7, bottom: 7),
          child: Material(
            color: Colors.white,
            elevation: 5,
            shadowColor: const Color(0x224D4AAD),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              customBorder: const CircleBorder(),
              child: const Icon(
                Icons.close_rounded,
                color: Color(0xFFE32636),
                size: 40,
              ),
            ),
          ),
        ),
        title: const Text(
          'Identify the tense',
          style: TextStyle(
            color: Color(0xFF29265F),
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            Center(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(38),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1F4D4AAD),
                      blurRadius: 26,
                      offset: Offset(0, 11),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'lib/img/identifythetense.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 38),
            _ModeButton(
              label: 'Time attack',
              subtitle: 'Βρες όσους περισσότερους χρόνους μπορείς σε 1 λεπτό',
              icon: Icons.timer_rounded,
              color: const Color(0xFF18A8EF),
              onPressed: () => _start(IdentifyTheTenseMode.timeAttack),
            ),
            const SizedBox(height: 16),
            _ModeButton(
              label: 'Survival',
              subtitle: 'Συνέχισε μέχρι την πρώτη λάθος απάντηση',
              icon: Icons.all_inclusive_rounded,
              color: const Color(0xFF4D4AAD),
              onPressed: () => _start(IdentifyTheTenseMode.survival),
            ),
            const SizedBox(height: 30),
            _LeaderboardPanel(
              selectedMode: _leaderboardMode,
              entriesFuture: _leaderboardFuture,
              currentStudentId: widget.studentId,
              onModeSelected: _selectLeaderboardMode,
              onRetry: _refreshLeaderboard,
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
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 42),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xE6FFFFFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white,
                size: 32,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaderboardPanel extends StatelessWidget {
  const _LeaderboardPanel({
    required this.selectedMode,
    required this.entriesFuture,
    required this.currentStudentId,
    required this.onModeSelected,
    required this.onRetry,
  });

  final IdentifyTheTenseMode selectedMode;
  final Future<List<_LeaderboardEntry>> entriesFuture;
  final String currentStudentId;
  final ValueChanged<IdentifyTheTenseMode> onModeSelected;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.leaderboard_rounded,
                color: Color(0xFFFFB300),
                size: 31,
              ),
              SizedBox(width: 8),
              Text(
                'Leaderboard',
                style: TextStyle(
                  color: Color(0xFF29265F),
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _LeaderboardModeButton(
                  label: 'Time attack',
                  selected: selectedMode == IdentifyTheTenseMode.timeAttack,
                  onTap: () => onModeSelected(IdentifyTheTenseMode.timeAttack),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _LeaderboardModeButton(
                  label: 'Survival',
                  selected: selectedMode == IdentifyTheTenseMode.survival,
                  onTap: () => onModeSelected(IdentifyTheTenseMode.survival),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FutureBuilder<List<_LeaderboardEntry>>(
            future: entriesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Column(
                    children: [
                      const Text(
                        'Δεν φορτώθηκε το leaderboard.',
                        style: TextStyle(
                          color: Color(0xFFA32121),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Δοκιμή ξανά'),
                      ),
                    ],
                  ),
                );
              }

              final entries = snapshot.data ?? const [];
              if (entries.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Δεν υπάρχει ακόμη σκορ σε αυτό το mode.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF77739C),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  for (var index = 0; index < entries.length; index++) ...[
                    _LeaderboardRow(
                      entry: entries[index],
                      isCurrentStudent:
                          entries[index].studentId == currentStudentId,
                    ),
                    if (index < entries.length - 1)
                      const Divider(height: 1, color: Color(0xFFE9E8F5)),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LeaderboardModeButton extends StatelessWidget {
  const _LeaderboardModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF4D4AAD) : const Color(0xFFF0EFFF),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF4D4AAD),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.entry, required this.isCurrentStudent});

  final _LeaderboardEntry entry;
  final bool isCurrentStudent;

  @override
  Widget build(BuildContext context) {
    final rankColor = switch (entry.rank) {
      1 => const Color(0xFFFFB300),
      2 => const Color(0xFF9CA7B8),
      3 => const Color(0xFFB87333),
      _ => const Color(0xFFE9E8F5),
    };
    final rankForeground = entry.rank <= 3
        ? Colors.white
        : const Color(0xFF4D4AAD);

    return Container(
      color: isCurrentStudent ? const Color(0xFFF3F1FF) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: rankColor, shape: BoxShape.circle),
            child: Text(
              '${entry.rank}',
              style: TextStyle(
                color: rankForeground,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _StudentAvatar(
            photoUrl: entry.profilePic,
            studentName: entry.studentName,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isCurrentStudent
                  ? '${entry.studentName} (Εσύ)'
                  : entry.studentName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF29265F),
                fontSize: 15,
                fontWeight: isCurrentStudent
                    ? FontWeight.w900
                    : FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${entry.score}',
            style: const TextStyle(
              color: Color(0xFF4D4AAD),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardEntry {
  const _LeaderboardEntry({
    required this.rank,
    required this.studentId,
    required this.studentName,
    required this.profilePic,
    required this.score,
  });

  factory _LeaderboardEntry.fromRow(Map<String, dynamic> row) {
    return _LeaderboardEntry(
      rank: row['rank'] is num ? (row['rank'] as num).toInt() : 0,
      studentId: row['student_id']?.toString() ?? '',
      studentName: row['student_name']?.toString().trim().isNotEmpty == true
          ? row['student_name'].toString().trim()
          : 'Μαθητής',
      profilePic: row['profile_pic']?.toString().trim().isNotEmpty == true
          ? row['profile_pic'].toString().trim()
          : null,
      score: row['score'] is num ? (row['score'] as num).toInt() : 0,
    );
  }

  final int rank;
  final String studentId;
  final String studentName;
  final String? profilePic;
  final int score;
}

class _StudentAvatar extends StatelessWidget {
  const _StudentAvatar({required this.photoUrl, required this.studentName});

  final String? photoUrl;
  final String studentName;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFE9E8F5),
        shape: BoxShape.circle,
      ),
      child: Text(
        studentName.trim().isEmpty ? '?' : studentName.trim()[0].toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF4D4AAD),
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );

    if (photoUrl == null) {
      return fallback;
    }

    return ClipOval(
      child: Image.network(
        photoUrl!,
        width: 42,
        height: 42,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}

class _IdentifyTheTenseGamePage extends StatefulWidget {
  const _IdentifyTheTenseGamePage({
    required this.studentId,
    required this.classId,
    required this.mode,
    required this.assignmentSession,
  });

  final String studentId;
  final String classId;
  final IdentifyTheTenseMode mode;
  final AssignmentSession? assignmentSession;

  @override
  State<_IdentifyTheTenseGamePage> createState() =>
      _IdentifyTheTenseGamePageState();
}

class _IdentifyTheTenseGamePageState extends State<_IdentifyTheTenseGamePage> {
  final Random _random = Random();
  List<_TenseQuestion> _questions = const [];
  List<String> _choices = const [];
  int _questionIndex = 0;
  int _score = 0;
  late int _secondsLeft = _isTimedAssignment
      ? widget.assignmentSession!.remainingSeconds
      : 60;
  int _answeredQuestions = 0;
  String? _selectedAnswer;
  Object? _loadError;
  bool _loading = true;
  bool _answerLocked = false;
  bool _finished = false;
  Future<void>? _scoreSaveFuture;
  Future<void>? _assignmentSaveFuture;
  Timer? _countdownTimer;
  Timer? _nextQuestionTimer;

  _TenseQuestion get _currentQuestion => _questions[_questionIndex];
  bool get _isTimedAssignment =>
      widget.assignmentSession?.settings['limit_type'] == 'time';
  bool get _isQuestionAssignment =>
      widget.assignmentSession?.settings['limit_type'] == 'questions';
  bool get _usesCountdown =>
      _isTimedAssignment ||
      (widget.assignmentSession == null &&
          widget.mode == IdentifyTheTenseMode.timeAttack);

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _nextQuestionTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    try {
      final rows = await Supabase.instance.client
          .from('tense_questions')
          .select('id, sentence, tense, highlight_phrases')
          .eq('language', 'English')
          .eq('is_active', true);
      final questions =
          (rows as List)
              .whereType<Map>()
              .map(
                (row) => _TenseQuestion.fromRow(Map<String, dynamic>.from(row)),
              )
              .where(
                (question) =>
                    question.sentence.isNotEmpty &&
                    _tenseLabels.contains(question.tense),
              )
              .toList()
            ..shuffle(_random);

      if (!mounted) {
        return;
      }
      setState(() {
        _questions = questions;
        _loading = false;
        if (questions.isNotEmpty) {
          _prepareChoices();
        }
      });
      if (questions.isNotEmpty && _usesCountdown) {
        _startCountdown();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _finished) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        setState(() => _secondsLeft = 0);
        timer.cancel();
        _finishGame();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  void _prepareChoices() {
    final correct = _currentQuestion.tense;
    final alternatives =
        _tenseLabels.where((tense) => tense != correct).toList()
          ..shuffle(_random);
    _choices = <String>[correct, ...alternatives.take(3)]..shuffle(_random);
  }

  void _selectAnswer(String answer) {
    if (_answerLocked || _finished) {
      return;
    }

    final correct = answer == _currentQuestion.tense;
    setState(() {
      _selectedAnswer = answer;
      _answerLocked = true;
      if (correct) {
        _score++;
      }
      _answeredQuestions++;
    });

    if (_isQuestionAssignment &&
        _answeredQuestions >= widget.assignmentSession!.targetValue) {
      _nextQuestionTimer = Timer(
        const Duration(milliseconds: 1500),
        _finishGame,
      );
      return;
    }

    if (!correct &&
        widget.assignmentSession == null &&
        widget.mode == IdentifyTheTenseMode.survival) {
      _nextQuestionTimer = Timer(
        const Duration(milliseconds: 1500),
        _finishGame,
      );
      return;
    }

    _nextQuestionTimer = Timer(
      const Duration(milliseconds: 1500),
      _moveToNextQuestion,
    );
  }

  void _moveToNextQuestion() {
    if (!mounted || _finished || _questions.isEmpty) {
      return;
    }
    setState(() {
      _questionIndex++;
      if (_questionIndex >= _questions.length) {
        _questions.shuffle(_random);
        _questionIndex = 0;
      }
      _selectedAnswer = null;
      _answerLocked = false;
      _prepareChoices();
    });
  }

  void _finishGame() {
    if (!mounted || _finished) {
      return;
    }
    _finished = true;
    _countdownTimer?.cancel();
    _nextQuestionTimer?.cancel();
    unawaited(_saveScore());
    unawaited(_saveAssignmentResult());
    _showResultDialog();
  }

  Future<void> _saveScore() {
    return _scoreSaveFuture ??= _persistScore();
  }

  Future<void> _persistScore() async {
    try {
      await Supabase.instance.client.rpc(
        'submit_tense_game_score',
        params: {
          'input_student_id': widget.studentId,
          'input_class_id': widget.classId,
          'input_mode': widget.mode.name,
          'input_score': _score,
        },
      );
    } catch (_) {
      // A result must never prevent the student from continuing the game.
    }
  }

  Future<void> _saveAssignmentResult() {
    return _assignmentSaveFuture ??= _persistAssignmentResult();
  }

  Future<void> _persistAssignmentResult() async {
    final session = widget.assignmentSession;
    if (session == null) return;
    final total = _answeredQuestions;
    final percentage = total == 0 ? 0.0 : (_score / total) * 100;
    try {
      await session.saveProgress(
        progress: _isTimedAssignment ? session.targetValue : total,
        scorePercentage: percentage,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Δεν αποθηκεύτηκε η προσπάθεια: $error')),
        );
      }
    }
  }

  Future<void> _showResultDialog() {
    final timeAttack = _usesCountdown;
    final percentage = _answeredQuestions == 0
        ? 0
        : ((_score / _answeredQuestions) * 100).round();
    final assignmentPassed =
        widget.assignmentSession == null || percentage >= 71;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          icon: Icon(
            timeAttack ? Icons.timer_off_rounded : Icons.emoji_events_rounded,
            size: 58,
            color: const Color(0xFF4D4AAD),
          ),
          title: Text(
            widget.assignmentSession == null
                ? (timeAttack ? 'Τέλος χρόνου!' : 'Τέλος παιχνιδιού!')
                : assignmentPassed
                ? 'Η άσκηση ολοκληρώθηκε!'
                : 'Χρειάζεται νέα προσπάθεια',
          ),
          content: Text(
            widget.assignmentSession == null
                ? 'Το σκορ σου είναι $_score'
                : 'Βαθμολογία: $percentage%\n'
                      'Απαιτείται τουλάχιστον 71%.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF29265F),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            if (widget.assignmentSession == null)
              OutlinedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _restartGame();
                },
                child: const Text('Προσπαθήστε ξανά'),
              ),
            FilledButton(
              onPressed: () async {
                await Future.wait([_saveScore(), _saveAssignmentResult()]);
                if (!dialogContext.mounted || !mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pop();
              },
              child: Text(
                widget.assignmentSession == null
                    ? 'Αρχική'
                    : 'Επιστροφή στις ασκήσεις',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _restartGame() {
    _questions.shuffle(_random);
    setState(() {
      _questionIndex = 0;
      _score = 0;
      _secondsLeft = _isTimedAssignment
          ? widget.assignmentSession!.remainingSeconds
          : 60;
      _answeredQuestions = 0;
      _selectedAnswer = null;
      _answerLocked = false;
      _finished = false;
      _scoreSaveFuture = null;
      _assignmentSaveFuture = null;
      _prepareChoices();
    });
    if (_usesCountdown) {
      _startCountdown();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? _GameStateMessage(
                icon: Icons.cloud_off_rounded,
                text: 'Δεν μπορέσαμε να φορτώσουμε τις προτάσεις.\n$_loadError',
                onBack: () => Navigator.of(context).pop(),
              )
            : _questions.isEmpty
            ? _GameStateMessage(
                icon: Icons.quiz_outlined,
                text: 'Δεν υπάρχουν ακόμη ενεργές προτάσεις στο Supabase.',
                onBack: () => Navigator.of(context).pop(),
              )
            : Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            constraints: const BoxConstraints(minHeight: 180),
                            padding: const EdgeInsets.all(24),
                            alignment: Alignment.center,
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
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: _HighlightedSentence(
                                key: ValueKey(
                                  '${_currentQuestion.id}:$_answerLocked',
                                ),
                                sentence: _currentQuestion.sentence,
                                highlightPhrases:
                                    _currentQuestion.highlightPhrases,
                                showHighlights: _answerLocked,
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          for (final choice in _choices) ...[
                            _AnswerButton(
                              label: choice,
                              selected: _selectedAnswer == choice,
                              correct: _answerLocked
                                  ? choice == _currentQuestion.tense
                                  : null,
                              onTap: () => _selectAnswer(choice),
                            ),
                            const SizedBox(height: 11),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildTopBar() {
    final timeAttack = _usesCountdown;
    return SizedBox(
      height: 82,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  color: const Color(0xFF4D4AAD),
                ),
              ),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    timeAttack
                        ? Icons.timer_rounded
                        : Icons.all_inclusive_rounded,
                    color: const Color(0xFF18A8EF),
                    size: timeAttack ? 34 : 42,
                  ),
                  if (timeAttack) ...[
                    const SizedBox(width: 5),
                    Text(
                      '${(_secondsLeft ~/ 60).toString().padLeft(2, '0')}:'
                      '${(_secondsLeft % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: _secondsLeft <= 10
                            ? const Color(0xFFE32636)
                            : const Color(0xFF29265F),
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ] else if (_isQuestionAssignment) ...[
                    const SizedBox(width: 5),
                    Text(
                      '$_answeredQuestions/${widget.assignmentSession!.targetValue}',
                      style: const TextStyle(
                        color: Color(0xFF29265F),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'SCORE',
                        style: TextStyle(
                          color: Color(0xFF77739C),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '$_score',
                        style: const TextStyle(
                          color: Color(0xFF4D4AAD),
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.label,
    required this.selected,
    required this.correct,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool? correct;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var background = Colors.white;
    var foreground = const Color(0xFF29265F);
    var border = const Color(0xFFD9D7F2);
    if (correct == true) {
      background = const Color(0xFFE4FBDC);
      foreground = const Color(0xFF24710E);
      border = const Color(0xFF65C84A);
    } else if (selected && correct == false) {
      background = const Color(0xFFFFE1E1);
      foreground = const Color(0xFFA32121);
      border = const Color(0xFFE45A5A);
    }

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: correct == null ? onTap : null,
        borderRadius: BorderRadius.circular(17),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: border, width: 2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (correct == true)
                const Icon(Icons.check_circle_rounded, color: Color(0xFF43A52A))
              else if (selected && correct == false)
                const Icon(Icons.cancel_rounded, color: Color(0xFFD43C3C)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightedSentence extends StatelessWidget {
  const _HighlightedSentence({
    super.key,
    required this.sentence,
    required this.highlightPhrases,
    required this.showHighlights,
  });

  final String sentence;
  final List<String> highlightPhrases;
  final bool showHighlights;

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(
      color: Color(0xFF29265F),
      fontSize: 27,
      fontWeight: FontWeight.w800,
      height: 1.35,
    );
    if (!showHighlights || highlightPhrases.isEmpty) {
      return Text(sentence, textAlign: TextAlign.center, style: baseStyle);
    }

    final ranges = _findHighlightRanges(sentence, highlightPhrases);
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final range in ranges) {
      if (range.start > cursor) {
        spans.add(TextSpan(text: sentence.substring(cursor, range.start)));
      }
      spans.add(
        TextSpan(
          text: sentence.substring(range.start, range.end),
          style: const TextStyle(
            color: Color(0xFF342A00),
            backgroundColor: Color(0xFFFFE56B),
            fontWeight: FontWeight.w900,
          ),
        ),
      );
      cursor = range.end;
    }
    if (cursor < sentence.length) {
      spans.add(TextSpan(text: sentence.substring(cursor)));
    }

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(style: baseStyle, children: spans),
    );
  }
}

List<_TextRange> _findHighlightRanges(String sentence, List<String> phrases) {
  final lowerSentence = sentence.toLowerCase();
  final ranges = <_TextRange>[];
  for (final rawPhrase in phrases) {
    final phrase = rawPhrase.trim().toLowerCase();
    if (phrase.isEmpty) {
      continue;
    }
    var from = 0;
    while (from < lowerSentence.length) {
      final start = lowerSentence.indexOf(phrase, from);
      if (start < 0) {
        break;
      }
      ranges.add(_TextRange(start, start + phrase.length));
      from = start + phrase.length;
    }
  }
  ranges.sort((a, b) => a.start.compareTo(b.start));

  final merged = <_TextRange>[];
  for (final range in ranges) {
    if (merged.isEmpty || range.start > merged.last.end) {
      merged.add(range);
    } else if (range.end > merged.last.end) {
      merged[merged.length - 1] = _TextRange(merged.last.start, range.end);
    }
  }
  return merged;
}

class _TextRange {
  const _TextRange(this.start, this.end);

  final int start;
  final int end;
}

class _TenseQuestion {
  const _TenseQuestion({
    required this.id,
    required this.sentence,
    required this.tense,
    required this.highlightPhrases,
  });

  factory _TenseQuestion.fromRow(Map<String, dynamic> row) {
    final rawPhrases = row['highlight_phrases'];
    return _TenseQuestion(
      id: row['id']?.toString() ?? '',
      sentence: row['sentence']?.toString().trim() ?? '',
      tense: row['tense']?.toString().trim() ?? '',
      highlightPhrases: rawPhrases is List
          ? rawPhrases
                .map((phrase) => phrase.toString().trim())
                .where((phrase) => phrase.isNotEmpty)
                .toList()
          : const [],
    );
  }

  final String id;
  final String sentence;
  final String tense;
  final List<String> highlightPhrases;
}

class _GameStateMessage extends StatelessWidget {
  const _GameStateMessage({
    required this.icon,
    required this.text,
    required this.onBack,
  });

  final IconData icon;
  final String text;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
            ),
          ),
          const Spacer(),
          Icon(icon, color: const Color(0xFF4D4AAD), size: 62),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF29265F),
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
