import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_language/assignment_word_preview.dart';

void main() {
  testWidgets('reviews every word before completing', (tester) async {
    var completed = false;
    const words = [
      AssignmentPreviewWord(id: '1', word: 'apple', translation: 'μήλο'),
      AssignmentPreviewWord(id: '2', word: 'book', translation: 'βιβλίο'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AssignmentWordPreview(
              words: words,
              onCompleted: () => completed = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('apple'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);

    await tester.tap(find.text('apple'));
    await tester.pumpAndSettle();
    expect(find.text('μήλο'), findsOneWidget);

    await tester.tap(find.text('Την έμαθα'));
    await tester.pump();
    expect(find.text('book'), findsOneWidget);
    expect(find.text('1/1'), findsOneWidget);
    expect(completed, isFalse);

    await tester.tap(find.text('Την έμαθα — Έναρξη άσκησης'));
    await tester.pump();
    expect(completed, isTrue);
  });

  testWidgets('supports swiping between preview cards', (tester) async {
    const words = [
      AssignmentPreviewWord(id: '1', word: 'apple', translation: 'μήλο'),
      AssignmentPreviewWord(id: '2', word: 'book', translation: 'βιβλίο'),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AssignmentWordPreview(
              words: words,
              onCompleted: _ignoreCompletion,
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.text('apple'), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(find.text('2/2'), findsOneWidget);
  });

  testWidgets('restores the active card when a swipe is cancelled', (
    tester,
  ) async {
    const words = [
      AssignmentPreviewWord(id: '1', word: 'apple', translation: 'μήλο'),
      AssignmentPreviewWord(id: '2', word: 'book', translation: 'βιβλίο'),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AssignmentWordPreview(
              words: words,
              onCompleted: _ignoreCompletion,
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.text('apple'), const Offset(-15, 0));
    await tester.pumpAndSettle();

    expect(find.text('1/2'), findsOneWidget);
  });
}

void _ignoreCompletion() {}
