import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'assignment_session.dart';
import 'hangman.dart';
import 'identify_the_tense.dart';
import 'reader.dart';
import 'studyyourgram.dart';
import 'studyyourvoc.dart';

class MyExercisesPage extends StatefulWidget {
  const MyExercisesPage({
    super.key,
    required this.studentId,
    required this.classId,
    required this.languageLabel,
  });

  final String studentId;
  final String classId;
  final String languageLabel;

  @override
  State<MyExercisesPage> createState() => _MyExercisesPageState();
}

class _MyExercisesPageState extends State<MyExercisesPage> {
  static const _red = Color(0xFF7D1010);
  late Future<List<_StudentAssignment>> _future = _load();
  String? _startingAssignmentId;

  Future<List<_StudentAssignment>> _load() async {
    final rows = await Supabase.instance.client.rpc(
      'get_student_exercise_assignments',
      params: {
        'input_student_id': widget.studentId,
        'input_class_id': widget.classId,
      },
    );
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map(
          (row) => _StudentAssignment.fromRow(Map<String, dynamic>.from(row)),
        )
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _start(_StudentAssignment assignment) async {
    if (!assignment.canStart) return;
    setState(() => _startingAssignmentId = assignment.id);
    try {
      final rows = await Supabase.instance.client.rpc(
        'start_exercise_assignment_attempt',
        params: {
          'input_assignment_id': assignment.id,
          'input_student_id': widget.studentId,
          'input_class_id': widget.classId,
        },
      );
      if (rows is! List || rows.isEmpty || rows.first is! Map) {
        throw StateError('Δεν δημιουργήθηκε προσπάθεια.');
      }
      final row = Map<String, dynamic>.from(rows.first as Map);
      final session = AssignmentSession(
        assignmentId: assignment.id,
        attemptId: row['attempt_id']?.toString() ?? '',
        studentId: widget.studentId,
        classId: widget.classId,
        activityType: assignment.activityType,
        settings: assignment.settings,
        progressValue: (row['progress_value'] as num?)?.toInt() ?? 0,
        targetValue: (row['target_value'] as num?)?.toInt() ?? 1,
        completedSourceKeys:
            (row['completed_source_keys'] as List?)
                ?.map((value) => value.toString())
                .toList() ??
            const [],
        startedAt:
            DateTime.tryParse(row['started_at']?.toString() ?? '') ??
            DateTime.now().toUtc(),
      );
      if (!mounted) return;

      final page = switch (assignment.activityType) {
        'reader' => ReaderPage(
          studentId: widget.studentId,
          classId: widget.classId,
          assignmentSession: session,
        ),
        'vocabulary' => StudyYourVocPage(
          studentId: widget.studentId,
          classId: widget.classId,
          languageLabel: widget.languageLabel,
          assignmentSession: session,
        ),
        'hangman' => HangmanHomePage(
          studentId: widget.studentId,
          classId: widget.classId,
          languageLabel: widget.languageLabel,
          assignmentSession: session,
        ),
        'identify_tense' => IdentifyTheTenseHomePage(
          studentId: widget.studentId,
          classId: widget.classId,
          assignmentSession: session,
        ),
        'study_grammar' => StudyYourGramPage(
          studentId: widget.studentId,
          classId: widget.classId,
          assignmentSession: session,
        ),
        _ => null,
      };
      if (page == null) {
        throw StateError('Η δραστηριότητα δεν υποστηρίζεται ακόμη.');
      }
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => page));
      if (mounted) _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Δεν ξεκίνησε η άσκηση: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _startingAssignmentId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F8),
      appBar: AppBar(
        title: const Text(
          'Ασκήσεις',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.white,
        foregroundColor: _red,
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<_StudentAssignment>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _MessageView(
              icon: Icons.error_outline_rounded,
              message: 'Δεν φορτώθηκαν οι ασκήσεις.',
              onRetry: _refresh,
            );
          }
          final assignments = snapshot.data ?? const [];
          if (assignments.isEmpty) {
            return const _MessageView(
              icon: Icons.edit_note_rounded,
              message: 'Δεν σου έχει ανατεθεί κάποια άσκηση ακόμη.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              _refresh();
              await _future;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(18),
              itemCount: assignments.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final assignment = assignments[index];
                return _AssignmentCard(
                  assignment: assignment,
                  loading: _startingAssignmentId == assignment.id,
                  onStart: () => _start(assignment),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({
    required this.assignment,
    required this.loading,
    required this.onStart,
  });

  final _StudentAssignment assignment;
  final bool loading;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final color = assignment.completed
        ? const Color(0xFF178A45)
        : assignment.expired
        ? Colors.grey
        : assignment.activityColor;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                foregroundColor: color,
                child: Icon(assignment.activityIcon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assignment.title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      assignment.activityLabel,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (assignment.completed)
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF178A45),
                  size: 30,
                ),
            ],
          ),
          if (assignment.instructions?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(assignment.instructions!),
          ],
          const SizedBox(height: 12),
          Text(
            assignment.goalLabel,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            assignment.metaLabel,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          if (assignment.attemptCount > 0) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: assignment.progressRatio,
              minHeight: 8,
              borderRadius: BorderRadius.circular(10),
              color: color,
              backgroundColor: color.withValues(alpha: 0.12),
            ),
            const SizedBox(height: 5),
            Text(
              assignment.progressLabel,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
          if (assignment.completed && assignment.displayScore != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF178A45).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.grade_rounded, color: Color(0xFF178A45)),
                  const SizedBox(width: 8),
                  Text(
                    'Βαθμός: ${_formatScore(assignment.displayScore!)}%',
                    style: const TextStyle(
                      color: Color(0xFF178A45),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: assignment.canStart && !loading ? onStart : null,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(assignment.completed ? Icons.check : Icons.play_arrow),
            label: Text(assignment.buttonLabel),
            style: FilledButton.styleFrom(backgroundColor: color),
          ),
        ],
      ),
    );
  }
}

