import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:supabase_flutter/supabase_flutter.dart';

enum _VocMode { study, speaking, multipleChoice, writeGreek, writeForeign }

class StudyYourVocPage extends StatefulWidget {
  const StudyYourVocPage({
    super.key,
    required this.studentId,
    required this.classId,
    required this.languageLabel,
  });

  final String studentId;
  final String classId;
  final String languageLabel;

  @override
  State<StudyYourVocPage> createState() => _StudyYourVocPageState();
}

class _StudyYourVocPageState extends State<StudyYourVocPage> {
  late final Future<List<_VocWord>> _wordsFuture = _loadWords();
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
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
  String _spokenText = '';
  bool _importantOnly = false;
  final List<_VocAttempt> _attempts = [];

  @override
  void dispose() {
    _answerController.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<List<_VocWord>> _loadWords() async {
    final rows = await Supabase.instance.client.rpc(
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
      _wordIndex = 0;
      _attempts.clear();
      _resetQuestionState();
    });
  }

  void _selectMode(_VocMode? mode) {
    setState(() {
      _mode = mode;
      _wordIndex = 0;
      _attempts.clear();
      _resetQuestionState();
    });
  }

  void _resetQuestionState() {
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
    final language = word.language.isEmpty
        ? widget.languageLabel
        : word.language;
    await _tts.setLanguage(_ttsLanguage(language));
    await _tts.setSpeechRate(0.42);
    await _tts.setPitch(1);
    await _tts.speak(word.word);
  }

