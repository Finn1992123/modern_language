import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'assignment_session.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.studentId,
    required this.classId,
    this.assignmentSession,
  });

  final String studentId;
  final String classId;
  final AssignmentSession? assignmentSession;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

enum _ReaderStage { levelSelection, reading, completed }

class _ReaderLevel {
  const _ReaderLevel(this.code, this.label);

  final String code;
  final String label;
}

const _readerLevels = [
  _ReaderLevel('junior_a', 'Junior A'),
  _ReaderLevel('junior_b', 'Junior B'),
  _ReaderLevel('senior_a', 'Senior A'),
  _ReaderLevel('senior_b', 'Senior B'),
  _ReaderLevel('senior_c', 'Senior C'),
  _ReaderLevel('senior_d', 'Senior D'),
  _ReaderLevel('pre_lower', 'Pre-Lower'),
  _ReaderLevel('lower', 'Lower'),
  _ReaderLevel('advanced', 'Advanced'),
  _ReaderLevel('proficiency', 'Proficiency'),
];

class _ReaderPageState extends State<ReaderPage> {
  static const _purple = Color(0xFF4D4AAD);
  static const _blue = Color(0xFF18A8EF);

  final Random _random = Random();

  _ReaderStage _stage = _ReaderStage.levelSelection;
  _ReaderLevel? _selectedLevel;
  _ReaderPassage? _passage;
  List<_ReaderQuestion> _questions = const [];
  int _questionIndex = 0;
  String _selectedText = '';
  bool? _answerIsCorrect;
  bool _loading = false;
  bool _showLevelError = false;
  bool _savingAssignmentProgress = false;
  late int _completedPassages = widget.assignmentSession?.progressValue ?? 0;
  late final Set<String> _completedPassageIds = {
    ...?widget.assignmentSession?.completedSourceKeys,
  };