class _StudentAssignment {
  const _StudentAssignment({
    required this.id,
    required this.activityType,
    required this.title,
    required this.instructions,
    required this.availableFrom,
    required this.dueAt,
    required this.maxAttempts,
    required this.settings,
    required this.attemptCount,
    required this.completed,
    required this.progressValue,
    required this.targetValue,
    required this.bestScore,
  });

  factory _StudentAssignment.fromRow(Map<String, dynamic> row) {
    final settingsValue = row['settings'];
    return _StudentAssignment(
      id: row['assignment_id']?.toString() ?? '',
      activityType: row['activity_type']?.toString() ?? '',
      title: row['title']?.toString() ?? 'Άσκηση',
      instructions: row['instructions']?.toString(),
      availableFrom: DateTime.tryParse(row['available_from']?.toString() ?? ''),
      dueAt: DateTime.tryParse(row['due_at']?.toString() ?? ''),
      maxAttempts: (row['max_attempts'] as num?)?.toInt(),
      settings: settingsValue is Map
          ? Map<String, dynamic>.from(settingsValue)
          : const {},
      attemptCount: (row['attempt_count'] as num?)?.toInt() ?? 0,
      completed: row['completed'] == true,
      progressValue: (row['progress_value'] as num?)?.toInt() ?? 0,
      targetValue: (row['target_value'] as num?)?.toInt() ?? 1,
      bestScore: (row['best_score'] as num?)?.toDouble(),
    );
  }

  final String id;
  final String activityType;
  final String title;
  final String? instructions;
  final DateTime? availableFrom;
  final DateTime? dueAt;
  final int? maxAttempts;
  final Map<String, dynamic> settings;
  final int attemptCount;
  final bool completed;
  final int progressValue;
  final int targetValue;
  final double? bestScore;

  bool get expired => dueAt != null && dueAt!.isBefore(DateTime.now());
  bool get upcoming =>
      availableFrom != null && availableFrom!.isAfter(DateTime.now());
  bool get attemptsExhausted =>
      maxAttempts != null && attemptCount >= maxAttempts!;
  bool get canStart =>
      !completed && !expired && !upcoming && !attemptsExhausted;

  double? get displayScore {
    if (bestScore != null) return bestScore!.clamp(0, 100);
    if (completed && (activityType == 'reader' || activityType == 'hangman')) {
      return 100;
    }
    return null;
  }