  Future<void> _toggleListening(_VocWord word) async {
    if (_isListening) {
      await _speech.stop();
      if (!mounted) {
        return;
      }
      setState(() => _isListening = false);
      return;
    }

    final ready = _speechReady || await _speech.initialize();
    if (!mounted) {
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
      _lastAnswerCorrect = null;
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
        if (!mounted) {
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
    final pool = words
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
    final correctAnswers = toGreek
        ? word.acceptedAnswers
        : <String>[word.word];
    final correctAnswer = toGreek ? word.translationGr : word.word;
    final prompt = toGreek ? word.word : word.translationGr;
    final mode = toGreek ? _VocMode.writeGreek : _VocMode.writeForeign;

    setState(() {
      _lastAnswerCorrect = correctAnswers.any((correct) {
        if (toGreek) {
          return _answersMatch(answer, correct);
        }

        return _exactAnswerMatch(answer, correct);
      });
      _recordAttempt(
        mode: mode,
        word: word,
        prompt: prompt,
        userAnswer: answer,
        correctAnswer: correctAnswer,
        correct: _lastAnswerCorrect ?? false,
      );
    });
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

  void _nextOrFinish(List<_VocWord> words) {
    if (_mode == _VocMode.multipleChoice ||
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
    final attempts = _attempts.where((attempt) => attempt.mode == mode).toList();
    final total = attempts.length;
    final correct = attempts.where((attempt) => attempt.correct).length;
    final wrong = attempts.where((attempt) => !attempt.correct).toList();
    final percent = total == 0 ? 0 : ((correct / total) * 100).round();

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
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _selectMode(null);
                },
                child: const Text('Μενού'),
              ),
            ],
          ),
        );
      },
    );
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

            _selectedUnit ??= units.first.value;
            final words = allWords
                .where(
                  (word) =>
                      word.unitKey == _selectedUnit &&
                      (!_importantOnly || word.isImportant),
                )
                .toList();

            if (words.isEmpty) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  _Header(onBack: () => Navigator.of(context).pop()),
                  const SizedBox(height: 16),
                  _UnitPicker(
                    units: units,
                    selectedUnit: _selectedUnit,
                    onChanged: _selectUnit,
                  ),
                  const SizedBox(height: 14),
                  _ImportantWordsToggle(
                    value: _importantOnly,
                    onChanged: (value) {
                      setState(() {
                        _importantOnly = value ?? false;
                        _wordIndex = 0;
                        _attempts.clear();
                        _resetQuestionState();
                      });
                    },
                  ),
                  const SizedBox(height: 18),
                  _ModeMenu(onSelected: _selectMode),
                  const SizedBox(height: 18),
                  const _EmptyUnitMessage(),
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
                _Header(onBack: () => Navigator.of(context).pop()),
                const SizedBox(height: 16),
                _UnitPicker(
                  units: units,
                  selectedUnit: _selectedUnit,
                  onChanged: _selectUnit,
                ),
                const SizedBox(height: 14),
                if (_mode == null) ...[
                  _ImportantWordsToggle(
                    value: _importantOnly,
                    onChanged: (value) {
                      setState(() {
                        _importantOnly = value ?? false;
                        _wordIndex = 0;
                        _attempts.clear();
                        _resetQuestionState();
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  const SizedBox(height: 18),
                  Image.asset(
                    'lib/img/openBook.png',
                    height: 190,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 18),
                  _ModeMenu(onSelected: _selectMode),
                ] else ...[
                  _ModeHeader(
                    mode: _mode!,
                    onBack: () => _selectMode(null),
                  ),
                  const SizedBox(height: 14),
                  _ModeBody(
                    mode: _mode!,
                    word: current,
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
                    onFlip: () => setState(() => _isFlipped = !_isFlipped),
                    onSwipe: (direction) => _moveWord(direction, words),
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
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

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
        const Expanded(
          child: Text(
            'Study your voc',
            style: TextStyle(
              color: Color(0xFF4D4AAD),
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
        ),
      ],
    );
  }
}

class _UnitPicker extends StatelessWidget {
  const _UnitPicker({
    required this.units,
    required this.selectedUnit,
    required this.onChanged,
  });

  final List<_VocUnit> units;
  final String? selectedUnit;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: selectedUnit,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Ενότητα',
        filled: true,
        fillColor: const Color(0xFFEAF7FF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
      items: [
        for (final unit in units)
          DropdownMenuItem(value: unit.value, child: Text(unit.label)),
      ],
      onChanged: onChanged,
    );
  }
}

class _ImportantWordsToggle extends StatelessWidget {
  const _ImportantWordsToggle({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEAF7FF),
      borderRadius: BorderRadius.circular(16),
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        activeColor: const Color(0xFF4D4AAD),
        checkColor: Colors.white,
        title: const Text(
          'Σημαντικές λέξεις',
          style: TextStyle(
            color: Color(0xFF173A8A),
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
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
      (_VocMode.study, 'Μελέτη', Icons.style_rounded, Color(0xFF4D4AAD)),
      (
        _VocMode.speaking,
        'Προφορικά',
        Icons.record_voice_over_rounded,
        Color(0xFF2D7D10),
      ),
      (_VocMode.multipleChoice, 'Quiz', Icons.quiz_rounded, Color(0xFFDB9538)),
      (
        _VocMode.writeForeign,
        'Ελληνικά - Ξένη Γλώσσα',
        Icons.translate_rounded,
        Color(0xFF385DC9),
      ),
      (
        _VocMode.writeGreek,
        'Ξένη Γλώσσα - Ελληνικά',
        Icons.edit_rounded,
        Color(0xFF7D1010),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final mode in modes) ...[
          _ModeMenuCard(
            label: mode.$2,
            icon: mode.$3,
            color: mode.$4,
            onTap: () => onSelected(mode.$1),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ModeMenuCard extends StatelessWidget {
  const _ModeMenuCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: color, size: 34),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color, size: 30),
            ],
          ),
        ),
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
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
          color: const Color(0xFF4D4AAD),
        ),
        Expanded(
          child: Text(
            _modeLabel(mode),
            style: const TextStyle(
              color: Color(0xFF4D4AAD),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeBody extends StatelessWidget {
  const _ModeBody({
    required this.mode,
    required this.word,
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
    required this.onFlip,
    required this.onSwipe,
    required this.onListen,
    required this.onChoiceSelected,
    required this.onCheckGreek,
    required this.onCheckForeign,
    required this.onNext,
  });

  final _VocMode mode;
  final _VocWord word;
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
  final VoidCallback onFlip;
  final ValueChanged<int> onSwipe;
  final VoidCallback onListen;
  final ValueChanged<String> onChoiceSelected;
  final VoidCallback onCheckGreek;
  final VoidCallback onCheckForeign;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case _VocMode.study:
        return _StudyCard(
          word: word,
          canGoBack: currentIndex > 0,
          canGoForward: currentIndex < wordCount - 1,
          isFlipped: isFlipped,
          onSpeak: onSpeak,
          onFlip: onFlip,
          onSwipe: onSwipe,
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
          onSpeak: null,
          onCheck: onCheckForeign,
          onNext: onNext,
        );
    }
  }
}

class _StudyCard extends StatelessWidget {
  const _StudyCard({
    required this.word,
    required this.canGoBack,
    required this.canGoForward,
    required this.isFlipped,
    required this.onSpeak,
    required this.onFlip,
    required this.onSwipe,
  });

  final _VocWord word;
  final bool canGoBack;
  final bool canGoForward;
  final bool isFlipped;
  final VoidCallback onSpeak;
  final VoidCallback onFlip;
  final ValueChanged<int> onSwipe;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 42,
          child: canGoBack
              ? IconButton(
                  onPressed: () => onSwipe(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: const Color(0xFF4D4AAD),
                  iconSize: 38,
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: GestureDetector(
            onTap: onFlip,
            onPanEnd: (details) {
              final velocity = details.velocity.pixelsPerSecond;
              final direction = velocity.dx.abs() > velocity.dy.abs()
                  ? (velocity.dx < 0 ? 1 : -1)
                  : (velocity.dy < 0 ? 1 : -1);
              if (direction < 0 && !canGoBack) {
                return;
              }
              if (direction > 0 && !canGoForward) {
                return;
              }
              onSwipe(direction);
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (child, animation) {
                return ScaleTransition(scale: animation, child: child);
              },
              child: Container(
                key: ValueKey('${word.id}-$isFlipped'),
                height: 330,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isFlipped
                      ? const Color(0xFFFFF5D8)
                      : const Color(0xFFEAF7FF),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0x334D4AAD)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!isFlipped)
                      IconButton.filled(
                        onPressed: onSpeak,
                        icon: const Icon(Icons.volume_up_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF4D4AAD),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      isFlipped ? word.translationGr : word.word,
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
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 42,
          child: canGoForward
              ? IconButton(
                  onPressed: () => onSwipe(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                  color: const Color(0xFF4D4AAD),
                  iconSize: 38,
                )
              : const SizedBox.shrink(),
        ),
      ],
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
              icon: Icon(
                isListening ? Icons.stop_rounded : Icons.mic_rounded,
              ),
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
        _AnswerResult(correct: lastAnswerCorrect, correctAnswer: word.word),
        if (lastAnswerCorrect != null)
          FilledButton(onPressed: onNext, child: const Text('Επόμενη')),
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
            correct: selectedChoice == null ? null : choice == word.translationGr,
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
    required this.onSpeak,
    required this.onCheck,
    required this.onNext,
  });

  final String prompt;
  final String helper;
  final TextEditingController controller;
  final bool? lastAnswerCorrect;
  final String correctAnswer;
  final VoidCallback? onSpeak;
  final VoidCallback onCheck;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
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
          onSubmitted: (_) => onCheck(),
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
          onPressed: lastAnswerCorrect == false ? null : onCheck,
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
  const _PracticePanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7FF),
        borderRadius: BorderRadius.circular(24),
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
            )
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
                color: index < correctText.length &&
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
      return 'Ξένη Γλώσσα - Ελληνικά';
    case _VocMode.writeForeign:
      return 'Ελληνικά - Ξένη Γλώσσα';
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