  @override
  void initState() {
    super.initState();
    final session = widget.assignmentSession;
    if (session == null) return;
    final levelCode = session.settings['level']?.toString();
    for (final level in _readerLevels) {
      if (level.code == levelCode) {
        _selectedLevel = level;
        break;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  Future<void> _start({bool chooseAnother = false}) async {
    final level = _selectedLevel;
    if (level == null) {
      setState(() => _showLevelError = true);
      return;
    }

    setState(() {
      _loading = true;
      _showLevelError = false;
    });

    try {
      final rows = await Supabase.instance.client
          .from('reader_passages')
          .select('id, title, body')
          .eq('level_code', level.code)
          .eq('is_active', true);
      final passages = rows.map(_ReaderPassage.fromRow).toList();
      if (passages.isEmpty) {
        throw StateError('Δεν υπάρχει ενεργό κείμενο για το ${level.label}.');
      }

      var candidates = passages
          .where((passage) => !_completedPassageIds.contains(passage.id))
          .toList();
      if (candidates.isEmpty) {
        throw StateError('Δεν υπάρχουν άλλα κείμενα για αυτή την άσκηση.');
      }
      if (chooseAnother && candidates.length > 1 && _passage != null) {
        candidates = passages
            .where(
              (passage) =>
                  passage.id != _passage!.id &&
                  !_completedPassageIds.contains(passage.id),
            )
            .toList();
      }
      candidates.shuffle(_random);
      final passage = candidates.first;

      final questionRows = await Supabase.instance.client
          .from('reader_questions')
          .select('id, question, accepted_answers, sort_order')
          .eq('passage_id', passage.id)
          .eq('is_active', true)
          .order('sort_order');
      final questions = questionRows.map(_ReaderQuestion.fromRow).toList();
      if (questions.isEmpty) {
        throw StateError('Το κείμενο δεν έχει ενεργές ερωτήσεις.');
      }

      if (!mounted) return;
      setState(() {
        _passage = passage;
        _questions = questions;
        _questionIndex = 0;
        _selectedText = '';
        _answerIsCorrect = null;
        _loading = false;
        _stage = _ReaderStage.reading;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Δεν φορτώθηκε το κείμενο: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onSelectionChanged(
    TextSelection selection,
    SelectionChangedCause? cause,
  ) {
    final body = _passage?.body ?? '';
    final start = min(selection.baseOffset, selection.extentOffset);
    final end = max(selection.baseOffset, selection.extentOffset);
    if (start < 0 || end > body.length || start == end) {
      if (_selectedText.isNotEmpty) {
        setState(() {
          _selectedText = '';
          _answerIsCorrect = null;
        });
      }
      return;
    }
    final selected = body.substring(start, end);
    if (selected != _selectedText) {
      setState(() {
        _selectedText = selected;
        _answerIsCorrect = null;
      });
    }
  }

  Future<void> _checkAnswer() async {
    if (_selectedText.trim().isEmpty || _answerIsCorrect != null) return;
    final question = _questions[_questionIndex];
    final correct = question.acceptedAnswers.any(
      (answer) => _selectionContainsAnswer(_selectedText, answer),
    );
    setState(() => _answerIsCorrect = correct);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    if (!correct) {
      setState(() => _answerIsCorrect = null);
      return;
    }
    if (_questionIndex + 1 < _questions.length) {
      setState(() {
        _questionIndex++;
        _selectedText = '';
        _answerIsCorrect = null;
      });
    } else {
      setState(() => _stage = _ReaderStage.completed);
      unawaited(_saveCompletion());
      unawaited(_saveAssignmentProgress());
    }
  }

  Future<void> _saveAssignmentProgress() async {
    final session = widget.assignmentSession;
    final passage = _passage;
    if (session == null || passage == null) return;
    setState(() => _savingAssignmentProgress = true);
    try {
      final passed = await session.saveProgress(
        progress: _completedPassages + 1,
        scorePercentage: ((_completedPassages + 1) / session.targetValue) * 100,
        finishAttempt: false,
        sourceKey: passage.id,
      );
      if (!mounted) return;
      setState(() {
        _completedPassageIds.add(passage.id);
        _completedPassages = (_completedPassages + 1).clamp(
          0,
          session.targetValue,
        );
        _savingAssignmentProgress = false;
      });
      if (passed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Η άσκηση Reader ολοκληρώθηκε!')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingAssignmentProgress = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Δεν αποθηκεύτηκε η πρόοδος: $error')),
      );
    }
  }

  Future<void> _saveCompletion() async {
    final passage = _passage;
    final level = _selectedLevel;
    if (passage == null || level == null) return;
    try {
      await Supabase.instance.client.rpc(
        'submit_reader_completion',
        params: {
          'input_student_id': widget.studentId,
          'input_class_id': widget.classId,
          'input_passage_id': passage.id,
          'input_level_code': level.code,
          'input_question_count': _questions.length,
        },
      );
    } catch (_) {
      // Η ολοκλήρωση παραμένει ορατή ακόμη και αν το δίκτυο αποτύχει.
    }
  }

  String _normalise(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r"""^[“”"'.,!?;:\s]+|[“”"'.,!?;:\s]+$"""), '')
      .replaceAll(RegExp(r'\s+'), ' ');

  bool _selectionContainsAnswer(String selection, String acceptedAnswer) {
    final selectedWords = _normalise(selection).split(' ');
    final answerWords = _normalise(acceptedAnswer).split(' ');
    if (selectedWords.isEmpty ||
        answerWords.isEmpty ||
        selectedWords.length < answerWords.length ||
        selectedWords.length - answerWords.length > 8) {
      return false;
    }

    for (
      var start = 0;
      start <= selectedWords.length - answerWords.length;
      start++
    ) {
      var allWordsMatch = true;
      for (var offset = 0; offset < answerWords.length; offset++) {
        if (selectedWords[start + offset] != answerWords[offset]) {
          allWordsMatch = false;
          break;
        }
      }
      if (allWordsMatch) return true;
    }
    return false;
  }

  void _goHome() {
    if (widget.assignmentSession != null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _stage = _ReaderStage.levelSelection;
      _selectedLevel = null;
      _passage = null;
      _questions = const [];
      _questionIndex = 0;
      _selectedText = '';
      _answerIsCorrect = null;
      _showLevelError = false;
    });
  }

  void _goBack() {
    if (_stage == _ReaderStage.levelSelection) {
      Navigator.of(context).pop();
    } else {
      _goHome();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage == _ReaderStage.levelSelection,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
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
                onTap: _goBack,
                customBorder: const CircleBorder(),
                child: Icon(
                  _stage == _ReaderStage.levelSelection
                      ? Icons.close_rounded
                      : Icons.arrow_back_ios_new_rounded,
                  color: _stage == _ReaderStage.levelSelection
                      ? const Color(0xFFE32636)
                      : _purple,
                  size: 40,
                ),
              ),
            ),
          ),
          title: const Text(
            'Reader',
            style: TextStyle(
              color: Color(0xFF29265F),
              fontWeight: FontWeight.w900,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              Positioned.fill(
                child: switch (_stage) {
                  _ReaderStage.levelSelection => _buildLevelSelection(),
                  _ReaderStage.reading => _buildReading(),
                  _ReaderStage.completed => _buildCompleted(),
                },
              ),
              if (_stage == _ReaderStage.reading && _answerIsCorrect != null)
                Positioned.fill(
                  child: _AnswerFeedbackOverlay(isCorrect: _answerIsCorrect!),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLevelSelection() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
            children: [
              Center(
                child: Container(
                  width: 184,
                  height: 184,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(34),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1F4D4AAD),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset('lib/img/reader.png', fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Επίλεξε επίπεδο',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF29265F),
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Διάβασε το κείμενο και βρες την απάντηση μέσα σε αυτό.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6E6B8F),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              ..._readerLevels.map(
                (level) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _LevelTile(
                    label: level.label,
                    selected: _selectedLevel?.code == level.code,
                    onTap: () => setState(() {
                      _selectedLevel = level;
                      _showLevelError = false;
                    }),
                  ),
                ),
              ),
              if (_showLevelError)
                const Text(
                  'Επίλεξε πρώτα ένα επίπεδο.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFE32636),
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
        ),
        _ReaderAction(label: 'Έναρξη', loading: _loading, onPressed: _start),
      ],
    );
  }

  Widget _buildReading() {
    final passage = _passage!;
    final question = _questions[_questionIndex];
    return Column(
      children: [
        LinearProgressIndicator(
          value: (_questionIndex + 1) / _questions.length,
          minHeight: 8,
          color: _blue,
          backgroundColor: const Color(0xFFDCD9F4),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            children: [
              Text(
                passage.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF29265F),
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_selectedLevel!.label} • Ερώτηση ${_questionIndex + 1}/${_questions.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF77738F),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(21),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x174D4AAD),
                      blurRadius: 22,
                      offset: Offset(0, 9),
                    ),
                  ],
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    textSelectionTheme: const TextSelectionThemeData(
                      selectionColor: Color(0xAAFFE066),
                      selectionHandleColor: Color(0xFF4D4AAD),
                    ),
                  ),
                  child: SelectableText(
                    passage.body,
                    key: ValueKey('${passage.id}-$_questionIndex'),
                    onSelectionChanged: _onSelectionChanged,
                    contextMenuBuilder: (_, _) => const SizedBox.shrink(),
                    style: const TextStyle(
                      color: Color(0xFF242238),
                      fontSize: 18,
                      height: 1.65,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9E7FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.touch_app_rounded,
                      color: _purple,
                      size: 30,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      question.question,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF29265F),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 9),
                    const Text(
                      'Κράτησε πατημένο και σύρε πάνω στην απάντηση.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF6E6B8F),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (_selectedText.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Επέλεξες: “${_selectedText.trim()}”',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF625F7E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (_answerIsCorrect != null) ...[
                const SizedBox(height: 12),
                Text(
                  _answerIsCorrect!
                      ? 'Σωστά! Πάμε στην επόμενη.'
                      : 'Δεν είναι αυτό το σωστό σημείο. Προσπάθησε ξανά.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _answerIsCorrect!
                        ? const Color(0xFF178A45)
                        : const Color(0xFFC62836),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ],
          ),
        ),
        _ReaderAction(
          label: 'Έλεγχος',
          onPressed: _selectedText.trim().isEmpty ? null : _checkAnswer,
        ),
      ],
    );
  }

