import 'package:flutter_test/flutter_test.dart';
import 'package:modern_language/assignment_session.dart';

void main() {
  test('assignment session keeps resumable progress and completed content', () {
    final session = AssignmentSession(
      assignmentId: 'assignment',
      attemptId: 'attempt',
      studentId: 'student',
      classId: 'class',
      activityType: 'reader',
      settings: {'level': 'lower', 'required_count': 3},
      progressValue: 1,
      targetValue: 3,
      completedSourceKeys: ['passage-1'],
      startedAt: DateTime(2026, 1, 1),
    );

    expect(session.progressValue, 1);
    expect(session.targetValue, 3);
    expect(session.completedSourceKeys, ['passage-1']);
    expect(session.settings['level'], 'lower');
  });
}
