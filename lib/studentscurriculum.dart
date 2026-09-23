import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudentsCurriculumPage extends StatefulWidget {
  const StudentsCurriculumPage({super.key});

  @override
  State<StudentsCurriculumPage> createState() => _StudentsCurriculumPageState();
}

class _StudentsCurriculumPageState extends State<StudentsCurriculumPage> {
  static const Color _headerColor = Color(0xFF89ACFF);
  static const Color _contentColor = Color(0xFF385DC9);

  late Future<List<_TeacherClass>> _classesFuture = _loadClasses();
  _TeacherClass? _selectedClass;
  List<_CurriculumRow> _rows = const [];
  bool _isLoadingRows = false;
  String? _removingPersonalHomeworkId;
  String? _loadError;

  Future<List<_TeacherClass>> _loadClasses() async {
    final rows = await Supabase.instance.client.rpc('get_teacher_classes');

    if (rows is! List) {
      return const [];
    }

    return rows
        .whereType<Map>()
        .map((row) => _TeacherClass.fromRow(Map<String, dynamic>.from(row)))
        .where((teacherClass) => teacherClass.id.isNotEmpty)
        .toList();
  }

  void _refreshClasses() {
    setState(() {
      _classesFuture = _loadClasses();
      _selectedClass = null;
      _rows = const [];
      _loadError = null;
    });
  }

  Future<void> _selectClass(_TeacherClass teacherClass) async {
    if (_selectedClass?.id == teacherClass.id) {
      setState(() {
        _selectedClass = null;
        _rows = const [];
        _loadError = null;
      });
      return;
    }

    setState(() {
      _selectedClass = teacherClass;
      _rows = const [];
      _isLoadingRows = true;
      _loadError = null;
    });

    try {
      final rows = await Supabase.instance.client.rpc(
        'get_teacher_upcoming_homework_rows',
        params: {
          'input_class_id': teacherClass.id,
          'input_from_date': _formatIsoDate(DateTime.now()),
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _rows = rows is List
            ? rows
                  .whereType<Map>()
                  .map(
                    (row) =>
                        _CurriculumRow.fromRow(Map<String, dynamic>.from(row)),
                  )
                  .toList()
            : const [];
        _isLoadingRows = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadError = 'Δεν μπορέσαμε να φορτώσουμε τα καθήκοντα.';
        _isLoadingRows = false;
      });
    }
  }

