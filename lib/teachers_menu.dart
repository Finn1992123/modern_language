import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'teacher_payments.dart';

class TeachersMenuPage extends StatefulWidget {
  const TeachersMenuPage({super.key});

  @override
  State<TeachersMenuPage> createState() => _TeachersMenuPageState();
}

class _TeachersMenuPageState extends State<TeachersMenuPage> {
  static const Color _headerColor = Color(0xFF627DE4);
  static const Color _contentColor = Color(0xFF173A8A);

  final _inClassController = TextEditingController();
  final _homeworkController = TextEditingController();
  final Map<String, _StudentGradeForm> _studentForms = {};
  final Set<String> _completedCurriculumClassIds = {};

  List<_TeacherClass> _classes = const [];
  List<_ClassStudent> _students = const [];
  _TeacherClass? _selectedClass;
  DateTime _homeworkDate = DateTime.now();
  bool _classesVisible = false;
  bool _isLoadingClasses = false;
  bool _isLoadingStudents = false;
  bool _isSubmittingCurriculum = false;
  String? _loadError;

  @override
  void dispose() {
    _inClassController.dispose();
    _homeworkController.dispose();
    for (final form in _studentForms.values) {
      form.dispose();
    }
    super.dispose();
  }

  Future<void> _loadClasses() async {
    if (_classesVisible) {
      setState(() {
        _classesVisible = false;
        _selectedClass = null;
        _students = const [];
        _loadError = null;
      });
      return;
    }

    setState(() {
      _classesVisible = true;
      _isLoadingClasses = true;
      _loadError = null;
    });

    try {
      final rows = await Supabase.instance.client.rpc('get_teacher_classes');

      if (!mounted) {
        return;
      }

      setState(() {
        _classes = rows is List
            ? rows
                  .whereType<Map>()
                  .map(
                    (row) =>
                        _TeacherClass.fromRow(Map<String, dynamic>.from(row)),
                  )
                  .where((item) => item.id.isNotEmpty)
                  .toList()
            : const [];
        _isLoadingClasses = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadError = 'Δεν μπορέσαμε να φορτώσουμε τις τάξεις σου.';
        _isLoadingClasses = false;
      });
    }
  }