  String get activityLabel => switch (activityType) {
    'reader' => 'Reader',
    'vocabulary' => 'Study your voc',
    'hangman' => 'Hangman',
    'identify_tense' => 'Identify the tense',
    'study_grammar' => 'Study your gram',
    _ => 'Άσκηση',
  };

  IconData get activityIcon => switch (activityType) {
    'reader' => Icons.auto_stories_rounded,
    'vocabulary' => Icons.style_rounded,
    'hangman' => Icons.extension_rounded,
    'identify_tense' => Icons.schedule_rounded,
    'study_grammar' => Icons.menu_book_rounded,
    _ => Icons.edit_note_rounded,
  };

  Color get activityColor => switch (activityType) {
    'reader' => const Color(0xFF18A8EF),
    'vocabulary' => const Color(0xFF4D4AAD),
    'hangman' => const Color(0xFFE32636),
    'identify_tense' => const Color(0xFF18A8EF),
    'study_grammar' => const Color(0xFF4D4AAD),
    _ => const Color(0xFF7D1010),
  };

  String get goalLabel {
    final personalWords =
        settings['personal_words'] == true ||
        settings['unit'] == '__personal__';
    if (activityType == 'reader') {
      return 'Στόχος: ${settings['required_count']} κείμενα';
    }
    if (activityType == 'vocabulary') {
      return personalWords
          ? 'Προσωπικές λέξεις · Επιτυχία ≥ ${settings['pass_percentage']}%'
          : '${_modeLabel(settings['mode']?.toString())} · Επιτυχία ≥ ${settings['pass_percentage']}%';
    }
    if (activityType == 'hangman') {
      return personalWords
          ? 'Βρες $targetValue προσωπικές λέξεις'
          : 'Βρες ${settings['required_count']} λέξεις · ${settings['unit']}';
    }
    if (activityType == 'identify_tense' || activityType == 'study_grammar') {
      final type = settings['limit_type']?.toString();
      final value = (settings['limit_value'] as num?)?.toInt() ?? 0;
      return type == 'time'
          ? 'Χρόνος: ${(value / 60).ceil()} λεπτά · Επιτυχία ≥ ${settings['pass_percentage'] ?? 71}%'
          : 'Στόχος: $value ερωτήσεις · Επιτυχία ≥ ${settings['pass_percentage'] ?? 71}%';
    }
    return 'Άσκηση';
  }

  String get metaLabel {
    final due = dueAt;
    final dueLabel = due == null
        ? 'Χωρίς λήξη'
        : 'Λήξη: ${due.day}/${due.month}/${due.year}';
    final attemptsLabel = maxAttempts == null
        ? 'Απεριόριστες προσπάθειες'
        : '$attemptCount/$maxAttempts προσπάθειες';
    return '$dueLabel · $attemptsLabel';
  }

  double get progressRatio {
    if (activityType == 'vocabulary') {
      return ((bestScore ?? 0) / 100).clamp(0, 1);
    }
    return (progressValue / targetValue).clamp(0, 1);
  }

  String get progressLabel => activityType == 'vocabulary'
      ? 'Καλύτερη βαθμολογία: ${(bestScore ?? 0).round()}%'
      : '$progressValue/$targetValue';

  String get buttonLabel {
    if (completed) return 'Ολοκληρώθηκε';
    if (expired) return 'Έληξε';
    if (upcoming) return 'Δεν άνοιξε ακόμη';
    if (attemptsExhausted) return 'Τέλος προσπαθειών';
    return attemptCount == 0 ? 'Έναρξη' : 'Συνέχεια / νέα προσπάθεια';
  }
}

String _formatScore(double score) => score == score.roundToDouble()
    ? score.toStringAsFixed(0)
    : score.toStringAsFixed(1);

String _modeLabel(String? mode) => switch (mode) {
  'speaking' => 'Προφορά λέξεων',
  'multiple_choice' => 'Πολλαπλής επιλογής',
  'write_foreign' => 'Ελληνικά → ξένη γλώσσα',
  'write_greek' => 'Ξένη γλώσσα → ελληνικά',
  _ => 'Λεξιλόγιο',
};

class _MessageView extends StatelessWidget {
  const _MessageView({required this.icon, required this.message, this.onRetry});

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 70, color: const Color(0xFF7D1010)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Δοκιμή ξανά'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
