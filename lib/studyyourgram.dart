import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'assignment_session.dart';

class StudyYourGramPage extends StatefulWidget {
  const StudyYourGramPage({
    super.key,
    required this.studentId,
    required this.classId,
    this.assignmentSession,
  });

  final String studentId;
  final String classId;
  final AssignmentSession? assignmentSession;

  @override
  State<StudyYourGramPage> createState() => _StudyYourGramPageState();
}

enum _GramStage { selection, theory, exercise, results }

class _StudyYourGramPageState extends State<StudyYourGramPage> {
  static const _purple = Color(0xFF4D4AAD);
  static const _blue = Color(0xFF18A8EF);

  late Future<List<_GrammarTopic>> _topicsFuture = _loadTopics();
  final Set<String> _selectedSlugs = {};
  final TextEditingController _answerController = TextEditingController();
  final FocusNode _answerFocusNode = FocusNode();
  final Random _random = Random();

  _GramStage _stage = _GramStage.selection;
  List<_GrammarTopic> _selectedTopics = const [];
  List<_GrammarQuestion> _questions = const [];
  Map<String, List<_GrammarQuestion>> _questionPoolByTopic = const {};
  int _questionIndex = 0;
  int _correctAnswers = 0;
  int _answeredQuestions = 0;
  bool _loadingQuestions = false;
  bool _showSelectionError = false;
  bool? _answerIsCorrect;
  String? _expectedAnswer;
  Timer? _assignmentTimer;
  late int _secondsLeft = widget.assignmentSession?.remainingSeconds ?? 0;
  Future<void>? _assignmentSaveFuture;

  bool get _isTimedAssignment =>
      widget.assignmentSession?.settings['limit_type'] == 'time';

  @override
  void initState() {
    super.initState();
    final session = widget.assignmentSession;
    if (session == null) return;
    _topicsFuture.then((topics) {
      if (!mounted) return;
      final rawSlugs = session.settings['topic_slugs'];
      final slugs = rawSlugs is List
          ? rawSlugs.map((value) => value.toString()).toSet()
          : <String>{};
      _selectedSlugs.addAll(slugs);
      _startTheory(topics);
    });
  }

  @override
  void dispose() {
    _assignmentTimer?.cancel();
    _answerController.dispose();
    _answerFocusNode.dispose();
    super.dispose();
  }

  Future<List<_GrammarTopic>> _loadTopics() async {
    final rows = await Supabase.instance.client
        .from('study_gram_topics')
        .select('slug, title, sort_order, theory')
        .eq('is_active', true)
        .order('sort_order');
    return rows.map(_GrammarTopic.fromRow).toList();
  }

