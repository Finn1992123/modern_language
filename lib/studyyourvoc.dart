import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'assignment_session.dart';
import 'assignment_word_preview.dart';

enum _VocMode { study, speaking, multipleChoice, writeGreek, writeForeign }

class StudyYourVocPage extends StatefulWidget {
  const StudyYourVocPage({
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
  State<StudyYourVocPage> createState() => _StudyYourVocPageState();
}

class _StudyYourVocPageState extends State<StudyYourVocPage> {
  late final Future<List<_VocWord>> _wordsFuture = _loadWords();
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final CardSwiperController _studySwiperController = CardSwiperController();
  final TextEditingController _answerController = TextEditingController();
  final Random _random = Random();

  _VocMode? _mode;
  String? _selectedUnit;
  int _wordIndex = 0;
  bool _isFlipped = false;
  bool? _lastAnswerCorrect;
  List<String> _multipleChoices = const [];
  String? _selectedChoice;
  bool _speechReady = false;
  bool _isListening = false;
  bool _speechResultHandled = false;
  int _speechSessionId = 0;
  int _ttsSessionId = 0;
  Future<void>? _ttsReady;
  String _spokenText = '';
  bool _importantOnly = false;
  bool _unitValidationError = false;
  final Set<String> _learnedWordIds = {};
  final Set<String> _recordedMistakeWordIds = {};
  final List<_VocAttempt> _attempts = [];
  bool _assignmentResultSaved = false;
  bool _assignmentPreviewCompleted = false;
  Future<void>? _assignmentSaveFuture;

  bool get _usesPersonalWords =>
      widget.assignmentSession?.settings['personal_words'] == true ||
      widget.assignmentSession?.settings['unit'] == '__personal__';

  @override
  void initState() {
    super.initState();
    final session = widget.assignmentSession;
    if (session == null) return;
    if (_usesPersonalWords) {
      _selectedUnit = 'personal';
    } else {
      final unit = session.settings['unit']?.toString() ?? '';
      final order = (session.settings['unit_order'] as num?)?.toInt();
      _selectedUnit = '${order ?? 999999}::$unit';
    }
    _importantOnly = session.settings['important_only'] == true;
    _mode = switch (session.settings['mode']?.toString()) {
      'speaking' => _VocMode.speaking,
      'multiple_choice' => _VocMode.multipleChoice,
      'write_foreign' => _VocMode.writeForeign,
      'write_greek' => _VocMode.writeGreek,
      _ => _VocMode.multipleChoice,
    };
  }

  @override
  void dispose() {
    _speechSessionId++;
    _ttsSessionId++;
    _answerController.dispose();
    unawaited(_speech.stop());
    _tts.stop();
    unawaited(_studySwiperController.dispose());
    super.dispose();
  }

  Future<List<_VocWord>> _loadWords() async {
    final session = widget.assignmentSession;
    final rows = _usesPersonalWords && session != null
        ? await Supabase.instance.client.rpc(
            'get_student_assignment_vocabulary_words',
            params: {
              'input_assignment_id': session.assignmentId,
              'input_student_id': widget.studentId,
              'input_class_id': widget.classId,
            },
          )
        : await Supabase.instance.client.rpc(
            'get_student_study_vocabulary',
            params: {
              'input_student_id': widget.studentId,
              'input_class_id': widget.classId,
            },
          );

    if (rows is! List) {
      return const [];
    }

    return rows
        .whereType<Map>()
        .map((row) => _VocWord.fromRow(Map<String, dynamic>.from(row)))
        .where((word) => word.word.isNotEmpty && word.translationGr.isNotEmpty)
        .toList();
  }

  void _selectUnit(String? unit) {
    setState(() {
      _selectedUnit = unit;
      _unitValidationError = false;
      _wordIndex = 0;
      _attempts.clear();
      _resetQuestionState();
    });
  }

  void _selectMode(_VocMode? mode) {
    if (mode != null && _selectedUnit == null) {
      setState(() => _unitValidationError = true);
      return;
    }

    setState(() {
      _mode = mode;
      _unitValidationError = false;
      _wordIndex = 0;
      if (mode == _VocMode.study) {
        _learnedWordIds.clear();
      }
      _recordedMistakeWordIds.clear();
      _attempts.clear();
      _resetQuestionState();
    });
  }

  void _resetQuestionState() {
    _speechSessionId++;
    _ttsSessionId++;
    unawaited(_speech.stop());
    unawaited(_tts.stop());
    _isFlipped = false;
    _lastAnswerCorrect = null;
    _selectedChoice = null;
    _multipleChoices = const [];
    _isListening = false;
    _speechResultHandled = false;
    _spokenText = '';
    _answerController.clear();
  }

  void _moveWord(int direction, List<_VocWord> words) {
    if (words.isEmpty) {
      return;
    }

    setState(() {
      _wordIndex = (_wordIndex + direction) % words.length;
      if (_wordIndex < 0) {
        _wordIndex = words.length - 1;
      }
      _resetQuestionState();
    });
  }

  Future<void> _speak(_VocWord word) async {
    final sessionId = ++_ttsSessionId;
    final language = word.language.isEmpty
        ? widget.languageLabel
        : word.language;
    try {
      await (_ttsReady ??= _initializeTts()).timeout(
        const Duration(seconds: 6),
      );
      if (!mounted || sessionId != _ttsSessionId) return;

      final languageResult = await _tts
          .setLanguage(_ttsLanguage(language))
          .timeout(const Duration(seconds: 6));
      if (languageResult != 1) {
        throw StateError('TTS language is not installed');
      }
      if (!mounted || sessionId != _ttsSessionId) return;

      final speakResult = await _tts
          .speak(word.word, focus: true)
          .timeout(const Duration(seconds: 6));
      if (speakResult != 1) {
        throw StateError('TTS engine did not start');
      }
    } catch (_) {
      _ttsReady = null;
      if (!mounted || sessionId != _ttsSessionId) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Δεν είναι διαθέσιμη η εκφώνηση. Ελέγξτε ότι υπάρχει εγκατεστημένη φωνή Text-to-Speech στη συσκευή.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _initializeTts() async {
    await _tts.awaitSpeakCompletion(false);
    await _tts.setSpeechRate(0.42);
    await _tts.setPitch(1);
  }

  Future<void> _toggleListening(_VocWord word) async {
    if (_isListening) {
      _speechSessionId++;
      await _speech.stop();
      if (!mounted) {
        return;
      }
      setState(() => _isListening = false);
      return;
    }

    final sessionId = ++_speechSessionId;
    final ready = _speechReady || await _speech.initialize();
    if (!mounted || sessionId != _speechSessionId) {
      return;
    }

    if (!ready) {
      setState(() {
        _speechReady = false;
        _lastAnswerCorrect = false;
        _spokenText = 'Δεν ενεργοποιήθηκε το μικρόφωνο.';
      });
      return;
    }

    final language = word.language.isEmpty
        ? widget.languageLabel
        : word.language;

    setState(() {
      _speechReady = true;
      _isListening = true;
      _speechResultHandled = false;
      if (_lastAnswerCorrect != false) {
        _lastAnswerCorrect = null;
      }
      _spokenText = '';
    });

    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: _speechLanguage(language),
        listenFor: const Duration(seconds: 4),
        pauseFor: const Duration(seconds: 2),
        partialResults: true,
      ),
      onResult: (result) {
        if (!mounted || sessionId != _speechSessionId) {
          return;
        }

        final recognized = result.recognizedWords;
        final isCorrect = _exactAnswerMatch(recognized, word.word);

        if (_speechResultHandled) {
          setState(() => _spokenText = recognized);
          return;
        }

        if (isCorrect) {
          _speechResultHandled = true;
          _speech.stop();
          setState(() {
            _spokenText = recognized;
            _isListening = false;
            _lastAnswerCorrect = true;
            _recordFirstSpeakingAttempt(
              word: word,
              userAnswer: recognized,
              correct: true,
            );
          });
          _speak(word);
          return;
        }

        setState(() {
          _spokenText = recognized;
          if (result.finalResult) {
            _speechResultHandled = true;
            _isListening = false;
            _lastAnswerCorrect = false;
            _recordFirstSpeakingAttempt(
              word: word,
              userAnswer: recognized,
              correct: false,
            );
          }
        });

        if (result.finalResult) {
          _speak(word);
        }
      },
    );
  }

  void _prepareChoices(List<_VocWord> words, _VocWord current) {
    if (_multipleChoices.isNotEmpty) {
      return;
    }

    final choices = <String>{current.translationGr};
    final pool =
        words
            .where((word) => word.id != current.id)
            .map((word) => word.translationGr)
            .where((translation) => translation.isNotEmpty)
            .toList()
          ..shuffle(_random);

    for (final translation in pool) {
      if (choices.length >= 4) {
        break;
      }
      choices.add(translation);
    }

    final prepared = choices.toList()..shuffle(_random);
    _multipleChoices = prepared;
  }

  void _checkWrittenAnswer(_VocWord word, {required bool toGreek}) {
    final answer = _answerController.text;
    final correctAnswers = toGreek ? word.acceptedAnswers : <String>[word.word];
    final correctAnswer = toGreek ? word.translationGr : word.word;
    final prompt = toGreek ? word.word : word.translationGr;
    final mode = toGreek ? _VocMode.writeGreek : _VocMode.writeForeign;
    final isCorrect = correctAnswers.any((correct) {
      if (toGreek) return _answersMatch(answer, correct);
      return _exactAnswerMatch(answer, correct);
    });

    setState(() {
      _lastAnswerCorrect = isCorrect;
      _recordAttempt(
        mode: mode,
        word: word,
        prompt: prompt,
        userAnswer: answer,
        correctAnswer: correctAnswer,
        correct: isCorrect,
      );
    });
    if (!isCorrect) {
      unawaited(_recordVocabularyMistake(word, answer));
    }
  }

  Future<void> _recordVocabularyMistake(
    _VocWord word,
    String wrongAnswer,
  ) async {
    if (widget.assignmentSession == null) return;
    if (!_recordedMistakeWordIds.add(word.id)) return;
    try {
      await Supabase.instance.client.rpc(
        'record_student_vocabulary_mistake',
        params: {
          'input_student_id': widget.studentId,
          'input_class_id': widget.classId,
          'input_vocabulary_word_id': word.id,
          'input_source': 'study_your_voc',
          'input_wrong_answer': wrongAnswer.trim(),
        },
      );
    } catch (_) {
      _recordedMistakeWordIds.remove(word.id);
    }
  }

  void _recordAttempt({
    required _VocMode mode,
    required _VocWord word,
    required String prompt,
    required String userAnswer,
    required String correctAnswer,
    required bool correct,
  }) {
    _attempts.removeWhere(
      (attempt) => attempt.mode == mode && attempt.wordId == word.id,
    );
    _attempts.add(
      _VocAttempt(
        mode: mode,
        wordId: word.id,
        prompt: prompt,
        userAnswer: userAnswer,
        correctAnswer: correctAnswer,
        correct: correct,
      ),
    );
  }

  void _recordFirstSpeakingAttempt({
    required _VocWord word,
    required String userAnswer,
    required bool correct,
  }) {
    final alreadyRecorded = _attempts.any(
      (attempt) =>
          attempt.mode == _VocMode.speaking && attempt.wordId == word.id,
    );
    if (alreadyRecorded) {
      return;
    }

    _attempts.add(
      _VocAttempt(
        mode: _VocMode.speaking,
        wordId: word.id,
        prompt: word.word,
        userAnswer: userAnswer,
        correctAnswer: word.word,
        correct: correct,
      ),
    );
  }

  void _nextOrFinish(List<_VocWord> words) {
    if (_mode == _VocMode.speaking ||
        _mode == _VocMode.multipleChoice ||
        _mode == _VocMode.writeGreek ||
        _mode == _VocMode.writeForeign) {
      if (_wordIndex >= words.length - 1) {
        _showScoreDialog(_mode!);
        return;
      }
    }

    _moveWord(1, words);
  }

  void _showScoreDialog(_VocMode mode) {
    final attempts = _attempts
        .where((attempt) => attempt.mode == mode)
        .toList();
    final total = attempts.length;
    final correct = attempts.where((attempt) => attempt.correct).length;
    final wrong = attempts.where((attempt) => !attempt.correct).toList();
    final percent = total == 0 ? 0 : ((correct / total) * 100).round();
    if (widget.assignmentSession != null && !_assignmentResultSaved) {
      _assignmentResultSaved = true;
      _assignmentSaveFuture = _saveAssignmentResult(percent);
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text('Βαθμολογία: $percent%'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '$correct/$total σωστά',
                    style: const TextStyle(
                      color: Color(0xFF173A8A),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (wrong.isEmpty)
                    const Text(
                      'Δεν υπήρχαν λάθη.',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    )
                  else ...[
                    const Text(
                      'Λάθος λέξεις/φράσεις:',
                      style: TextStyle(
                        color: Color(0xFF7D1010),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final attempt in wrong) ...[
                              _WrongAttemptCard(attempt: attempt),
                              const SizedBox(height: 10),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () async {
                  await _assignmentSaveFuture;
                  if (!dialogContext.mounted || !mounted) return;
                  Navigator.of(dialogContext).pop();
                  if (widget.assignmentSession != null) {
                    Navigator.of(context).pop();
                  } else {
                    _selectMode(null);
                  }
                },
                child: Text(
                  widget.assignmentSession == null
                      ? 'Μενού'
                      : 'Επιστροφή στις ασκήσεις',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveAssignmentResult(int percent) async {
    final session = widget.assignmentSession;
    if (session == null) return;
    try {
      if (_usesPersonalWords) {
        final correctWordIds = _attempts
            .where((attempt) => attempt.correct)
            .map((attempt) => attempt.wordId)
            .toSet()
            .toList();
        try {
          await Supabase.instance.client.rpc(
            'record_personal_vocabulary_assignment_successes',
            params: {
              'input_assignment_id': session.assignmentId,
              'input_student_id': widget.studentId,
              'input_class_id': widget.classId,
              'input_vocabulary_word_ids': correctWordIds,
            },
          );
        } catch (_) {
          // Η βαθμολογία της άσκησης αποθηκεύεται ακόμη κι αν αποτύχει
          // προσωρινά ο συγχρονισμός της προσωπικής λίστας.
        }
      }
      final passed = await session.saveProgress(
        progress: percent,
        scorePercentage: percent.toDouble(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            passed
                ? 'Η άσκηση ολοκληρώθηκε με $percent%!'
                : 'Χρειάζεσαι τουλάχιστον 71%. Μπορείς να προσπαθήσεις ξανά.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Δεν αποθηκεύτηκε η προσπάθεια: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: FutureBuilder<List<_VocWord>>(
          future: _wordsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _StateMessage(
                icon: Icons.error_outline_rounded,
                text:
                    'Δεν μπορέσαμε να φορτώσουμε το λεξιλόγιο.\n${snapshot.error}',
                onBack: () => Navigator.of(context).pop(),
              );
            }

            final allWords = snapshot.data ?? const [];
            final units = _buildUnits(allWords);

            if (allWords.isEmpty) {
              return _StateMessage(
                icon: Icons.style_outlined,
                text: 'Δεν υπάρχουν λέξεις για αυτό το βιβλίο ακόμα.',
                onBack: () => Navigator.of(context).pop(),
              );
            }

            final selectedWords = _usesPersonalWords
                ? allWords
                : allWords
                      .where(
                        (word) =>
                            word.unitKey == _selectedUnit &&
                            (!_importantOnly || word.isImportant),
                      )
                      .toList();
            final words = _mode == _VocMode.study
                ? selectedWords
                      .where((word) => !_learnedWordIds.contains(word.id))
                      .toList()
                : selectedWords;
            final studyCompleted =
                _mode == _VocMode.study &&
                selectedWords.isNotEmpty &&
                words.isEmpty;

            if (widget.assignmentSession != null &&
                !_assignmentPreviewCompleted &&
                selectedWords.isNotEmpty) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
                children: [
                  AssignmentWordPreview(
                    words: selectedWords
                        .map(
                          (word) => AssignmentPreviewWord(
                            id: word.id,
                            word: word.word,
                            translation: word.translationGr,
                            partOfSpeech: word.partOfSpeech,
                          ),
                        )
                        .toList(),
                    onCompleted: () {
                      setState(() {
                        _assignmentPreviewCompleted = true;
                        _wordIndex = 0;
                        _resetQuestionState();
                      });
                    },
                  ),
                ],
              );
            }

            if (_mode == null || (words.isEmpty && !studyCompleted)) {
              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  _StudyVocHome(
                    units: units,
                    selectedUnit: _selectedUnit,
                    importantOnly: _importantOnly,
                    unitValidationError: _unitValidationError,
                    onBack: () => Navigator.of(context).pop(),
                    onUnitChanged: _selectUnit,
                    onImportantChanged: (value) {
                      setState(() {
                        _importantOnly = value;
                        _wordIndex = 0;
                        _attempts.clear();
                        _resetQuestionState();
                      });
                    },
                    onModeSelected: _selectMode,
                    showEmptyMessage: _selectedUnit != null && words.isEmpty,
                  ),
                ],
              );
            }

            if (studyCompleted) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  _ModeHeader(
                    mode: _VocMode.study,
                    onBack: () => _selectMode(null),
                  ),
                  const SizedBox(height: 14),
                  _StudyCompletedCard(
                    wordCount: selectedWords.length,
                    onReviewAgain: () {
                      setState(() {
                        _learnedWordIds.removeAll(
                          selectedWords.map((word) => word.id),
                        );
                        _wordIndex = 0;
                        _resetQuestionState();
                      });
                    },
                  ),
                ],
              );
            }

            final currentIndex = _wordIndex.clamp(0, words.length - 1).toInt();
            final current = words[currentIndex];

            if (_mode == _VocMode.multipleChoice) {
              _prepareChoices(words, current);
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                _ModeHeader(mode: _mode!, onBack: () => _selectMode(null)),
                const SizedBox(height: 14),
                _ModeBody(
                  mode: _mode!,
                  word: current,
                  studyWords: words,
                  studyController: _studySwiperController,
                  currentIndex: currentIndex,
                  wordCount: words.length,
                  isFlipped: _isFlipped,
                  choices: _multipleChoices,
                  selectedChoice: _selectedChoice,
                  lastAnswerCorrect: _lastAnswerCorrect,
                  spokenText: _spokenText,
                  isListening: _isListening,
                  answerController: _answerController,
                  onSpeak: () => _speak(current),
                  onStudySpeak: _speak,
                  onStudyIndexChanged: (index) {
                    if (!mounted || _mode != _VocMode.study) return;
                    setState(() {
                      _wordIndex = index;
                      _resetQuestionState();
                    });
                  },
                  onStudyLearned: () {
                    setState(() {
                      _learnedWordIds.add(current.id);
                      final remainingCount = words.length - 1;
                      _wordIndex = remainingCount == 0
                          ? 0
                          : currentIndex.clamp(0, remainingCount - 1);
                      _resetQuestionState();
                    });
                  },
                  onFlip: () => setState(() => _isFlipped = !_isFlipped),
                  onListen: () => _toggleListening(current),
                  onChoiceSelected: (choice) {
                    final isCorrect = choice == current.translationGr;
                    setState(() {
                      _selectedChoice = choice;
                      _lastAnswerCorrect = isCorrect;
                      _recordAttempt(
                        mode: _VocMode.multipleChoice,
                        word: current,
                        prompt: current.word,
                        userAnswer: choice,
                        correctAnswer: current.translationGr,
                        correct: isCorrect,
                      );
                    });
                    if (!isCorrect) {
                      unawaited(_recordVocabularyMistake(current, choice));
                    }
                    if (isCorrect) {
                      _speak(current);
                    }
                  },
                  onCheckGreek: () =>
                      _checkWrittenAnswer(current, toGreek: true),
                  onCheckForeign: () =>
                      _checkWrittenAnswer(current, toGreek: false),
                  onNext: () => _nextOrFinish(words),
                ),
                const SizedBox(height: 14),
                Text(
                  '${currentIndex + 1}/${words.length}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF173A8A),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                _ExerciseMascot(
                  mode: _mode!,
                  isCorrect: _lastAnswerCorrect == true,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StudyVocHome extends StatelessWidget {
  const _StudyVocHome({
    required this.units,
    required this.selectedUnit,
    required this.importantOnly,
    required this.unitValidationError,
    required this.onBack,
    required this.onUnitChanged,
    required this.onImportantChanged,
    required this.onModeSelected,
    required this.showEmptyMessage,
  });

  final List<_VocUnit> units;
  final String? selectedUnit;
  final bool importantOnly;
  final bool unitValidationError;
  final VoidCallback onBack;
  final ValueChanged<String?> onUnitChanged;
  final ValueChanged<bool> onImportantChanged;
  final ValueChanged<_VocMode> onModeSelected;
  final bool showEmptyMessage;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 390;

    return Container(
      constraints: BoxConstraints(
        minHeight:
            MediaQuery.sizeOf(context).height -
            MediaQuery.paddingOf(context).vertical,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFCFA), Color(0xFFF8F8FF), Color(0xFFEEF3FF)],
          stops: [0, 0.52, 1],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            top: -80,
            right: -70,
            child: _SoftGlow(color: Color(0x337E6BFF), size: 230),
          ),
          const Positioned(
            top: 80,
            left: -90,
            child: _SoftGlow(color: Color(0x22FF9B63), size: 210),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 14 : 20,
              compact ? 12 : 18,
              compact ? 14 : 20,
              34,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StudyVocHero(onBack: onBack, compact: compact),
                SizedBox(height: compact ? 14 : 20),
                _StudyVocSettings(
                  units: units,
                  selectedUnit: selectedUnit,
                  importantOnly: importantOnly,
                  unitValidationError: unitValidationError,
                  onUnitChanged: onUnitChanged,
                  onImportantChanged: onImportantChanged,
                  compact: compact,
                ),
                const SizedBox(height: 16),
                _ModeMenu(onSelected: onModeSelected),
                if (showEmptyMessage) ...[
                  const SizedBox(height: 6),
                  const _EmptyUnitMessage(),
                ],
                const SizedBox(height: 22),
                const _StudyVocFooterDecoration(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StudyVocHero extends StatelessWidget {
  const _StudyVocHero({required this.onBack, required this.compact});

  final VoidCallback onBack;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Material(
              color: Colors.white.withValues(alpha: 0.92),
              shape: const CircleBorder(),
              elevation: 6,
              shadowColor: const Color(0x26D52323),
              child: InkWell(
                onTap: onBack,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: compact ? 50 : 58,
                  height: compact ? 50 : 58,
                  child: Icon(
                    Icons.close_rounded,
                    color: const Color(0xFFE32636),
                    size: compact ? 37 : 43,
                    weight: 900,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Study your voc',
                maxLines: 2,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFF28116B),
                  fontSize: compact ? 31 : 38,
                  fontWeight: FontWeight.w900,
                  height: 0.98,
                  letterSpacing: -1.2,
                  shadows: const [
                    Shadow(
                      color: Color(0x20754EF2),
                      blurRadius: 14,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: compact ? 88 : 112,
              height: compact ? 92 : 116,
              child: Image.asset(
                'lib/img/studyyourvoc.png',
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
        Transform.translate(
          offset: const Offset(0, -4),
          child: Text(
            'Μελέτησε, εξάσκησε και\nβελτίωσε το λεξιλόγιό σου!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF77718F),
              fontSize: compact ? 17 : 20,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _StudyVocSettings extends StatelessWidget {
  const _StudyVocSettings({
    required this.units,
    required this.selectedUnit,
    required this.importantOnly,
    required this.unitValidationError,
    required this.onUnitChanged,
    required this.onImportantChanged,
    required this.compact,
  });

  final List<_VocUnit> units;
  final String? selectedUnit;
  final bool importantOnly;
  final bool unitValidationError;
  final ValueChanged<String?> onUnitChanged;
  final ValueChanged<bool> onImportantChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x1F7964EE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x126051B4),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: compact ? 82 : 92,
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: unitValidationError
                  ? const Color(0xFFFFF2F2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: unitValidationError
                    ? const Color(0xFFE32636)
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                const _SettingsIcon(
                  icon: Icons.menu_book_rounded,
                  foreground: Color(0xFF7448EC),
                  background: Color(0xFFF2EDFF),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ενότητα',
                        style: TextStyle(
                          color: unitValidationError
                              ? const Color(0xFFE32636)
                              : const Color(0xFF2A1B50),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedUnit,
                          isDense: true,
                          isExpanded: true,
                          icon: _RoundTrailingIcon(
                            icon: Icons.keyboard_arrow_down_rounded,
                            color: unitValidationError
                                ? const Color(0xFFE32636)
                                : const Color(0xFF6940EB),
                          ),
                          hint: Text(
                            'Επέλεξε ενότητα να μελετήσεις',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: unitValidationError
                                  ? const Color(0xFFE32636)
                                  : const Color(0xFF77718F),
                              fontSize: compact ? 14 : 15,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                          borderRadius: BorderRadius.circular(18),
                          style: const TextStyle(
                            color: Color(0xFF22134F),
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                          items: [
                            for (final unit in units)
                              DropdownMenuItem(
                                value: unit.value,
                                child: Text(
                                  unit.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: onUnitChanged,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0x1F7964EE)),
          SizedBox(
            height: compact ? 76 : 84,
            child: Row(
              children: [
                const _SettingsIcon(
                  icon: Icons.star_rounded,
                  foreground: Color(0xFFFFBD18),
                  background: Color(0xFFFFF5E7),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Σημαντικές λέξεις μόνο',
                    style: TextStyle(
                      color: Color(0xFF25174E),
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: importantOnly,
                  activeTrackColor: const Color(0xFF7547EF),
                  activeThumbColor: Colors.white,
                  onChanged: onImportantChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, color: foreground, size: 31),
    );
  }
}

class _RoundTrailingIcon extends StatelessWidget {
  const _RoundTrailingIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: const BoxDecoration(
        color: Color(0xFFF7F5FF),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 31),
    );
  }
}

class _SoftGlow extends StatelessWidget {
  const _SoftGlow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}

class _EmptyUnitMessage extends StatelessWidget {
  const _EmptyUnitMessage();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5D8),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Text(
        'Δεν υπάρχουν important words για αυτή την ενότητα.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFF173A8A),
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ModeMenu extends StatelessWidget {
  const _ModeMenu({required this.onSelected});

  final ValueChanged<_VocMode> onSelected;

  @override
  Widget build(BuildContext context) {
    const modes = [
      (
        _VocMode.study,
        'Μελέτη',
        'Διάβασε και μάθε\nτο λεξιλόγιο',
        Icons.menu_book_rounded,
        Color(0xFF6840E8),
        Color(0xFFF5F0FF),
      ),
      (
        _VocMode.speaking,
        'Προφορικά',
        'Πες τις λέξεις δυνατά\nκαι εξάσκησε την προφορά σου',
        Icons.record_voice_over_rounded,
        Color(0xFF239A39),
        Color(0xFFF0FFF2),
      ),
      (
        _VocMode.multipleChoice,
        'Quiz',
        'Απάντησε σε ερωτήσεις\nπολλαπλής επιλογής',
        Icons.quiz_rounded,
        Color(0xFFFF7A08),
        Color(0xFFFFF8ED),
      ),
      (
        _VocMode.writeForeign,
        'Ελληνικά – Ξένη Γλώσσα',
        'Μετάφρασε από τα ελληνικά\nστη ξένη γλώσσα',
        Icons.translate_rounded,
        Color(0xFF2468E8),
        Color(0xFFF0F6FF),
      ),
      (
        _VocMode.writeGreek,
        'Ξένη Γλώσσα – Ελληνικά',
        'Μετάφρασε από τη ξένη γλώσσα\nστα ελληνικά',
        Icons.edit_rounded,
        Color(0xFFFF4F59),
        Color(0xFFFFF2F4),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final mode in modes) ...[
          _ModeMenuCard(
            label: mode.$2,
            description: mode.$3,
            icon: mode.$4,
            color: mode.$5,
            background: mode.$6,
            onTap: () => onSelected(mode.$1),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ModeMenuCard extends StatelessWidget {
  const _ModeMenuCard({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.background,
    required this.onTap,
  });

  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(26),
      elevation: 3,
      shadowColor: const Color(0x126051B4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color.withValues(alpha: 0.68), color],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.22),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 42),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF514B63),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.82),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white),
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: color,
                  size: 31,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudyVocFooterDecoration extends StatelessWidget {
  const _StudyVocFooterDecoration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 20,
            bottom: 2,
            child: Transform.rotate(
              angle: -0.12,
              child: Container(
                width: 108,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFA14EED), Color(0xFFE89CFF)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x307D48D8),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: Colors.white70,
                  size: 27,
                ),
              ),
            ),
          ),
          const Positioned(
            right: 122,
            bottom: 28,
            child: Icon(Icons.circle, color: Color(0xFF21CBE4), size: 13),
          ),
          const Positioned(
            right: 52,
            bottom: 1,
            child: Icon(
              Icons.star_rounded,
              color: Color(0xFFFFC81F),
              size: 52,
              shadows: [
                Shadow(
                  color: Color(0x45D69A00),
                  blurRadius: 7,
                  offset: Offset(0, 4),
                ),
              ],
            ),
          ),
          const Positioned(
            right: 3,
            bottom: 42,
            child: Icon(Icons.auto_awesome, color: Color(0xFF5B9CFF), size: 28),
          ),
        ],
      ),
    );
  }
}

class _ModeHeader extends StatelessWidget {
  const _ModeHeader({required this.mode, required this.onBack});

  final _VocMode mode;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: onBack,
          borderRadius: BorderRadius.circular(18),
          child: const SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF8E8E93),
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _modeLabel(mode),
            style: const TextStyle(
              color: Color(0xFF4D4AAD),
              fontSize: 24,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
        ),
      ],
    );
  }
}

class _ExerciseMascot extends StatelessWidget {
  const _ExerciseMascot({required this.mode, required this.isCorrect});

  final _VocMode mode;
  final bool isCorrect;

  String get _assetPath {
    if (mode == _VocMode.study) {
      return 'lib/img/studying.png';
    }

    if (isCorrect) {
      return 'lib/img/happyboy.png';
    }

    if (mode == _VocMode.speaking) {
      return 'lib/img/talking.png';
    }

    return 'lib/img/puzzled.png';
  }

  @override
  Widget build(BuildContext context) {
    final assetPath = _assetPath;
    final imageHeight = min(MediaQuery.sizeOf(context).width * 0.72, 280.0);

    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
              child: child,
            ),
          );
        },
        child: Image.asset(
          assetPath,
          key: ValueKey(assetPath),
          height: imageHeight,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _ModeBody extends StatelessWidget {
  const _ModeBody({
    required this.mode,
    required this.word,
    required this.studyWords,
    required this.studyController,
    required this.currentIndex,
    required this.wordCount,
    required this.isFlipped,
    required this.choices,
    required this.selectedChoice,
    required this.lastAnswerCorrect,
    required this.spokenText,
    required this.isListening,
    required this.answerController,
    required this.onSpeak,
    required this.onStudySpeak,
    required this.onStudyIndexChanged,
    required this.onStudyLearned,
    required this.onFlip,
    required this.onListen,
    required this.onChoiceSelected,
    required this.onCheckGreek,
    required this.onCheckForeign,
    required this.onNext,
  });

  final _VocMode mode;
  final _VocWord word;
  final List<_VocWord> studyWords;
  final CardSwiperController studyController;
  final int currentIndex;
  final int wordCount;
  final bool isFlipped;
  final List<String> choices;
  final String? selectedChoice;
  final bool? lastAnswerCorrect;
  final String spokenText;
  final bool isListening;
  final TextEditingController answerController;
  final VoidCallback onSpeak;
  final ValueChanged<_VocWord> onStudySpeak;
  final ValueChanged<int> onStudyIndexChanged;
  final VoidCallback onStudyLearned;
  final VoidCallback onFlip;
  final VoidCallback onListen;
  final ValueChanged<String> onChoiceSelected;
  final VoidCallback onCheckGreek;
  final VoidCallback onCheckForeign;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case _VocMode.study:
        return _StudyCardStack(
          words: studyWords,
          controller: studyController,
          currentIndex: currentIndex,
          isFlipped: isFlipped,
          onSpeak: onStudySpeak,
          onFlip: onFlip,
          onIndexChanged: onStudyIndexChanged,
          onLearned: onStudyLearned,
        );
      case _VocMode.speaking:
        return _SpeakingCard(
          word: word,
          spokenText: spokenText,
          isListening: isListening,
          lastAnswerCorrect: lastAnswerCorrect,
          onSpeak: onSpeak,
          onListen: onListen,
          onNext: onNext,
        );
      case _VocMode.multipleChoice:
        return _MultipleChoiceCard(
          word: word,
          choices: choices,
          selectedChoice: selectedChoice,
          lastAnswerCorrect: lastAnswerCorrect,
          onSelected: onChoiceSelected,
          onNext: onNext,
        );
      case _VocMode.writeGreek:
        return _WrittenCard(
          prompt: word.word,
          helper: 'Γράψε την ελληνική σημασία',
          controller: answerController,
          lastAnswerCorrect: lastAnswerCorrect,
          correctAnswer: word.translationGr,
          lockCheckAfterAnswer: false,
          onSpeak: onSpeak,
          onCheck: onCheckGreek,
          onNext: onNext,
        );
      case _VocMode.writeForeign:
        return _WrittenCard(
          prompt: word.translationGr,
          helper: 'Γράψε τη λέξη στη ξένη γλώσσα',
          controller: answerController,
          lastAnswerCorrect: lastAnswerCorrect,
          correctAnswer: word.word,
          lockCheckAfterAnswer: true,
          onSpeak: null,
          onCheck: onCheckForeign,
          onNext: onNext,
        );
    }
  }
}

class _StudyCompletedCard extends StatelessWidget {
  const _StudyCompletedCard({
    required this.wordCount,
    required this.onReviewAgain,
  });

  final int wordCount;
  final VoidCallback onReviewAgain;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF0FFF3), Color(0xFFDDF7E5)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.celebration_rounded,
            color: Color(0xFF178A45),
            size: 76,
          ),
          const SizedBox(height: 16),
          const Text(
            'Μπράβο!',
            style: TextStyle(
              color: Color(0xFF173A8A),
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Έμαθες και τις $wordCount λέξεις αυτής της ενότητας.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF526078),
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 26),
          OutlinedButton.icon(
            onPressed: onReviewAgain,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Επανάληψη όλων'),
          ),
        ],
      ),
    );
  }
}

class _StudyCardStack extends StatelessWidget {
  const _StudyCardStack({
    required this.words,
    required this.controller,
    required this.currentIndex,
    required this.isFlipped,
    required this.onSpeak,
    required this.onFlip,
    required this.onIndexChanged,
    required this.onLearned,
  });

  final List<_VocWord> words;
  final CardSwiperController controller;
  final int currentIndex;
  final bool isFlipped;
  final ValueChanged<_VocWord> onSpeak;
  final VoidCallback onFlip;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback onLearned;

  @override
  Widget build(BuildContext context) {
    final visibleCards = min(words.length, 3);

    return SizedBox(
      height: 390,
      child: CardSwiper(
        key: ValueKey('${words.first.id}-${words.length}'),
        controller: controller,
        cardsCount: words.length,
        initialIndex: currentIndex,
        numberOfCardsDisplayed: visibleCards,
        isLoop: true,
        duration: const Duration(milliseconds: 320),
        threshold: 35,
        maxAngle: 18,
        scale: 0.92,
        backCardOffset: const Offset(0, 24),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 38),
        onSwipe: (previousIndex, nextIndex, direction) {
          if (nextIndex != null) {
            onIndexChanged(nextIndex);
          }
          return true;
        },
        cardBuilder: (context, index, percentX, percentY) {
          final word = words[index];
          return _StudyFlashCard(
            key: ValueKey(word.id),
            word: word,
            isFlipped: index == currentIndex && isFlipped,
            onSpeak: () => onSpeak(word),
            onFlip: onFlip,
            onLearned: onLearned,
          );
        },
      ),
    );
  }
}

class _StudyFlashCard extends StatelessWidget {
  const _StudyFlashCard({
    super.key,
    required this.word,
    required this.isFlipped,
    required this.onSpeak,
    required this.onFlip,
    required this.onLearned,
  });

  final _VocWord word;
  final bool isFlipped;
  final VoidCallback onSpeak;
  final VoidCallback onFlip;
  final VoidCallback onLearned;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onFlip,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: isFlipped ? pi : 0),
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeInOutCubic,
        builder: (context, angle, _) {
          final showBack = angle >= pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(angle),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: showBack
                      ? const [Color(0xFFFFFAE9), Color(0xFFFFEFC2)]
                      : const [Color(0xFFFDFEFF), Color(0xFFEAF5FF)],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white, width: 1.6),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x246051B4),
                    blurRadius: 24,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.rotationY(showBack ? pi : 0),
                child: Stack(
                  children: [
                    Positioned(
                      top: -48,
                      right: -32,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              (showBack
                                      ? const Color(0xFFFFBD18)
                                      : const Color(0xFF5D65EA))
                                  .withValues(alpha: 0.12),
                        ),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!showBack)
                            IconButton.filled(
                              onPressed: onSpeak,
                              icon: const Icon(Icons.volume_up_rounded),
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFF5D4BE2),
                                foregroundColor: Colors.white,
                                fixedSize: const Size(54, 54),
                              ),
                            ),
                          SizedBox(height: showBack ? 0 : 20),
                          Text(
                            showBack ? word.translationGr : word.word,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF173A8A),
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              height: 1.08,
                            ),
                          ),
                          if (word.partOfSpeech != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              word.partOfSpeech!,
                              style: const TextStyle(
                                color: Color(0xFF6B6B78),
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          Text(
                            showBack
                                ? 'Πάτησε για τη λέξη • Σύρε για επόμενη'
                                : 'Πάτησε για μετάφραση • Σύρε για επόμενη',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF77718F),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: onLearned,
                            icon: const Icon(Icons.task_alt_rounded),
                            label: const Text('Την έμαθα'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFDDF5E5),
                              foregroundColor: const Color(0xFF24734A),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 12,
                              ),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: const BorderSide(
                                  color: Color(0xFFB9E5C8),
                                ),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SpeakingCard extends StatelessWidget {
  const _SpeakingCard({
    required this.word,
    required this.spokenText,
    required this.isListening,
    required this.lastAnswerCorrect,
    required this.onSpeak,
    required this.onListen,
    required this.onNext,
  });

  final _VocWord word;
  final String spokenText;
  final bool isListening;
  final bool? lastAnswerCorrect;
  final VoidCallback onSpeak;
  final VoidCallback onListen;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _PracticePanel(
      backgroundColor: lastAnswerCorrect == false
          ? const Color(0xFFFFE2E2)
          : const Color(0xFFEAF7FF),
      borderColor: lastAnswerCorrect == false
          ? const Color(0xFFE32636)
          : Colors.transparent,
      children: [
        Text(
          word.word,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF173A8A),
            fontSize: 34,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filled(
              onPressed: onSpeak,
              icon: const Icon(Icons.volume_up_rounded),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF4D4AAD),
                foregroundColor: Colors.white,
                fixedSize: const Size(58, 58),
              ),
            ),
            const SizedBox(width: 16),
            IconButton.filled(
              onPressed: onListen,
              icon: Icon(isListening ? Icons.stop_rounded : Icons.mic_rounded),
              style: IconButton.styleFrom(
                backgroundColor: isListening
                    ? const Color(0xFF7D1010)
                    : const Color(0xFF2D7D10),
                foregroundColor: Colors.white,
                fixedSize: const Size(66, 66),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          isListening
              ? 'Ακούω...'
              : spokenText.isEmpty
              ? 'Πάτα το μικρόφωνο και πες τη λέξη.'
              : spokenText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF173A8A),
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (lastAnswerCorrect == true) ...[
          const SizedBox(height: 18),
          FilledButton(onPressed: onNext, child: const Text('Επόμενη')),
        ],
      ],
    );
  }
}

