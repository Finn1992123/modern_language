import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';

class AssignmentPreviewWord {
  const AssignmentPreviewWord({
    required this.id,
    required this.word,
    required this.translation,
    this.partOfSpeech,
  });

  final String id;
  final String word;
  final String translation;
  final String? partOfSpeech;
}

class AssignmentWordPreview extends StatefulWidget {
  const AssignmentWordPreview({
    super.key,
    required this.words,
    required this.onCompleted,
  });

  final List<AssignmentPreviewWord> words;
  final VoidCallback onCompleted;

  @override
  State<AssignmentWordPreview> createState() => _AssignmentWordPreviewState();
}

class _AssignmentWordPreviewState extends State<AssignmentWordPreview> {
  late final List<AssignmentPreviewWord> _remainingWords;
  int _index = 0;
  bool _isFlipped = false;
  bool _isCompleting = false;
  int? _swipeStartIndex;
  bool _swipeCompleted = false;

  @override
  void initState() {
    super.initState();
    _remainingWords = List<AssignmentPreviewWord>.from(widget.words);
  }

  void _markLearned() {
    if (_isCompleting) return;
    if (_remainingWords.length == 1) {
      _isCompleting = true;
      widget.onCompleted();
      return;
    }
    setState(() {
      _swipeStartIndex = null;
      _swipeCompleted = false;
      _remainingWords.removeAt(_index);
      if (_index >= _remainingWords.length) _index = 0;
      _isFlipped = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Μελέτησε πρώτα τις λέξεις',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF173A8A),
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 390,
          child: CardSwiper(
            key: ValueKey(_remainingWords.map((word) => word.id).join('|')),
            cardsCount: _remainingWords.length,
            initialIndex: _index,
            numberOfCardsDisplayed: min(_remainingWords.length, 3),
            isLoop: true,
            duration: const Duration(milliseconds: 320),
            threshold: 35,
            maxAngle: 18,
            scale: 0.92,
            backCardOffset: const Offset(0, 20),
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 34),
            onSwipeDirectionChange: (horizontal, vertical) {
              final isSwiping =
                  horizontal != CardSwiperDirection.none ||
                  vertical != CardSwiperDirection.none;
              if (isSwiping && _swipeStartIndex == null) {
                _swipeStartIndex = _index;
                setState(() {
                  _index = (_index + 1) % _remainingWords.length;
                  _isFlipped = false;
                });
              } else if (!isSwiping && _swipeStartIndex != null) {
                final previousIndex = _swipeStartIndex!;
                final shouldRestore = !_swipeCompleted;
                _swipeStartIndex = null;
                _swipeCompleted = false;
                if (shouldRestore) {
                  setState(() {
                    _index = previousIndex;
                    _isFlipped = false;
                  });
                }
              }
            },
            onSwipe: (previousIndex, nextIndex, direction) {
              _swipeCompleted = true;
              if (nextIndex != null) {
                if (_index != nextIndex) {
                  setState(() {
                    _index = nextIndex;
                    _isFlipped = false;
                  });
                }
              }
              return true;
            },
            cardBuilder: (context, index, percentX, percentY) {
              final word = _remainingWords[index];
              return _AssignmentPreviewCard(
                key: ValueKey(word.id),
                word: word,
                isFlipped: index == _index && _isFlipped,
                onFlip: () => setState(() => _isFlipped = !_isFlipped),
                onLearned: _markLearned,
                isLastWord: _remainingWords.length == 1,
                isCompleting: _isCompleting,
                isActive: index == _index,
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${_index + 1}/${_remainingWords.length}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF24734A),
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _AssignmentPreviewCard extends StatelessWidget {
  const _AssignmentPreviewCard({
    super.key,
    required this.word,
    required this.isFlipped,
    required this.onFlip,
    required this.onLearned,
    required this.isLastWord,
    required this.isCompleting,
    required this.isActive,
  });

  final AssignmentPreviewWord word;
  final bool isFlipped;
  final VoidCallback onFlip;
  final VoidCallback onLearned;
  final bool isLastWord;
  final bool isCompleting;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onFlip,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: isFlipped ? pi : 0),
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeInOutCubic,
        builder: (context, angle, _) {
          final showBack = angle >= pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(angle),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: showBack
                      ? const [Color(0xFFFFFAE9), Color(0xFFFFEFC2)]
                      : const [Color(0xFFFDFEFF), Color(0xFFEAF5FF)],
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white, width: 1.6),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x246051B4),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.rotationY(showBack ? pi : 0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      showBack ? Icons.translate_rounded : Icons.style_rounded,
                      color: showBack
                          ? const Color(0xFFE6A000)
                          : const Color(0xFF5D4BE2),
                      size: 44,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      showBack ? word.translation : word.word,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF173A8A),
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        height: 1.08,
                      ),
                    ),
                    if (word.partOfSpeech?.isNotEmpty == true) ...[
                      const SizedBox(height: 10),
                      Text(
                        word.partOfSpeech!,
                        style: const TextStyle(
                          color: Color(0xFF6B6B78),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Text(
                      showBack ? 'Πάτησε για τη λέξη' : 'Πάτησε για μετάφραση',
                      style: const TextStyle(
                        color: Color(0xFF77718F),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (isActive)
                      FilledButton.icon(
                        onPressed: isCompleting ? null : onLearned,
                        icon: const Icon(Icons.task_alt_rounded),
                        label: Text(
                          isLastWord
                              ? 'Την έμαθα — Έναρξη άσκησης'
                              : 'Την έμαθα',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFDDF5E5),
                          foregroundColor: const Color(0xFF24734A),
                          disabledBackgroundColor: const Color(0xFFDDF5E5),
                          disabledForegroundColor: const Color(0xFF24734A),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: Color(0xFFB9E5C8)),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 48),
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