  Future<void> _startTheory(List<_GrammarTopic> topics) async {
    if (_selectedSlugs.isEmpty) {
      setState(() => _showSelectionError = true);
      return;
    }

    setState(() {
      _loadingQuestions = true;
      _showSelectionError = false;
    });

    try {
      final rows = await Supabase.instance.client
          .from('study_gram_questions')
          .select(
            'id, topic_slug, prompt, verb_hint, accepted_answers, '
            'highlight_phrases, explanation, sort_order',
          )
          .inFilter('topic_slug', _selectedSlugs.toList())
          .eq('is_active', true)
          .order('sort_order');

      final byTopic = <String, List<_GrammarQuestion>>{};
      for (final row in rows) {
        final question = _GrammarQuestion.fromRow(row);
        byTopic.putIfAbsent(question.topicSlug, () => []).add(question);
      }

      final selectedTopics = topics
          .where((topic) => _selectedSlugs.contains(topic.slug))
          .toList();
      for (final topic in selectedTopics) {
        final topicQuestions = byTopic[topic.slug] ?? const [];
        if (widget.assignmentSession == null && topicQuestions.length < 12) {
          throw StateError(
            'Το "${topic.title}" χρειάζεται 12 ενεργές ερωτήσεις '
            '(βρέθηκαν ${topicQuestions.length}).',
          );
        }
      }
      final questions = _buildRandomQuestionSet(byTopic, selectedTopics);

      if (!mounted) return;
      setState(() {
        _selectedTopics = selectedTopics;
        _questionPoolByTopic = byTopic;
        _questions = questions;
        _stage = _GramStage.theory;
        _loadingQuestions = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingQuestions = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Δεν φορτώθηκαν οι ασκήσεις: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _beginExercise() {
    setState(() {
      _questionIndex = 0;
      _correctAnswers = 0;
      _answeredQuestions = 0;
      _answerIsCorrect = null;
      _expectedAnswer = null;
      _answerController.clear();
      _stage = _GramStage.exercise;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _answerFocusNode.requestFocus(),
    );
    if (_isTimedAssignment) _startAssignmentTimer();
  }

  void _startAssignmentTimer() {
    _assignmentTimer?.cancel();
    _assignmentTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _stage != _GramStage.exercise) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() {
          _secondsLeft = 0;
          _stage = _GramStage.results;
        });
        unawaited(_saveAssignmentResult());
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  void _checkAnswer() {
    if (_answerIsCorrect != null) {
      _nextQuestion();
      return;
    }
    final answer = _normalise(_answerController.text);
    if (answer.isEmpty) return;

    final question = _questions[_questionIndex];
    final isCorrect = question.acceptedAnswers.map(_normalise).contains(answer);
    setState(() {
      _answerIsCorrect = isCorrect;
      _expectedAnswer = question.acceptedAnswers.first;
      _answeredQuestions++;
      if (isCorrect) _correctAnswers++;
    });
  }

  void _nextQuestion() {
    if (_questionIndex + 1 >= _questions.length) {
      if (_isTimedAssignment) {
        setState(() {
          _questions.shuffle(_random);
          _questionIndex = 0;
          _answerIsCorrect = null;
          _expectedAnswer = null;
          _answerController.clear();
        });
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _answerFocusNode.requestFocus(),
        );
        return;
      }
      setState(() => _stage = _GramStage.results);
      unawaited(_saveAttempt());
      unawaited(_saveAssignmentResult());
      return;
    }
    setState(() {
      _questionIndex++;
      _answerIsCorrect = null;
      _expectedAnswer = null;
      _answerController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _answerFocusNode.requestFocus(),
    );
  }

  Future<void> _saveAttempt() async {
    if (widget.assignmentSession != null) return;
    try {
      await Supabase.instance.client.rpc(
        'submit_study_gram_attempt',
        params: {
          'input_student_id': widget.studentId,
          'input_class_id': widget.classId,
          'input_topic_slugs': _selectedTopics
              .map((topic) => topic.slug)
              .toList(),
          'input_correct_answers': _correctAnswers,
          'input_total_questions': _questions.length,
        },
      );
    } catch (_) {
      // Η βαθμολογία παραμένει ορατή ακόμη και αν το δίκτυο αποτύχει.
    }
  }

  Future<void> _saveAssignmentResult() {
    return _assignmentSaveFuture ??= _persistAssignmentResult();
  }

  Future<void> _persistAssignmentResult() async {
    final session = widget.assignmentSession;
    if (session == null) return;
    _assignmentTimer?.cancel();
    final answered = _answeredQuestions;
    final percentage = answered == 0 ? 0.0 : (_correctAnswers / answered) * 100;
    try {
      await session.saveProgress(
        progress: _isTimedAssignment ? session.targetValue : answered,
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

  void _tryAgain() {
    final previousIds = _questions.map((question) => question.id).toSet();
    var questions = _buildRandomQuestionSet(
      _questionPoolByTopic,
      _selectedTopics,
    );

    final canCreateDifferentSet = _selectedTopics.any(
      (topic) => (_questionPoolByTopic[topic.slug]?.length ?? 0) > 12,
    );
    if (canCreateDifferentSet) {
      for (
        var attempt = 0;
        attempt < 12 &&
            questions
                .map((question) => question.id)
                .toSet()
                .containsAll(previousIds);
        attempt++
      ) {
        questions = _buildRandomQuestionSet(
          _questionPoolByTopic,
          _selectedTopics,
        );
      }
    }

    setState(() {
      _questions = questions;
      _questionIndex = 0;
      _correctAnswers = 0;
      _answeredQuestions = 0;
      _answerIsCorrect = null;
      _expectedAnswer = null;
      _answerController.clear();
      _stage = _GramStage.theory;
    });
  }

  void _returnHome() {
    if (widget.assignmentSession != null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _stage = _GramStage.selection;
      _selectedSlugs.clear();
      _selectedTopics = const [];
      _questions = const [];
      _questionPoolByTopic = const {};
      _showSelectionError = false;
      _answerController.clear();
    });
  }

  void _goBack() {
    switch (_stage) {
      case _GramStage.selection:
        Navigator.of(context).pop();
      case _GramStage.theory:
        setState(() => _stage = _GramStage.selection);
      case _GramStage.exercise:
      case _GramStage.results:
        setState(() => _stage = _GramStage.theory);
    }
  }

  String _normalise(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r'\s+'), ' ');

  List<_GrammarQuestion> _buildRandomQuestionSet(
    Map<String, List<_GrammarQuestion>> questionPool,
    List<_GrammarTopic> selectedTopics,
  ) {
    final session = widget.assignmentSession;
    if (session != null) {
      final allQuestions = <_GrammarQuestion>[
        for (final topic in selectedTopics) ...?questionPool[topic.slug],
      ]..shuffle(_random);
      if (session.settings['limit_type'] == 'questions') {
        return allQuestions.take(session.targetValue).toList();
      }
      return allQuestions;
    }
    final questions = <_GrammarQuestion>[];
    for (final topic in selectedTopics) {
      final topicQuestions = [...?questionPool[topic.slug]]..shuffle(_random);
      questions.addAll(topicQuestions.take(12));
    }
    questions.shuffle(_random);
    return questions;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage == _GramStage.selection,
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
                  _stage == _GramStage.selection
                      ? Icons.close_rounded
                      : Icons.arrow_back_ios_new_rounded,
                  color: _stage == _GramStage.selection
                      ? const Color(0xFFE32636)
                      : const Color(0xFF4D4AAD),
                  size: 40,
                ),
              ),
            ),
          ),
          title: const Text(
            'Study your gram',
            style: TextStyle(
              color: Color(0xFF29265F),
              fontWeight: FontWeight.w900,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          top: false,
          child: switch (_stage) {
            _GramStage.selection => _buildSelection(),
            _GramStage.theory => _buildTheory(),
            _GramStage.exercise => _buildExercise(),
            _GramStage.results => _buildResults(),
          },
        ),
      ),
    );
  }