class _MultipleChoiceCard extends StatelessWidget {
  const _MultipleChoiceCard({
    required this.word,
    required this.choices,
    required this.selectedChoice,
    required this.lastAnswerCorrect,
    required this.onSelected,
    required this.onNext,
  });

  final _VocWord word;
  final List<String> choices;
  final String? selectedChoice;
  final bool? lastAnswerCorrect;
  final ValueChanged<String> onSelected;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _PracticePanel(
      children: [
        Text(
          word.word,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF173A8A),
            fontSize: 32,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 22),
        for (final choice in choices) ...[
          _ChoiceButton(
            label: choice,
            selected: selectedChoice == choice,
            correct: selectedChoice == null
                ? null
                : choice == word.translationGr,
            onTap: () => onSelected(choice),
          ),
          const SizedBox(height: 10),
        ],
        _AnswerResult(correct: lastAnswerCorrect),
        if (selectedChoice != null)
          FilledButton(onPressed: onNext, child: const Text('Επόμενη')),
      ],
    );
  }
}

class _WrittenCard extends StatelessWidget {
  const _WrittenCard({
    required this.prompt,
    required this.helper,
    required this.controller,
    required this.lastAnswerCorrect,
    required this.correctAnswer,
    required this.lockCheckAfterAnswer,
    required this.onSpeak,
    required this.onCheck,
    required this.onNext,
  });

