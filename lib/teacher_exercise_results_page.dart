import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeacherExerciseResultsPage extends StatefulWidget {
  const TeacherExerciseResultsPage({super.key});

  @override
  State<TeacherExerciseResultsPage> createState() =>
      _TeacherExerciseResultsPageState();
}

class _TeacherExerciseResultsPageState
    extends State<TeacherExerciseResultsPage> {
  static const _blue = Color(0xFF173A8A);

  late Future<List<_TeacherClass>> _classesFuture = _loadClasses();
  Future<List<_AssignmentOverview>>? _assignmentsFuture;
  _TeacherClass? _selectedClass;

  Future<List<_TeacherClass>> _loadClasses() async {
    final rows = await Supabase.instance.client.rpc('get_teacher_classes');
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => _TeacherClass.fromRow(Map<String, dynamic>.from(row)))
        .where((teacherClass) => teacherClass.id.isNotEmpty)
        .toList();
  }

  Future<List<_AssignmentOverview>> _loadAssignments(String classId) async {
    final rows = await Supabase.instance.client.rpc(
      'get_teacher_exercise_assignments_overview',
      params: {'input_class_id': classId},
    );
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map(
          (row) => _AssignmentOverview.fromRow(Map<String, dynamic>.from(row)),
        )
        .where((assignment) => assignment.id.isNotEmpty)
        .toList();
  }

  void _selectClass(_TeacherClass? teacherClass) {
    if (teacherClass == null) return;
    setState(() {
      _selectedClass = teacherClass;
      _assignmentsFuture = _loadAssignments(teacherClass.id);
    });
  }

  void _refreshAssignments() {
    final teacherClass = _selectedClass;
    if (teacherClass == null) return;
    setState(() {
      _assignmentsFuture = _loadAssignments(teacherClass.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FF),
      appBar: AppBar(
        title: const Text(
          'Έλεγχος ασκήσεων',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.white,
        foregroundColor: _blue,
        actions: [
          if (_selectedClass != null)
            IconButton(
              onPressed: _refreshAssignments,
              tooltip: 'Ανανέωση',
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: FutureBuilder<List<_TeacherClass>>(
        future: _classesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _MessageView(
              icon: Icons.error_outline_rounded,
              text: 'Δεν φορτώθηκαν τα τμήματα.',
              onRetry: () => setState(() {
                _classesFuture = _loadClasses();
              }),
            );
          }
          final classes = snapshot.data ?? const [];
          if (classes.isEmpty) {
            return const _MessageView(
              icon: Icons.school_outlined,
              text: 'Δεν υπάρχουν διαθέσιμα τμήματα.',
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                child: DropdownButtonFormField<_TeacherClass>(
                  initialValue: _selectedClass,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Επίλεξε τμήμα',
                    prefixIcon: const Icon(Icons.groups_rounded),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  items: [
                    for (final teacherClass in classes)
                      DropdownMenuItem(
                        value: teacherClass,
                        child: Text(
                          teacherClass.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _selectClass,
                ),
              ),
              Expanded(child: _buildAssignments()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAssignments() {
    final assignmentsFuture = _assignmentsFuture;
    if (assignmentsFuture == null) {
      return const _MessageView(
        icon: Icons.touch_app_rounded,
        text: 'Επίλεξε ένα τμήμα για να δεις τις ασκήσεις του.',
      );
    }
    return FutureBuilder<List<_AssignmentOverview>>(
      future: assignmentsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _MessageView(
            icon: Icons.error_outline_rounded,
            text: 'Δεν φορτώθηκαν οι αναθέσεις.',
            onRetry: _refreshAssignments,
          );
        }
        final assignments = snapshot.data ?? const [];
        if (assignments.isEmpty) {
          return const _MessageView(
            icon: Icons.assignment_outlined,
            text: 'Δεν έχουν ανατεθεί ασκήσεις σε αυτό το τμήμα.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            _refreshAssignments();
            await _assignmentsFuture;
          },
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
            itemCount: assignments.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final assignment = assignments[index];
              return _AssignmentOverviewCard(
                assignment: assignment,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _AssignmentStudentResultsPage(
                        assignment: assignment,
                        teacherClass: _selectedClass!,
                      ),
                    ),
                  );
                  if (mounted) _refreshAssignments();
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _AssignmentOverviewCard extends StatelessWidget {
  const _AssignmentOverviewCard({
    required this.assignment,
    required this.onTap,
  });

  final _AssignmentOverview assignment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF178A45);
    final ratio = assignment.studentCount == 0
        ? 0.0
        : assignment.completedCount / assignment.studentCount;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: assignment.color.withValues(alpha: 0.12),
                    foregroundColor: assignment.color,
                    child: Icon(assignment.icon),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          assignment.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          assignment.activityLabel,
                          style: TextStyle(
                            color: assignment.color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: ratio,
                minHeight: 9,
                borderRadius: BorderRadius.circular(12),
                color: green,
                backgroundColor: const Color(0xFFE5E8F2),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${assignment.completedCount}/${assignment.studentCount} ολοκλήρωσαν',
                    style: const TextStyle(
                      color: green,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${assignment.startedCount} ξεκίνησαν',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                assignment.dateLabel,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssignmentStudentResultsPage extends StatefulWidget {
  const _AssignmentStudentResultsPage({
    required this.assignment,
    required this.teacherClass,
  });

  final _AssignmentOverview assignment;
  final _TeacherClass teacherClass;

  @override
  State<_AssignmentStudentResultsPage> createState() =>
      _AssignmentStudentResultsPageState();
}

class _AssignmentStudentResultsPageState
    extends State<_AssignmentStudentResultsPage> {
  late Future<List<_StudentResult>> _future = _load();

  Future<List<_StudentResult>> _load() async {
    final rows = await Supabase.instance.client.rpc(
      'get_teacher_exercise_assignment_results',
      params: {
        'input_assignment_id': widget.assignment.id,
        'input_class_id': widget.teacherClass.id,
      },
    );
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => _StudentResult.fromRow(Map<String, dynamic>.from(row)))
        .where((result) => result.id.isNotEmpty)
        .toList();
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FF),
      appBar: AppBar(
        title: Text(
          widget.assignment.title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF173A8A),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<_StudentResult>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _MessageView(
              icon: Icons.error_outline_rounded,
              text: 'Δεν φορτώθηκαν τα αποτελέσματα.',
              onRetry: _refresh,
            );
          }
          final results = snapshot.data ?? const [];
          if (results.isEmpty) {
            return const _MessageView(
              icon: Icons.people_outline_rounded,
              text: 'Δεν υπάρχουν μαθητές σε αυτό το τμήμα.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              _refresh();
              await _future;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(18),
              itemCount: results.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, index) => _StudentResultCard(
                result: results[index],
                activityType: widget.assignment.activityType,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StudentResultCard extends StatelessWidget {
  const _StudentResultCard({required this.result, required this.activityType});

  final _StudentResult result;
  final String activityType;

  @override
  Widget build(BuildContext context) {
    final status = result.statusInfo;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: status.color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: status.color.withValues(alpha: 0.12),
            foregroundColor: status.color,
            child: Text(
              result.initial,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: status.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.label,
                    style: TextStyle(
                      color: status.color,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (result.status != 'not_started') ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 5,
                    children: [
                      Text(
                        'Προσπάθειες: ${result.attemptCount}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (result.bestScore != null)
                        Text(
                          'Βαθμός: ${_formatScore(result.bestScore!)}%',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      Text(
                        'Πρόοδος: ${result.progressValue}/${result.targetValue}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  if (result.completedAt != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      'Ολοκλήρωση: ${_formatDateTime(result.completedAt!)}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          Icon(status.icon, color: status.color, size: 28),
        ],
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 60, color: const Color(0xFF627DE4)),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Δοκιμή ξανά'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TeacherClass {
  const _TeacherClass({
    required this.id,
    required this.name,
    required this.language,
    required this.daysHours,
  });

  factory _TeacherClass.fromRow(Map<String, dynamic> row) => _TeacherClass(
    id: row['id']?.toString() ?? '',
    name: row['name']?.toString().trim() ?? '',
    language: row['language']?.toString().trim() ?? '',
    daysHours: row['days_hours']?.toString().trim() ?? '',
  );

  final String id;
  final String name;
  final String language;
  final String daysHours;

  String get title =>
      [name, language, daysHours].where((part) => part.isNotEmpty).join(' · ');
}

class _AssignmentOverview {
  const _AssignmentOverview({
    required this.id,
    required this.title,
    required this.activityType,
    required this.createdAt,
    required this.dueAt,
    required this.status,
    required this.studentCount,
    required this.startedCount,
    required this.completedCount,
  });

  factory _AssignmentOverview.fromRow(Map<String, dynamic> row) =>
      _AssignmentOverview(
        id: row['assignment_id']?.toString() ?? '',
        title: row['assignment_title']?.toString().trim() ?? 'Άσκηση',
        activityType: row['activity_type']?.toString() ?? '',
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
        dueAt: DateTime.tryParse(row['due_at']?.toString() ?? ''),
        status: row['assignment_status']?.toString() ?? '',
        studentCount: _readInt(row['student_count']),
        startedCount: _readInt(row['started_count']),
        completedCount: _readInt(row['completed_count']),
      );

  final String id;
  final String title;
  final String activityType;
  final DateTime? createdAt;
  final DateTime? dueAt;
  final String status;
  final int studentCount;
  final int startedCount;
  final int completedCount;

  String get activityLabel => switch (activityType) {
    'reader' => 'Reader',
    'vocabulary' => 'Study your voc',
    'hangman' => 'Hangman',
    'identify_tense' => 'Identify the tense',
    'study_grammar' => 'Study your gram',
    _ => 'Άσκηση',
  };

  IconData get icon => switch (activityType) {
    'reader' => Icons.auto_stories_rounded,
    'vocabulary' => Icons.style_rounded,
    'hangman' => Icons.extension_rounded,
    'identify_tense' => Icons.schedule_rounded,
    'study_grammar' => Icons.menu_book_rounded,
    _ => Icons.assignment_rounded,
  };

  Color get color => switch (activityType) {
    'reader' => const Color(0xFF18A8EF),
    'vocabulary' => const Color(0xFF4D4AAD),
    'hangman' => const Color(0xFFE32636),
    'identify_tense' => const Color(0xFF18A8EF),
    'study_grammar' => const Color(0xFF4D4AAD),
    _ => const Color(0xFF627DE4),
  };

  String get dateLabel {
    final created = createdAt;
    final due = dueAt;
    final createdLabel = created == null
        ? ''
        : 'Ανάθεση: ${created.day}/${created.month}/${created.year}';
    final dueLabel = due == null
        ? 'Χωρίς λήξη'
        : 'Λήξη: ${due.day}/${due.month}/${due.year}';
    return [
      createdLabel,
      dueLabel,
    ].where((part) => part.isNotEmpty).join(' · ');
  }
}

class _StudentResult {
  const _StudentResult({
    required this.id,
    required this.name,
    required this.status,
    required this.attemptCount,
    required this.progressValue,
    required this.targetValue,
    required this.bestScore,
    required this.completedAt,
  });

  factory _StudentResult.fromRow(Map<String, dynamic> row) => _StudentResult(
    id: row['result_student_id']?.toString() ?? '',
    name: row['student_name']?.toString().trim().isNotEmpty == true
        ? row['student_name'].toString().trim()
        : 'Μαθητής',
    status: row['result_status']?.toString() ?? 'not_started',
    attemptCount: _readInt(row['attempt_count']),
    progressValue: _readInt(row['progress_value']),
    targetValue: _readInt(row['target_value'], fallback: 1),
    bestScore: (row['best_score'] as num?)?.toDouble(),
    completedAt: DateTime.tryParse(row['completed_at']?.toString() ?? ''),
  );

  final String id;
  final String name;
  final String status;
  final int attemptCount;
  final int progressValue;
  final int targetValue;
  final double? bestScore;
  final DateTime? completedAt;

  String get initial =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  _StatusInfo get statusInfo => switch (status) {
    'completed' => const _StatusInfo(
      'Ολοκληρώθηκε',
      Color(0xFF178A45),
      Icons.check_circle_rounded,
    ),
    'in_progress' => const _StatusInfo(
      'Σε εξέλιξη',
      Color(0xFFF2A000),
      Icons.timelapse_rounded,
    ),
    'retry' => const _StatusInfo(
      'Χρειάζεται νέα προσπάθεια',
      Color(0xFFC62836),
      Icons.refresh_rounded,
    ),
    _ => const _StatusInfo(
      'Δεν ξεκίνησε',
      Color(0xFF7B8190),
      Icons.radio_button_unchecked_rounded,
    ),
  };
}

class _StatusInfo {
  const _StatusInfo(this.label, this.color, this.icon);

  final String label;
  final Color color;
  final IconData icon;
}

int _readInt(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String _formatScore(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day}/${local.month}/${local.year} $hour:$minute';
}