  Widget _buildSelection() {
    return FutureBuilder<List<_GrammarTopic>>(
      future: _topicsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: _purple));
        }
        if (snapshot.hasError) {
          return _ErrorState(
            message:
                'Δεν φορτώθηκαν τα γραμματικά φαινόμενα.\n${snapshot.error}',
            onRetry: () {
              setState(() {
                _topicsFuture = _loadTopics();
              });
            },
          );
        }
        final topics = snapshot.data ?? const [];
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
                      child: Image.asset(
                        'lib/img/studyyourgram.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Τι θέλεις να εξασκήσεις;',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF29265F),
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Μπορείς να επιλέξεις ένα ή περισσότερα.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF6E6B8F),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ...topics.map(
                    (topic) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TopicTile(
                        title: topic.title,
                        selected: _selectedSlugs.contains(topic.slug),
                        onTap: () => setState(() {
                          _showSelectionError = false;
                          if (!_selectedSlugs.add(topic.slug)) {
                            _selectedSlugs.remove(topic.slug);
                          }
                        }),
                      ),
                    ),
                  ),
                  if (_showSelectionError)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Επίλεξε τουλάχιστον ένα γραμματικό φαινόμενο.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFE32636),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _BottomAction(
              label: _selectedSlugs.isEmpty
                  ? 'Έναρξη'
                  : 'Έναρξη • ${_selectedSlugs.length * 12} ερωτήσεις',
              loading: _loadingQuestions,
              onPressed: () => _startTheory(topics),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTheory() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              const Text(
                'Μικρή επανάληψη',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF29265F),
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 18),
              ..._selectedTopics.map((topic) => _TheoryCard(topic: topic)),
            ],
          ),
        ),
        _BottomAction(label: 'Κατάλαβα', onPressed: _beginExercise),
      ],
    );
  }

  Widget _buildExercise() {
    final question = _questions[_questionIndex];
    final progress = (_questionIndex + 1) / _questions.length;

    return Column(
      children: [
        LinearProgressIndicator(
          value: progress,
          minHeight: 8,
          color: _blue,
          backgroundColor: const Color(0xFFDCD9F4),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ερώτηση ${_questionIndex + 1} από ${_questions.length}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF77738F),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_isTimedAssignment) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Χρόνος: ${(_secondsLeft ~/ 60).toString().padLeft(2, '0')}:${(_secondsLeft % 60).toString().padLeft(2, '0')}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFE32636),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x174D4AAD),
                        blurRadius: 22,
                        offset: Offset(0, 9),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (question.verbHint.isNotEmpty)
                        Text(
                          'Βάλε το “${question.verbHint}” στον σωστό τύπο.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF6E6B8F),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      const SizedBox(height: 22),
                      _GapSentence(
                        question: question,
                        controller: _answerController,
                        focusNode: _answerFocusNode,
                        enabled: _answerIsCorrect == null,
                        answerIsCorrect: _answerIsCorrect,
                        onSubmitted: (_) => _checkAnswer(),
                      ),
                      if (_answerIsCorrect != null) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _answerIsCorrect!
                                ? const Color(0xFFE8F8EE)
                                : const Color(0xFFFFECEE),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            _answerIsCorrect!
                                ? 'Σωστά! Μπράβο!'
                                : 'Η σωστή απάντηση είναι: $_expectedAnswer',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _answerIsCorrect!
                                  ? const Color(0xFF178A45)
                                  : const Color(0xFFC62836),
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (question.explanation.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            question.explanation,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF625F7E),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _answerController,
          builder: (context, value, _) => _BottomAction(
            label: _answerIsCorrect == null
                ? 'Έλεγχος'
                : _questionIndex + 1 == _questions.length
                ? 'Αποτελέσματα'
                : 'Επόμενη',
            onPressed: value.text.trim().isEmpty && _answerIsCorrect == null
                ? null
                : _checkAnswer,
          ),
        ),
      ],
    );
  }

  Widget _buildResults() {
    final resultTotal = _isTimedAssignment
        ? _answeredQuestions
        : _questions.length;
    final percentage = resultTotal == 0
        ? 0
        : ((_correctAnswers / resultTotal) * 100).round();
    final color = percentage >= 80
        ? const Color(0xFF20A85B)
        : percentage >= 50
        ? const Color(0xFFFFA000)
        : const Color(0xFFE34B58);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 230,
              padding: const EdgeInsets.symmetric(vertical: 30),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(34),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x204D4AAD),
                    blurRadius: 28,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(Icons.emoji_events_rounded, color: color, size: 72),
                  const SizedBox(height: 10),
                  Text(
                    '$percentage%',
                    style: TextStyle(
                      color: color,
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '$_correctAnswers / $resultTotal σωστές',
                    style: const TextStyle(
                      color: Color(0xFF625F7E),
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (widget.assignmentSession != null) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Απαιτείται τουλάχιστον 71%',
                      style: TextStyle(
                        color: Color(0xFF625F7E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 34),
            if (widget.assignmentSession == null) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _tryAgain,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Προσπάθησε ξανά'),
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
                onPressed: () async {
                  await _saveAssignmentResult();
                  if (mounted) _returnHome();
                },
                icon: const Icon(Icons.home_rounded),
                label: Text(
                  widget.assignmentSession == null
                      ? 'Επιστροφή στην αρχική'
                      : 'Επιστροφή στις ασκήσεις',
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

class _GrammarTopic {
  const _GrammarTopic({
    required this.slug,
    required this.title,
    required this.theory,
  });

  factory _GrammarTopic.fromRow(Map<String, dynamic> row) {
    final rawTheory = row['theory'];
    return _GrammarTopic(
      slug: row['slug']?.toString() ?? '',
      title: row['title']?.toString() ?? '',
      theory: rawTheory is List
          ? rawTheory
                .whereType<Map>()
                .map(
                  (item) =>
                      _TheoryLine.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
          : const [],
    );
  }

  final String slug;
  final String title;
  final List<_TheoryLine> theory;
}

class _TheoryLine {
  const _TheoryLine({required this.label, required this.parts});

  factory _TheoryLine.fromJson(Map<String, dynamic> json) {
    final rawParts = json['parts'];
    return _TheoryLine(
      label: json['label']?.toString() ?? '',
      parts: rawParts is List
          ? rawParts
                .whereType<Map>()
                .map(
                  (part) =>
                      _TheoryPart.fromJson(Map<String, dynamic>.from(part)),
                )
                .toList()
          : const [],
    );
  }

  final String label;
  final List<_TheoryPart> parts;
}

class _TheoryPart {
  const _TheoryPart({required this.text, required this.highlight});

  factory _TheoryPart.fromJson(Map<String, dynamic> json) => _TheoryPart(
    text: json['text']?.toString() ?? '',
    highlight: json['highlight'] == true,
  );

  final String text;
  final bool highlight;
}

class _GrammarQuestion {
  const _GrammarQuestion({
    required this.id,
    required this.topicSlug,
    required this.prompt,
    required this.verbHint,
    required this.acceptedAnswers,
    required this.highlightPhrases,
    required this.explanation,
  });

  factory _GrammarQuestion.fromRow(Map<String, dynamic> row) =>
      _GrammarQuestion(
        id: row['id']?.toString() ?? '',
        topicSlug: row['topic_slug']?.toString() ?? '',
        prompt: row['prompt']?.toString() ?? '',
        verbHint: row['verb_hint']?.toString() ?? '',
        acceptedAnswers: (row['accepted_answers'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
        highlightPhrases: (row['highlight_phrases'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
        explanation: row['explanation']?.toString() ?? '',
      );

  final String id;
  final String topicSlug;
  final String prompt;
  final String verbHint;
  final List<String> acceptedAnswers;
  final List<String> highlightPhrases;
  final String explanation;
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
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
                  title,
                  style: TextStyle(
                    color: const Color(0xFF29265F),
                    fontSize: 16,
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

class _TheoryCard extends StatelessWidget {
  const _TheoryCard({required this.topic});

  final _GrammarTopic topic;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x144D4AAD),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            topic.title,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 21,
              fontWeight: FontWeight.w900,
              decoration: TextDecoration.underline,
              decorationThickness: 2,
            ),
          ),
          const SizedBox(height: 14),
          ...topic.theory.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                    color: Color(0xFF242238),
                    fontSize: 15.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                  children: [
                    if (line.label.isNotEmpty)
                      TextSpan(
                        text: '${line.label}: ',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ...line.parts.map(
                      (part) => TextSpan(
                        text: part.text,
                        style: part.highlight
                            ? const TextStyle(
                                color: Color(0xFF29265F),
                                backgroundColor: Color(0xFFFFE66D),
                                fontWeight: FontWeight.w900,
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GapSentence extends StatelessWidget {
  const _GapSentence({
    required this.question,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.answerIsCorrect,
    required this.onSubmitted,
  });

  final _GrammarQuestion question;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool? answerIsCorrect;
  final ValueChanged<String> onSubmitted;

  List<InlineSpan> _highlightedSpans(String value) {
    if (value.isEmpty) return const [];
    final phrases =
        question.highlightPhrases
            .where((phrase) => phrase.trim().isNotEmpty)
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    if (phrases.isEmpty) return [TextSpan(text: value)];
    final pattern = RegExp(
      '(${phrases.map(RegExp.escape).join('|')})',
      caseSensitive: false,
    );
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in pattern.allMatches(value)) {
      if (match.start > start) {
        spans.add(TextSpan(text: value.substring(start, match.start)));
      }
      spans.add(
        TextSpan(
          text: value.substring(match.start, match.end),
          style: const TextStyle(
            backgroundColor: Color(0xFFFFE66D),
            fontWeight: FontWeight.w900,
          ),
        ),
      );
      start = match.end;
    }
    if (start < value.length) spans.add(TextSpan(text: value.substring(start)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final promptParts = question.prompt.split('{{gap}}');
    final before = promptParts.first;
    final after = promptParts.length > 1
        ? promptParts.sublist(1).join('{{gap}}')
        : '';
    final borderColor = answerIsCorrect == null
        ? const Color(0xFF4D4AAD)
        : answerIsCorrect!
        ? const Color(0xFF20A85B)
        : const Color(0xFFE32636);

    return Text.rich(
      TextSpan(
        style: const TextStyle(
          color: Color(0xFF242238),
          fontSize: 21,
          height: 2,
          fontWeight: FontWeight.w700,
        ),
        children: [
          ..._highlightedSpans(before),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              width: 156,
              height: 48,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                onSubmitted: onSubmitted,
                textAlign: TextAlign.center,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.none,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF29265F),
                ),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  filled: true,
                  fillColor: const Color(0xFFF5F4FC),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: borderColor, width: 3),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: borderColor, width: 3),
                  ),
                  disabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: borderColor, width: 3),
                  ),
                ),
              ),
            ),
          ),
          ..._highlightedSpans(after),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    Widget button() => SizedBox(
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
    );

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
      child: button(),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

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
            const Icon(
              Icons.cloud_off_rounded,
              size: 58,
              color: Color(0xFFE32636),
            ),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Δοκίμασε ξανά'),
            ),
          ],
        ),
      ),
    );
  }
}