  final String prompt;
  final String helper;
  final TextEditingController controller;
  final bool? lastAnswerCorrect;
  final String correctAnswer;
  final bool lockCheckAfterAnswer;
  final VoidCallback? onSpeak;
  final VoidCallback onCheck;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final checkDisabled =
        lastAnswerCorrect == false ||
        (lockCheckAfterAnswer && lastAnswerCorrect != null);

    return _PracticePanel(
      children: [
        if (onSpeak != null)
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: onSpeak,
              icon: const Icon(Icons.volume_up_rounded),
              color: const Color(0xFF4D4AAD),
            ),
          ),
        Text(
          prompt,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF173A8A),
            fontSize: 32,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 22),
        TextField(
          controller: controller,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!checkDisabled) {
              onCheck();
            }
          },
          decoration: InputDecoration(
            hintText: helper,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: checkDisabled ? null : onCheck,
          child: const Text('Έλεγχος'),
        ),
        _AnswerResult(correct: lastAnswerCorrect, correctAnswer: correctAnswer),
        if (lastAnswerCorrect != null)
          FilledButton(onPressed: onNext, child: const Text('Επόμενη')),
      ],
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
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
    Color background = Colors.white;
    Color foreground = const Color(0xFF173A8A);

    if (selected && correct == true) {
      background = const Color(0xFF82FE63);
      foreground = const Color(0xFF2D7D10);
    } else if (selected && correct == false) {
      background = const Color(0xFFFFD7D7);
      foreground = const Color(0xFF7D1010);
    } else if (correct == true) {
      background = const Color(0xFFE8FFE3);
      foreground = const Color(0xFF2D7D10);
    }

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foreground,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _PracticePanel extends StatelessWidget {
  const _PracticePanel({
    required this.children,
    this.backgroundColor = const Color(0xFFEAF7FF),
    this.borderColor = Colors.transparent,
  });

  final List<Widget> children;
  final Color backgroundColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _AnswerResult extends StatelessWidget {
  const _AnswerResult({required this.correct, this.correctAnswer});

  final bool? correct;
  final String? correctAnswer;

  @override
  Widget build(BuildContext context) {
    if (correct == null) {
      return const SizedBox(height: 12);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        correct!
            ? 'Σωστό'
            : correctAnswer == null
            ? 'Δοκίμασε ξανά'
            : 'Σωστό: $correctAnswer',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: correct! ? const Color(0xFF2D7D10) : const Color(0xFF7D1010),
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _WrongAttemptCard extends StatelessWidget {
  const _WrongAttemptCard({required this.attempt});

  final _VocAttempt attempt;

  @override
  Widget build(BuildContext context) {
    final showLetterDiff = attempt.mode == _VocMode.writeForeign;
    final showInlineAnswer =
        attempt.mode == _VocMode.multipleChoice ||
        attempt.mode == _VocMode.writeGreek ||
        attempt.mode == _VocMode.writeForeign;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x33FF1010)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showInlineAnswer)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                Text(
                  '${attempt.prompt} =',
                  style: const TextStyle(
                    color: Color(0xFF173A8A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (showLetterDiff)
                  _LetterDiffText(
                    typed: attempt.userAnswer,
                    correct: attempt.correctAnswer,
                  )
                else
                  Text(
                    attempt.userAnswer.isEmpty ? '-' : attempt.userAnswer,
                    style: const TextStyle(
                      color: Color(0xFFB3261E),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                Text(
                  attempt.correctAnswer,
                  style: const TextStyle(
                    color: Color(0xFF2D7D10),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            )
          else ...[
            Text(
              attempt.prompt,
              style: const TextStyle(
                color: Color(0xFF173A8A),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            if (showLetterDiff)
              _LetterDiffText(
                typed: attempt.userAnswer,
                correct: attempt.correctAnswer,
              )
            else
              Text(
                attempt.userAnswer.isEmpty ? '-' : attempt.userAnswer,
                style: const TextStyle(
                  color: Color(0xFFB3261E),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            const SizedBox(height: 5),
            Text(
              attempt.correctAnswer,
              style: const TextStyle(
                color: Color(0xFF2D7D10),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LetterDiffText extends StatelessWidget {
  const _LetterDiffText({required this.typed, required this.correct});

  final String typed;
  final String correct;

  @override
  Widget build(BuildContext context) {
    final typedText = typed.trim();
    final correctText = correct.trim();

    if (typedText.isEmpty) {
      return const Text(
        '-',
        style: TextStyle(
          color: Color(0xFFB3261E),
          fontSize: 15,
          fontWeight: FontWeight.w800,
          decoration: TextDecoration.lineThrough,
        ),
      );
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(
          decoration: TextDecoration.lineThrough,
          decorationColor: Color(0xFFB3261E),
          decorationThickness: 2,
        ),
        children: [
          for (var index = 0; index < typedText.length; index++)
            TextSpan(
              text: typedText[index],
              style: TextStyle(
                color:
                    index < correctText.length &&
                        typedText[index].toLowerCase() ==
                            correctText[index].toLowerCase()
                    ? const Color(0xFF2D7D10)
                    : const Color(0xFFB3261E),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
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
          Icon(icon, size: 54, color: const Color(0xFF4D4AAD)),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF173A8A),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _VocUnit {
  const _VocUnit({required this.value, required this.label});

  final String value;
  final String label;
}

class _VocAttempt {
  const _VocAttempt({
    required this.mode,
    required this.wordId,
    required this.prompt,
    required this.userAnswer,
    required this.correctAnswer,
    required this.correct,
  });

  final _VocMode mode;
  final String wordId;
  final String prompt;
  final String userAnswer;
  final String correctAnswer;
  final bool correct;
}

class _VocWord {
  const _VocWord({
    required this.id,
    required this.language,
    required this.unit,
    required this.unitOrder,
    required this.word,
    required this.translationGr,
    required this.acceptedWords,
    required this.partOfSpeech,
    required this.isImportant,
  });

  factory _VocWord.fromRow(Map<String, dynamic> row) {
    return _VocWord(
      id: _readText(row['id']) ?? '',
      language: _readText(row['language']) ?? '',
      unit: _readText(row['unit']) ?? 'Ενότητα',
      unitOrder: row['unit_order'] is num
          ? (row['unit_order'] as num).toInt()
          : null,
      word: _readText(row['word']) ?? '',
      translationGr: _readText(row['translation_gr']) ?? '',
      acceptedWords: _readText(row['accepted_words']),
      partOfSpeech: _readText(row['part_of_speech']),
      isImportant: row['is_important'] == true,
    );
  }

  final String id;
  final String language;
  final String unit;
  final int? unitOrder;
  final String word;
  final String translationGr;
  final String? acceptedWords;
  final String? partOfSpeech;
  final bool isImportant;

  String get unitKey => '${unitOrder ?? 999999}::$unit';

  List<String> get acceptedAnswers {
    final answers = <String>[translationGr];
    if (acceptedWords != null) {
      answers.addAll(
        acceptedWords!
            .split('|')
            .map((answer) => answer.trim())
            .where((answer) => answer.isNotEmpty),
      );
    }
    return answers.toSet().toList();
  }
}

List<_VocUnit> _buildUnits(List<_VocWord> words) {
  final units = <String, _VocUnit>{};
  for (final word in words) {
    units[word.unitKey] = _VocUnit(value: word.unitKey, label: word.unit);
  }
  return units.values.toList();
}

String? _readText(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

String _ttsLanguage(String language) {
  switch (language.trim().toLowerCase()) {
    case 'english':
      return 'en-US';
    case 'spanish':
      return 'es-ES';
    case 'french':
      return 'fr-FR';
    case 'german':
      return 'de-DE';
    default:
      return 'en-US';
  }
}

String _speechLanguage(String language) {
  switch (language.trim().toLowerCase()) {
    case 'english':
      return 'en_US';
    case 'spanish':
      return 'es_ES';
    case 'french':
      return 'fr_FR';
    case 'german':
      return 'de_DE';
    default:
      return 'en_US';
  }
}

String _modeLabel(_VocMode mode) {
  switch (mode) {
    case _VocMode.study:
      return 'Μελέτη';
    case _VocMode.speaking:
      return 'Προφορικά';
    case _VocMode.multipleChoice:
      return 'Quiz';
    case _VocMode.writeGreek:
      return 'Ξένη Γλώσσα – Ελληνικά';
    case _VocMode.writeForeign:
      return 'Ελληνικά – Ξένη Γλώσσα';
  }
}

bool _answersMatch(String typed, String correct) {
  final normalizedTyped = _normalizeAnswer(typed);
  final normalizedCorrect = _normalizeAnswer(correct);

  if (normalizedTyped.isEmpty || normalizedCorrect.isEmpty) {
    return false;
  }

  if (normalizedTyped == normalizedCorrect) {
    return true;
  }

  final distance = _levenshtein(normalizedTyped, normalizedCorrect);
  final tolerance = normalizedCorrect.length >= 8 ? 2 : 1;
  return distance <= tolerance;
}

bool _exactAnswerMatch(String typed, String correct) {
  return _normalizeAnswer(typed) == _normalizeAnswer(correct);
}

String _normalizeAnswer(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('ά', 'α')
      .replaceAll('έ', 'ε')
      .replaceAll('ή', 'η')
      .replaceAll('ί', 'ι')
      .replaceAll('ϊ', 'ι')
      .replaceAll('ΐ', 'ι')
      .replaceAll('ό', 'ο')
      .replaceAll('ύ', 'υ')
      .replaceAll('ϋ', 'υ')
      .replaceAll('ΰ', 'υ')
      .replaceAll('ώ', 'ω')
      .replaceAll(RegExp(r'[^a-z0-9α-ω\s]'), '');
}

int _levenshtein(String a, String b) {
  final previous = List<int>.generate(b.length + 1, (index) => index);
  final current = List<int>.filled(b.length + 1, 0);

  for (var i = 0; i < a.length; i++) {
    current[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a[i] == b[j] ? 0 : 1;
      current[j + 1] = min(
        min(current[j] + 1, previous[j + 1] + 1),
        previous[j] + cost,
      );
    }
    for (var j = 0; j < previous.length; j++) {
      previous[j] = current[j];
    }
  }

  return previous[b.length];
}
