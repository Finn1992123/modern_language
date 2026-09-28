import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:modern_language/students_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <({String rpc, Map<String, dynamic> params})>[];
  final responses = <String, List<Map<String, dynamic>>>{};

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      anonKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        final rpc = request.url.pathSegments.last;
        final params = jsonDecode(request.body) as Map<String, dynamic>;
        calls.add((rpc: rpc, params: params));
        final rows = responses[rpc];
        if (rows == null) {
          return http.Response('{"message":"Unexpected RPC: $rpc"}', 400);
        }
        final offset = params['input_offset'] as int? ?? 0;
        final limit = params['input_limit'] as int? ?? rows.length;
        return http.Response(
          jsonEncode(rows.skip(offset).take(limit).toList()),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  setUp(() {
    calls.clear();
    responses.clear();
    responses['get_student_language_summaries'] = [
      {
        'language': 'english',
        'classes': [
          {'class_id': 'group', 'class_name': 'SC2', 'days_hours': 'Monday'},
          {
            'class_id': 'private',
            'class_name': 'Ιδιαίτερο',
            'days_hours': 'Friday',
          },
        ],
        'reading': 70,
        'overall': 66,
      },
    ];
    responses['get_student_exercise_assignments'] = [];
  });

  Future<void> openMenu(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: StudentsMenuPage(
          studentId: 'student',
          studentName: 'Student',
          profilePic: null,
          heroTag: 'student',
          accentColor: Colors.blue,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('one card per language includes both class schedules', (
    tester,
  ) async {
    responses['get_student_language_summaries']!.add({
      'language': 'french',
      'classes': [
        {'class_id': 'french', 'class_name': 'French class'},
      ],
    });
    await openMenu(tester);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('French'), findsOneWidget);
    expect(find.text('SC2 · Monday'), findsOneWidget);
    expect(find.text('Ιδιαίτερο · Friday'), findsOneWidget);
    expect(find.text('70.0%'), findsOneWidget);
    expect(find.text('Οι βαθμοί μου'), findsNWidgets(2));
    expect(
      calls
          .where((call) => call.rpc == 'get_student_exercise_assignments')
          .map((call) => call.params['input_class_id'])
          .toSet(),
      {'group', 'private', 'french'},
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('detailed grades use language scope and combined pagination', (
    tester,
  ) async {
    responses['get_student_language_grade_rows'] = List.generate(
      11,
      (index) => {
        'created_at': '2026-09-28T12:00:00Z',
        'class_name': index.isEven ? 'SC2' : 'Ιδιαίτερο',
        'reading': index.isEven ? 80 : 40,
        'comments': 'Grade $index',
      },
    );
    await openMenu(tester);
    await tester.ensureVisible(find.text('Οι βαθμοί μου'));
    await tester.tap(find.text('Οι βαθμοί μου'));
    await tester.pumpAndSettle();
    expect(find.text('SC2'), findsWidgets);
    expect(find.text('Ιδιαίτερο'), findsWidgets);
    final more = find.byIcon(Icons.keyboard_arrow_down_rounded);
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    final gradeCalls = calls.where(
      (call) => call.rpc == 'get_student_language_grade_rows',
    );
    expect(gradeCalls.map((call) => call.params['input_offset']).toList(), [
      0,
      10,
    ]);
    expect(
      gradeCalls.every(
        (call) =>
            call.params['input_language'] == 'english' &&
            !call.params.containsKey('input_class_id'),
      ),
      isTrue,
    );
    expect(more, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'homework and upcoming dialog include both classes and personal work',
    (tester) async {
      responses['get_student_language_curriculum_rows'] = [
        {
          'created_at': '2026-09-28T12:00:00Z',
          'for_date': '2026-09-29',
          'class_name': 'SC2',
          'in_class': 'Group lesson',
          'homework': 'Group homework',
        },
        {
          'created_at': '2026-09-27T12:00:00Z',
          'for_date': '2026-09-30',
          'class_name': 'Ιδιαίτερο',
          'in_class': 'Private lesson',
          'homework': 'Private homework',
        },
      ];
      responses['get_student_language_upcoming_curriculum_rows'] =
          responses['get_student_language_curriculum_rows']!;
      responses['get_student_language_personal_homework_rows'] = [
        {
          'for_date': '2026-09-29',
          'class_name': 'SC2',
          'homework': 'Personal group work',
        },
        {
          'for_date': '2026-09-30',
          'class_name': 'Ιδιαίτερο',
          'homework': 'Personal private work',
        },
      ];
      await openMenu(tester);
      await tester.ensureVisible(find.text('Τα καθήκοντα μου'));
      await tester.tap(find.text('Τα καθήκοντα μου'));
      await tester.pumpAndSettle();
      expect(find.text('Group lesson'), findsOneWidget);
      expect(find.text('Private lesson'), findsOneWidget);
      expect(find.text('Personal group work'), findsOneWidget);
      expect(find.text('Personal private work'), findsOneWidget);
      await tester.tap(find.text('Τα επόμενα καθήκοντα μου'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Group homework'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Private homework'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Personal private work'),
        ),
        findsOneWidget,
      );
      final homeworkCalls = calls.where(
        (call) =>
            call.rpc.contains('curriculum') ||
            call.rpc.contains('personal_homework'),
      );
      expect(
        homeworkCalls.every(
          (call) => call.params['input_language'] == 'english',
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('class-specific exercises remain reachable for either class', (
    tester,
  ) async {
    await openMenu(tester);
    await tester.ensureVisible(find.text('Ασκήσεις'));
    await tester.tap(find.text('Ασκήσεις'));
    await tester.pumpAndSettle();
    expect(find.text('Επίλεξε τμήμα'), findsOneWidget);
    expect(find.text('SC2'), findsOneWidget);
    expect(find.text('Ιδιαίτερο'), findsOneWidget);
    await tester.tap(find.text('Ιδιαίτερο'));
    await tester.pumpAndSettle();
    expect(calls.last.rpc, 'get_student_exercise_assignments');
    expect(calls.last.params['input_class_id'], 'private');
    expect(tester.takeException(), isNull);
  });
}