  Widget _buildCompleted() {
    final session = widget.assignmentSession;
    final assignmentFinished =
        session != null && _completedPassages >= session.targetValue;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(
              Icons.celebration_rounded,
              color: Color(0xFFFFB300),
              size: 92,
            ),
            const SizedBox(height: 18),
            const Text(
              'Συγχαρητήρια!\nΤελειώσατε.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF29265F),
                fontSize: 30,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 34),
            if (session != null) ...[
              Text(
                'Κείμενα: $_completedPassages/${session.targetValue}',
                style: const TextStyle(
                  color: _purple,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (assignmentFinished) ...[
                const SizedBox(height: 10),
                const Text(
                  'Βαθμός: 100%',
                  style: TextStyle(
                    color: Color(0xFF178A45),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
              const SizedBox(height: 18),
            ],
            if (!assignmentFinished) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading || _savingAssignmentProgress
                      ? null
                      : () => _start(chooseAnother: true),
                  icon: const Icon(Icons.auto_stories_rounded),
                  label: const Text('Άλλο κείμενο'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _savingAssignmentProgress ? null : _goHome,
                icon: const Icon(Icons.home_rounded),
                label: Text(
                  session == null ? 'Αρχική' : 'Επιστροφή στις ασκήσεις',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _purple,
                  side: const BorderSide(color: _purple, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
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

class _ReaderPassage {
  const _ReaderPassage({
    required this.id,
    required this.title,
    required this.body,
  });

  factory _ReaderPassage.fromRow(Map<String, dynamic> row) => _ReaderPassage(
    id: row['id']?.toString() ?? '',
    title: row['title']?.toString() ?? '',
    body: row['body']?.toString() ?? '',
  );

  final String id;
  final String title;
  final String body;
}

class _ReaderQuestion {
  const _ReaderQuestion({
    required this.question,
    required this.acceptedAnswers,
  });

  factory _ReaderQuestion.fromRow(Map<String, dynamic> row) => _ReaderQuestion(
    question: row['question']?.toString() ?? '',
    acceptedAnswers: (row['accepted_answers'] as List? ?? const [])
        .map((answer) => answer.toString())
        .toList(),
  );

  final String question;
  final List<String> acceptedAnswers;
}

class _LevelTile extends StatelessWidget {
  const _LevelTile({
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
      color: selected ? const Color(0xFFE9E7FF) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? const Color(0xFF4D4AAD)
                  : const Color(0xFFE1DFEC),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: const Color(0xFF29265F),
                    fontSize: 17,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 27,
                height: 27,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF4D4AAD)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF4D4AAD)
                        : const Color(0xFFAAA7BC),
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 19,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderAction extends StatelessWidget {
  const _ReaderAction({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        14 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x164D4AAD),
            blurRadius: 16,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: loading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF4D4AAD),
            disabledBackgroundColor: const Color(0xFFC5C2DD),
            padding: const EdgeInsets.symmetric(vertical: 17),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        ),
      ),
    );
  }
}

class _AnswerFeedbackOverlay extends StatelessWidget {
  const _AnswerFeedbackOverlay({required this.isCorrect});

  final bool isCorrect;

  @override
  Widget build(BuildContext context) {
    final color = isCorrect ? const Color(0xFF20A85B) : const Color(0xFFE32636);
    return AbsorbPointer(
      child: ColoredBox(
        color: const Color(0x55000000),
        child: Center(
          child: Container(
            width: 176,
            height: 176,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 9),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 30,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Icon(
              isCorrect ? Icons.check_rounded : Icons.close_rounded,
              color: color,
              size: 126,
              weight: 900,
            ),
          ),
        ),
      ),
    );
  }
}