  void _openTeacherPayments() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const TeacherPaymentsPage(),
      ),
    );
  }

  Future<void> _selectClass(_TeacherClass teacherClass) async {
    if (_selectedClass?.id == teacherClass.id) {
      setState(() {
        _selectedClass = null;
        _students = const [];
        _loadError = null;
      });
      return;
    }

    setState(() {
      _selectedClass = null;
      _students = const [];
      _isLoadingStudents = true;
      _loadError = null;
    });

    try {
      final rows = await Supabase.instance.client.rpc(
        'get_teacher_class_students',
        params: {'input_class_id': teacherClass.id},
      );

      final students =
          rows is List
                ? rows
                      .whereType<Map>()
                      .map(
                        (row) => _ClassStudent.fromRow(
                          Map<String, dynamic>.from(row),
                        ),
                      )
                      .where((student) => student.studentLanguageId.isNotEmpty)
                      .toList()
                : <_ClassStudent>[]
            ..sort((a, b) => a.name.compareTo(b.name));

      for (final student in students) {
        _studentForms.putIfAbsent(
          student.studentLanguageId,
          _StudentGradeForm.new,
        );
        _studentForms[student.studentLanguageId]!.completionMessage = null;
        await _studentForms[student.studentLanguageId]!.loadAverages(
          student.studentLanguageId,
        );
      }

      final today = _formatIsoDate(DateTime.now());
      final curriculumCompleted = await Supabase.instance.client.rpc(
        'get_teacher_curriculum_completed_today',
        params: {'input_class_id': teacherClass.id, 'input_local_date': today},
      );
      final studentCompletions = await Supabase.instance.client.rpc(
        'get_teacher_student_completion_today',
        params: {'input_class_id': teacherClass.id, 'input_local_date': today},
      );

      if (studentCompletions is List) {
        for (final row in studentCompletions.whereType<Map>()) {
          final data = Map<String, dynamic>.from(row);
          final studentLanguageId = data['student_language_id']?.toString();
          final message = _readText(data['completion_message']);

          if (studentLanguageId != null && message != null) {
            _studentForms[studentLanguageId]?.completionMessage = message;
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedClass = teacherClass;
        if (curriculumCompleted == true) {
          _completedCurriculumClassIds.add(teacherClass.id);
        } else {
          _completedCurriculumClassIds.remove(teacherClass.id);
        }
        _students = students;
        _isLoadingStudents = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadError = 'Δεν μπορέσαμε να φορτώσουμε τους μαθητές της τάξης.';
        _isLoadingStudents = false;
      });
    }
  }

  Future<void> _pickHomeworkDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _homeworkDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _homeworkDate = picked;
    });
  }

  Future<void> _submitCurriculum() async {
    final selectedClass = _selectedClass;
    if (selectedClass == null || _isSubmittingCurriculum) {
      return;
    }

    setState(() {
      _isSubmittingCurriculum = true;
    });

    try {
      await Supabase.instance.client.rpc(
        'insert_teacher_curriculum',
        params: {
          'input_class_id': selectedClass.id,
          'input_for_date': _formatIsoDate(_homeworkDate),
          'input_in_class': _inClassController.text,
          'input_homework': _homeworkController.text,
        },
      );

      _inClassController.clear();
      _homeworkController.clear();
      if (mounted) {
        setState(() {
          _completedCurriculumClassIds.add(selectedClass.id);
        });
      }
      _showMessage('Η ύλη και τα καθήκοντα αποθηκεύτηκαν.');
    } catch (_) {
      _showMessage('Δεν μπορέσαμε να αποθηκεύσουμε την ύλη.');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingCurriculum = false;
        });
      }
    }
  }

  Future<void> _submitAbsence(_ClassStudent student) async {
    final form = _studentForms[student.studentLanguageId];
    if (form == null || form.isSubmitting) {
      return;
    }

    setState(() {
      form.isSubmitting = true;
    });

    try {
      await Supabase.instance.client.rpc(
        'insert_teacher_absence',
        params: {
          'input_student_language_id': student.studentLanguageId,
          'input_student_id': student.studentId,
          'input_student_name': student.name,
        },
      );

      if (mounted) {
        setState(() {
          form.completionMessage = 'Η απουσία καταχωρήθηκε';
        });
      }
      _showMessage('Η απουσία αποθηκεύτηκε για ${student.name}.');
    } catch (_) {
      _showMessage('Δεν μπορέσαμε να αποθηκεύσουμε την απουσία.');
    } finally {
      if (mounted) {
        setState(() {
          form.isSubmitting = false;
        });
      }
    }
  }

  Future<void> _submitGrades(_ClassStudent student) async {
    final form = _studentForms[student.studentLanguageId];
    if (form == null || form.isSubmitting) {
      return;
    }

    setState(() {
      form.isSubmitting = true;
    });

    try {
      await Supabase.instance.client.rpc(
        'insert_teacher_student_grades',
        params: {
          'input_student_language_id': student.studentLanguageId,
          'input_student_id': student.studentId,
          'input_student_name': student.name,
          'input_reading': form.gradeValue('reading'),
          'input_vocabulary': form.gradeValue('vocabulary'),
          'input_grammar': form.gradeValue('grammar'),
          'input_writing': form.gradeValue('writing'),
          'input_listening': form.gradeValue('listening'),
          'input_speaking': form.gradeValue('speaking'),
          'input_homework': form.gradeValue('homework'),
          'input_effort': form.gradeValue('effort'),
          'input_comments': form.commentsController.text,
        },
      );

      form.clearInputs();
      if (mounted) {
        setState(() {
          form.completionMessage = 'Οι βαθμοί καταχωρήθηκαν';
        });
      }
      _showMessage('Οι βαθμοί αποθηκεύτηκαν για ${student.name}.');
    } catch (_) {
      _showMessage('Δεν μπορέσαμε να αποθηκεύσουμε τους βαθμούς.');
    } finally {
      if (mounted) {
        setState(() {
          form.isSubmitting = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Align(
              alignment: Alignment.centerLeft,
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
            const SizedBox(height: 8),
            const Text(
              'Μενού Καθηγητών',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _contentColor,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                height: 1.08,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _isLoadingClasses ? null : _loadClasses,
              icon: _isLoadingClasses
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.school_rounded),
              label: const Text('Οι τάξεις μου'),
              style: FilledButton.styleFrom(
                backgroundColor: _headerColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _openTeacherPayments,
              icon: const Icon(Icons.savings_rounded),
              label: const Text('Πληρωμές'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDB9538),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_loadError != null) ...[
              const SizedBox(height: 14),
              _InfoPanel(text: _loadError!, icon: Icons.error_outline_rounded),
            ],
            if (_classesVisible) ...[
              const SizedBox(height: 18),
              _buildClasses(),
            ],
            if (_isLoadingStudents) ...[
              const SizedBox(height: 22),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_selectedClass != null) ...[
              const SizedBox(height: 22),
              _CurriculumCard(
                selectedClass: _selectedClass!,
                homeworkDate: _homeworkDate,
                inClassController: _inClassController,
                homeworkController: _homeworkController,
                isCompleted: _completedCurriculumClassIds.contains(
                  _selectedClass!.id,
                ),
                isSubmitting: _isSubmittingCurriculum,
                onPickDate: _pickHomeworkDate,
                onSubmit: _submitCurriculum,
              ),
              const SizedBox(height: 22),
              _buildStudents(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClasses() {
    if (_isLoadingClasses) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_classes.isEmpty) {
      return const _InfoPanel(
        text: 'Δεν υπάρχουν τάξεις συνδεδεμένες με αυτόν τον καθηγητή.',
        icon: Icons.info_outline_rounded,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final teacherClass in _classes) ...[
          _ClassTile(
            teacherClass: teacherClass,
            isSelected: teacherClass.id == _selectedClass?.id,
            onTap: () => _selectClass(teacherClass),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildStudents() {
    if (_isLoadingStudents) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_students.isEmpty) {
      return const _InfoPanel(
        text: 'Δεν υπάρχουν μαθητές σε αυτή την τάξη.',
        icon: Icons.group_off_rounded,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final student in _students) ...[
          _StudentGradeCard(
            student: student,
            form: _studentForms[student.studentLanguageId]!,
            onAbsence: () => _submitAbsence(student),
            onSubmit: () => _submitGrades(student),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _CurriculumCard extends StatelessWidget {
  const _CurriculumCard({
    required this.selectedClass,
    required this.homeworkDate,
    required this.inClassController,
    required this.homeworkController,
    required this.isCompleted,
    required this.isSubmitting,
    required this.onPickDate,
    required this.onSubmit,
  });

  final _TeacherClass selectedClass;
  final DateTime homeworkDate;
  final TextEditingController inClassController;
  final TextEditingController homeworkController;
  final bool isCompleted;
  final bool isSubmitting;
  final VoidCallback onPickDate;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    if (isCompleted) {
      return _CompletedCard(
        title: selectedClass.title,
        message: 'Έχουν μπει μαθήματα και καθήκοντα για αυτή την τάξη',
      );
    }

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            selectedClass.title,
            style: const TextStyle(
              color: _TeachersMenuPageState._contentColor,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: inClassController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'In class',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Επέλεξε ημερομηνία για καθήκοντα:',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onPickDate,
            icon: const Icon(Icons.calendar_month_rounded),
            label: Text(_formatDisplayDate(homeworkDate)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: homeworkController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Καθήκοντα',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: isSubmitting ? null : onSubmit,
            child: isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Τέλος'),
          ),
        ],
      ),
    );
  }
}

class _StudentGradeCard extends StatelessWidget {
  const _StudentGradeCard({
    required this.student,
    required this.form,
    required this.onAbsence,
    required this.onSubmit,
  });

  final _ClassStudent student;
  final _StudentGradeForm form;
  final VoidCallback onAbsence;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    if (form.completionMessage != null) {
      return _CompletedCard(
        title: student.name,
        message: form.completionMessage!,
      );
    }

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            student.name,
            style: const TextStyle(
              color: _TeachersMenuPageState._contentColor,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          for (final item in _gradeItems) ...[
            _GradeInputRow(
              label: item.label,
              controller: form.controllers[item.key]!,
              average: form.averages[item.key],
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 4),
          TextField(
            controller: form.commentsController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Comments',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: form.isSubmitting ? null : onAbsence,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Απουσία'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: form.isSubmitting ? null : onSubmit,
                  child: form.isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Τέλος'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GradeInputRow extends StatelessWidget {
  const _GradeInputRow({
    required this.label,
    required this.controller,
    required this.average,
  });

  final String label;
  final TextEditingController controller;
  final double? average;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 82,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(r'^\d{0,3}([.,]\d{0,1})?'),
              ),
              _MaxGradeFormatter(),
            ],
            decoration: const InputDecoration(
              suffixText: '%',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Μ.Ο. ${_formatAverage(average)}',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
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
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(
                Icons.groups_rounded,
                color: _TeachersMenuPageState._contentColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  teacherClass.title,
                  style: const TextStyle(
                    color: _TeachersMenuPageState._contentColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletedCard extends StatelessWidget {
  const _CompletedCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F8D8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF86C85F), width: 1.4),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFF58B832),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF245817),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFF3C6D2B),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E8F2)),
      ),
      child: child,
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Row(
        children: [
          Icon(icon, color: _TeachersMenuPageState._contentColor),
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

class _ClassStudent {
  const _ClassStudent({
    required this.studentLanguageId,
    required this.studentId,
    required this.name,
  });

  factory _ClassStudent.fromRow(Map<String, dynamic> row) {
    return _ClassStudent(
      studentLanguageId: row['student_language_id']?.toString() ?? '',
      studentId: row['student_id']?.toString() ?? '',
      name: _readText(row['student_name']) ?? 'Μαθητής',
    );
  }

  final String studentLanguageId;
  final String studentId;
  final String name;
}

class _StudentGradeForm {
  _StudentGradeForm()
    : controllers = {
        for (final item in _gradeItems) item.key: TextEditingController(),
      };

  final Map<String, TextEditingController> controllers;
  final commentsController = TextEditingController();
  final Map<String, double?> averages = {
    for (final item in _gradeItems) item.key: null,
  };
  String? completionMessage;
  bool isSubmitting = false;

  Future<void> loadAverages(String studentLanguageId) async {
    final rows = await Supabase.instance.client.rpc(
      'get_teacher_student_grade_averages',
      params: {'input_student_language_id': studentLanguageId},
    );

    if (rows is! List || rows.isEmpty || rows.first is! Map) {
      return;
    }

    final row = Map<String, dynamic>.from(rows.first as Map);
    for (final item in _gradeItems) {
      averages[item.key] = row[item.key] is num
          ? (row[item.key] as num).toDouble()
          : null;
    }
  }

  double? gradeValue(String key) {
    final text = controllers[key]?.text.trim().replaceAll(',', '.') ?? '';
    if (text.isEmpty) {
      return null;
    }

    final value = double.tryParse(text);
    return value?.clamp(0, 100).toDouble();
  }

  void clearInputs() {
    for (final controller in controllers.values) {
      controller.clear();
    }
    commentsController.clear();
  }

  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    commentsController.dispose();
  }
}

class _GradeItem {
  const _GradeItem(this.key, this.label);

  final String key;
  final String label;
}

const _gradeItems = [
  _GradeItem('reading', 'Reading'),
  _GradeItem('vocabulary', 'Vocabulary'),
  _GradeItem('grammar', 'Grammar'),
  _GradeItem('listening', 'Listening'),
  _GradeItem('speaking', 'Speaking'),
  _GradeItem('writing', 'Writing'),
  _GradeItem('effort', 'Effort'),
  _GradeItem('homework', 'HW'),
];

class _MaxGradeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    final value = double.tryParse(newValue.text.replaceAll(',', '.'));
    if (value == null || value <= 100) {
      return newValue;
    }

    return oldValue;
  }
}

String _formatDisplayDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String _formatIsoDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

String _formatAverage(double? value) {
  if (value == null) {
    return '-';
  }

  return '${value.toStringAsFixed(1)}%';
}

String? _readText(Object? value) {
  if (value is! String) {
    return null;
  }

  final text = value.trim();
  return text.isEmpty ? null : text;
}
