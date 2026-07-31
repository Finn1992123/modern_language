import 'package:supabase_flutter/supabase_flutter.dart';

class AssignmentSession {
  const AssignmentSession({
    required this.assignmentId,
    required this.attemptId,
    required this.studentId,
    required this.classId,
    required this.activityType,
    required this.settings,
    required this.progressValue,
    required this.targetValue,
    this.completedSourceKeys = const [],
    required this.startedAt,
  });

  final String assignmentId;
  final String attemptId;
  final String studentId;
  final String classId;
  final String activityType;
  final Map<String, dynamic> settings;
  final int progressValue;
  final int targetValue;
  final List<String> completedSourceKeys;
  final DateTime startedAt;

  int get remainingSeconds {
    final elapsed = DateTime.now()
        .toUtc()
        .difference(startedAt.toUtc())
        .inSeconds;
    return (targetValue - elapsed).clamp(0, targetValue);
  }

  Future<bool> saveProgress({
    required int progress,
    double? scorePercentage,
    bool finishAttempt = true,
    String? sourceKey,
  }) async {
    final result = await Supabase.instance.client.rpc(
      'finish_exercise_assignment_attempt',
      params: {
        'input_attempt_id': attemptId,
        'input_progress_value': progress,
        'input_score_percentage': scorePercentage,
        'input_finish_attempt': finishAttempt,
        'input_source_key': sourceKey,
      },
    );
    return result == true;
  }
}
