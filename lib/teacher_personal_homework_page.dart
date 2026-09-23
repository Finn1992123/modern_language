import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeacherPersonalHomeworkPage extends StatefulWidget {
  const TeacherPersonalHomeworkPage({super.key});

  @override
  State<TeacherPersonalHomeworkPage> createState() =>
      _TeacherPersonalHomeworkPageState();
}

class _TeacherPersonalHomeworkPageState
    extends State<TeacherPersonalHomeworkPage> {
  static const _blue = Color(0xFF385DC9);

  final _formKey = GlobalKey<FormState>();
  final _homeworkController = TextEditingController();

  late Future<List<_TeacherClass>> _classesFuture = _loadClasses();
  _TeacherClass? _selectedClass;
  _ClassStudent? _selectedStudent;
  List<_ClassStudent> _students = const [];
  List<_PersonalHomeworkRow> _rows = const [];
  DateTime _forDate = DateTime.now();
  bool _loadingClass = false;
  bool _submitting = false;
  String? _removingId;
  String? _classError;

  @override
  void dispose() {
    _homeworkController.dispose();
    super.dispose();
  }

  Future<List<_TeacherClass>> _loadClasses() async {
    final rows = await Supabase.instance.client.rpc('get_teacher_classes');
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => _TeacherClass.fromRow(Map<String, dynamic>.from(row)))
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  Future<void> _selectClass(_TeacherClass? teacherClass) async {
    setState(() {
      _selectedClass = teacherClass;
      _selectedStudent = null;
      _students = const [];
      _rows = const [];
      _classError = null;
      _loadingClass = teacherClass != null;
    });
    if (teacherClass == null) return;

    try {
      final results = await Future.wait([
        Supabase.instance.client.rpc(
          'get_teacher_class_students',
          params: {'input_class_id': teacherClass.id},
        ),
        Supabase.instance.client.rpc(
          'get_teacher_personal_homework_rows',
          params: {
            'input_class_id': teacherClass.id,
            'input_from_date': _formatIsoDate(DateTime.now()),
          },
        ),
      ]);
      if (!mounted || _selectedClass?.id != teacherClass.id) return;

      final studentRows = results[0];
      final homeworkRows = results[1];
      setState(() {
        _students = studentRows is List
            ? studentRows
                  .whereType<Map>()
                  .map(
                    (row) =>
                        _ClassStudent.fromRow(Map<String, dynamic>.from(row)),
                  )
                  .where((item) => item.id.isNotEmpty)
                  .toList()
            : const [];
        _rows = homeworkRows is List
            ? homeworkRows
                  .whereType<Map>()
                  .map(
                    (row) => _PersonalHomeworkRow.fromRow(
                      Map<String, dynamic>.from(row),
                    ),
                  )
                  .toList()
            : const [];
        _loadingClass = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _classError =
            'Δεν μπορέσαμε να φορτώσουμε τους μαθητές και τα καθήκοντα.';
        _loadingClass = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _forDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() => _forDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _submitting) return;
    final teacherClass = _selectedClass;
    final student = _selectedStudent;
    if (teacherClass == null || student == null) return;

    setState(() => _submitting = true);
    try {
      await Supabase.instance.client.rpc(
        'create_teacher_personal_homework',
        params: {
          'input_class_id': teacherClass.id,
          'input_student_id': student.id,
          'input_for_date': _formatIsoDate(_forDate),
          'input_homework': _homeworkController.text.trim(),
        },
      );
      _homeworkController.clear();
      await _selectClass(teacherClass);
      if (!mounted) return;
      setState(
        () => _selectedStudent = _students
            .where((item) => item.id == student.id)
            .firstOrNull,
      );
      _showMessage('Το προσωπικό καθήκον ανατέθηκε στον/στην ${student.name}.');
    } catch (error) {
      if (mounted) {
        _showMessage('Το προσωπικό καθήκον δεν αποθηκεύτηκε: $error');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _remove(_PersonalHomeworkRow row) async {
    if (_removingId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Αφαίρεση καθήκοντος'),
        content: Text(
          'Να αφαιρεθεί το προσωπικό καθήκον του/της ${row.studentName}; '
          'Δεν θα εμφανίζεται πλέον στον μαθητή.',
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

    setState(() => _removingId = row.id);
    try {
      await Supabase.instance.client.rpc(
        'remove_teacher_personal_homework',
        params: {'input_personal_homework_id': row.id},
      );
      if (!mounted) return;
      setState(() => _rows = _rows.where((item) => item.id != row.id).toList());
      _showMessage('Το προσωπικό καθήκον αφαιρέθηκε.');
    } catch (error) {
      if (mounted) _showMessage('Το καθήκον δεν αφαιρέθηκε: $error');
    } finally {
      if (mounted) setState(() => _removingId = null);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FF),
      appBar: AppBar(
        title: const Text(
          'Προσωπικά καθήκοντα',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        foregroundColor: _blue,
        backgroundColor: Colors.white,
      ),
      body: FutureBuilder<List<_TeacherClass>>(
        future: _classesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: FilledButton.icon(
                onPressed: () => setState(() {
                  _classesFuture = _loadClasses();
                }),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Δοκιμή ξανά'),
              ),
            );
          }

          final classes = snapshot.data ?? const [];
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _SectionCard(
                  title: 'Νέο προσωπικό καθήκον',
                  child: Column(
                    children: [
                      DropdownButtonFormField<_TeacherClass>(
                        initialValue: _selectedClass,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Τμήμα',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final item in classes)
                            DropdownMenuItem(
                              value: item,
                              child: Text(
                                item.title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _loadingClass ? null : _selectClass,
                        validator: (value) =>
                            value == null ? 'Επίλεξε τμήμα' : null,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<_ClassStudent>(
                        key: ValueKey(
                          'student-${_selectedClass?.id}-${_selectedStudent?.id}',
                        ),
                        initialValue: _selectedStudent,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Μαθητής',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final student in _students)
                            DropdownMenuItem(
                              value: student,
                              child: Text(
                                student.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _loadingClass
                            ? null
                            : (value) =>
                                  setState(() => _selectedStudent = value),
                        validator: (value) =>
                            value == null ? 'Επίλεξε μαθητή' : null,
                      ),
                      if (_loadingClass) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                      ],
                      if (_classError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _classError!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _homeworkController,
                        minLines: 4,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          labelText: 'Καθήκοντα',
                          hintText: 'Γράψε το προσωπικό καθήκον του μαθητή',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Γράψε τα καθήκοντα'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_month_rounded),
                        label: Text('Για ${_formatShortDate(_forDate)}'),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.person_add_alt_1_rounded),
                          label: const Text('Ανάθεση στον μαθητή'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  title: 'Προσωπικά καθήκοντα τμήματος',
                  child: _buildRows(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRows() {
    if (_selectedClass == null) {
      return const Text('Επίλεξε τμήμα για να εμφανιστούν τα καθήκοντα.');
    }
    if (_loadingClass) return const Center(child: CircularProgressIndicator());
    if (_rows.isEmpty) {
      return const Text('Δεν υπάρχουν ενεργά προσωπικά καθήκοντα.');
    }
    return Column(
      children: [
        for (final row in _rows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFEAF0FF),
              foregroundColor: _blue,
              child: Icon(Icons.person_rounded),
            ),
            title: Text(
              row.studentName,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text('${row.formattedDate}\n${row.homework}'),
            isThreeLine: true,
            trailing: _removingId == row.id
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: 'Αφαίρεση',
                    onPressed: _removingId == null ? () => _remove(row) : null,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.redAccent,
                    ),
                  ),
          ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12385DC9),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _TeacherPersonalHomeworkPageState._blue,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 15),
          child,
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

  factory _TeacherClass.fromRow(Map<String, dynamic> row) => _TeacherClass(
    id: row['id']?.toString() ?? '',
    name: _readText(row['name']),
    language: _readText(row['language']) ?? '',
    daysHours: _readText(row['days_hours']),
  );

  final String id;
  final String? name;
  final String language;
  final String? daysHours;

  String get title => [
    if (name != null) name!,
    if (language.isNotEmpty) language,
    if (daysHours != null) daysHours!,
  ].join(' · ');
}

class _ClassStudent {
  const _ClassStudent({required this.id, required this.name});

  factory _ClassStudent.fromRow(Map<String, dynamic> row) => _ClassStudent(
    id: row['student_id']?.toString() ?? '',
    name: _readText(row['student_name']) ?? 'Μαθητής',
  );

  final String id;
  final String name;
}

class _PersonalHomeworkRow {
  const _PersonalHomeworkRow({
    required this.id,
    required this.forDate,
    required this.homework,
    required this.studentName,
  });

  factory _PersonalHomeworkRow.fromRow(Map<String, dynamic> row) =>
      _PersonalHomeworkRow(
        id: row['personal_homework_id']?.toString() ?? '',
        forDate: DateTime.tryParse(row['for_date']?.toString() ?? ''),
        homework: _readText(row['homework']) ?? '',
        studentName: _readText(row['student_name']) ?? 'Μαθητής',
      );

  final String id;
  final DateTime? forDate;
  final String homework;
  final String studentName;

  String get formattedDate => _formatShortDate(forDate);
}

String _formatIsoDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _formatShortDate(DateTime? date) {
  if (date == null) return '-';
  return '${date.day}/${date.month}/${date.year}';
}

String? _readText(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}