  Future<void> _removePersonalHomework(_CurriculumRow row) async {
    final id = row.personalHomeworkId;
    if (id == null || _removingPersonalHomeworkId != null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Αφαίρεση καθήκοντος'),
        content: Text(
          'Να αφαιρεθεί το προσωπικό καθήκον του/της '
          '${row.studentName ?? 'μαθητή'}; Δεν θα εμφανίζεται πλέον στον μαθητή.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Αφαίρεση'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _removingPersonalHomeworkId = id);
    try {
      await Supabase.instance.client.rpc(
        'remove_teacher_personal_homework',
        params: {'input_personal_homework_id': id},
      );
      if (!mounted) return;
      setState(() {
        _rows = _rows.where((item) => item.personalHomeworkId != id).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Το προσωπικό καθήκον αφαιρέθηκε.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Το καθήκον δεν αφαιρέθηκε: $error')),
      );
    } finally {
      if (mounted) setState(() => _removingPersonalHomeworkId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            height: 220,
            decoration: const BoxDecoration(
              color: _headerColor,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(42),
                bottomRight: Radius.circular(42),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  Positioned(
                    left: 18,
                    top: 12,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
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
                  ),
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Τα καθήκοντα',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _contentColor,
                            fontSize: 31,
                            fontWeight: FontWeight.w900,
                            height: 1.08,
                          ),
                        ),
                        SizedBox(height: 12),
                        Icon(
                          Icons.assignment_rounded,
                          color: _contentColor,
                          size: 76,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<_TeacherClass>>(
              future: _classesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return _MessagePanel(
                    text: 'Δεν μπορέσαμε να φορτώσουμε τις τάξεις.',
                    onRetry: _refreshClasses,
                  );
                }

                final classes = snapshot.data ?? const [];

                if (classes.isEmpty) {
                  return const _MessagePanel(
                    text: 'Δεν υπάρχουν τάξεις για αυτόν τον καθηγητή.',
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
                  children: [
                    for (final teacherClass in classes) ...[
                      _ClassTile(
                        teacherClass: teacherClass,
                        isSelected: teacherClass.id == _selectedClass?.id,
                        onTap: () => _selectClass(teacherClass),
                      ),
                      if (teacherClass.id == _selectedClass?.id) ...[
                        const SizedBox(height: 12),
                        _buildSelectedClassRows(),
                      ],
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedClassRows() {
    if (_isLoadingRows) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return _InfoCard(text: _loadError!, icon: Icons.error_outline_rounded);
    }

    if (_rows.isEmpty) {
      return const _InfoCard(
        text: 'Δεν υπάρχουν καθήκοντα από σήμερα και μετά.',
        icon: Icons.event_busy_rounded,
      );
    }

    return Column(
      children: [
        for (final row in _rows) ...[
          _CurriculumCard(
            row: row,
            isRemoving: row.personalHomeworkId == _removingPersonalHomeworkId,
            onRemove: row.isPersonal
                ? () => _removePersonalHomework(row)
                : null,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ClassTile extends StatelessWidget {
  const _ClassTile({
    required this.teacherClass,
    required this.isSelected,
    required this.onTap,
  });

  final _TeacherClass teacherClass;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? const Color(0xFFEAF0FF) : const Color(0xFFF7F8FC),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              const Icon(
                Icons.groups_rounded,
                color: _StudentsCurriculumPageState._contentColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  teacherClass.title,
                  style: const TextStyle(
                    color: _StudentsCurriculumPageState._contentColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(
                isSelected
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.chevron_right_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurriculumCard extends StatelessWidget {
  const _CurriculumCard({
    required this.row,
    required this.isRemoving,
    required this.onRemove,
  });

  final _CurriculumRow row;
  final bool isRemoving;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E9FA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                row.isPersonal
                    ? Icons.person_rounded
                    : Icons.calendar_month_rounded,
                color: row.isPersonal
                    ? const Color(0xFF7B4CC9)
                    : _StudentsCurriculumPageState._contentColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  row.isPersonal
                      ? 'Προσωπικό · ${row.studentName ?? 'Μαθητής'} · ${row.formattedForDate}'
                      : row.formattedForDate,
                  style: TextStyle(
                    color: row.isPersonal
                        ? const Color(0xFF7B4CC9)
                        : _StudentsCurriculumPageState._contentColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (onRemove != null)
                isRemoving
                    ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: Padding(
                          padding: EdgeInsets.all(9),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Αφαίρεση',
                        onPressed: onRemove,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent,
                        ),
                      ),
            ],
          ),
          if (row.inClass != null) ...[
            const SizedBox(height: 12),
            const Text(
              'In class',
              style: TextStyle(
                color: Color(0xFF202124),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              row.inClass!,
              style: const TextStyle(
                color: Color(0xFF313A2E),
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.28,
              ),
            ),
          ],
          if (row.homework != null) ...[
            const SizedBox(height: 12),
            Text(
              'Καθήκοντα για ${row.formattedForDate}',
              style: const TextStyle(
                color: Color(0xFF202124),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              row.homework!,
              style: const TextStyle(
                color: Color(0xFF313A2E),
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.28,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E8F2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _StudentsCurriculumPageState._contentColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
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

class _TeacherClass {
  const _TeacherClass({
    required this.id,
    required this.name,
    required this.language,
    required this.daysHours,
  });

  factory _TeacherClass.fromRow(Map<String, dynamic> row) {
    return _TeacherClass(
      id: row['id']?.toString() ?? '',
      name: _readText(row['name']),
      language: _readText(row['language']) ?? 'Τάξη',
      daysHours: _readText(row['days_hours']),
    );
  }

  final String id;
  final String? name;
  final String language;
  final String? daysHours;

  String get title {
    final className = name;
    final base = className == null ? language : '$className - $language';
    return daysHours == null ? base : '$base - $daysHours';
  }
}

class _CurriculumRow {
  const _CurriculumRow({
    required this.personalHomeworkId,
    required this.forDate,
    required this.inClass,
    required this.homework,
    required this.isPersonal,
    required this.studentName,
  });

  factory _CurriculumRow.fromRow(Map<String, dynamic> row) {
    return _CurriculumRow(
      personalHomeworkId: _readText(row['personal_homework_id']),
      forDate: DateTime.tryParse(row['for_date']?.toString() ?? ''),
      inClass: _readText(row['in_class']),
      homework: _readText(row['homework']),
      isPersonal: row['is_personal'] == true,
      studentName: _readText(row['student_name']),
    );
  }

  final String? personalHomeworkId;
  final DateTime? forDate;
  final String? inClass;
  final String? homework;
  final bool isPersonal;
  final String? studentName;

  String get formattedForDate => _formatShortDate(forDate);
}

String _formatShortDate(DateTime? date) {
  if (date == null) {
    return '-';
  }

  final year = (date.year % 100).toString().padLeft(2, '0');
  return '${date.day}/${date.month}/$year';
}

String _formatIsoDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String? _readText(Object? value) {
  if (value is! String) {
    return null;
  }

  final text = value.trim();
  return text.isEmpty ? null : text;
}
