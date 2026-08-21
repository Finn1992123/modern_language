import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeacherDictationPage extends StatefulWidget {
  const TeacherDictationPage({super.key});

  @override
  State<TeacherDictationPage> createState() => _TeacherDictationPageState();
}

class _TeacherDictationPageState extends State<TeacherDictationPage> {
  static const _purple = Color(0xFF4D4AAD);
  final _formKey = GlobalKey<FormState>();
  final _wordCountController = TextEditingController(text: '15');
  final _customMinutesController = TextEditingController(text: '15');
  late Future<List<_TeacherClass>> _classesFuture = _loadClasses();
  List<_VocabularyUnit> _units = const [];
  _TeacherClass? _selectedClass;
  _VocabularyUnit? _selectedUnit;
  bool _importantOnly = false;
  bool _customWordCount = false;
  int _durationMinutes = 5;
  bool _loadingUnits = false;
  bool _creating = false;

  @override
  void dispose() {
    _wordCountController.dispose();
    _customMinutesController.dispose();
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

  Future<void> _selectClass(_TeacherClass? value) async {
    setState(() {
      _selectedClass = value;
      _selectedUnit = null;
      _units = const [];
      _loadingUnits = value != null;
    });
    if (value == null) return;
    try {
      final rows = await Supabase.instance.client.rpc(
        'get_teacher_assignment_vocabulary_units',
        params: {'input_class_id': value.id},
      );
      if (!mounted || _selectedClass?.id != value.id) return;
      setState(() {
        _units = rows is List
            ? rows
                  .whereType<Map>()
                  .map(
                    (row) =>
                        _VocabularyUnit.fromRow(Map<String, dynamic>.from(row)),
                  )
                  .where((unit) => unit.unit.isNotEmpty)
                  .toList()
            : const [];
        _loadingUnits = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingUnits = false);
      _message('Δεν φορτώθηκαν οι ενότητες του τμήματος.');
    }
  }

  Future<void> _createRoom() async {
    if (!_formKey.currentState!.validate()) return;
    final teacherClass = _selectedClass;
    final unit = _selectedUnit;
    if (teacherClass == null || unit == null) {
      _message('Επίλεξε τμήμα και ενότητα.');
      return;
    }
    final available = _importantOnly ? unit.importantWordCount : unit.wordCount;
    if (available == 0) {
      _message(
        'Δεν υπάρχουν ${_importantOnly ? 'σημαντικές ' : ''}λέξεις σε αυτή την ενότητα.',
      );
      return;
    }
    final minutes = _durationMinutes == 0
        ? int.parse(_customMinutesController.text)
        : _durationMinutes;
    setState(() => _creating = true);
    try {
      final response = await Supabase.instance.client.rpc(
        'create_live_dictation_room',
        params: {
          'input_class_id': teacherClass.id,
          'input_unit': unit.unit,
          'input_unit_order': unit.unitOrder,
          'input_important_only': _importantOnly,
          'input_word_count': _customWordCount
              ? int.parse(_wordCountController.text)
              : null,
          'input_duration_seconds': minutes * 60,
        },
      );
      if (!mounted || response is! Map) return;
      final data = Map<String, dynamic>.from(response);
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => TeacherDictationRoomPage(
            roomId: data['room_id'].toString(),
            initialCode: data['code']?.toString() ?? '',
          ),
        ),
      );
    } catch (error) {
      if (mounted) _message('Το δωμάτιο δεν δημιουργήθηκε: $error');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _message(String value) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(value), behavior: SnackBarBehavior.floating),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FF),
      appBar: AppBar(
        title: const Text(
          'Δημιουργία ορθογραφίας',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        foregroundColor: _purple,
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
              child: FilledButton(
                onPressed: () =>
                    setState(() => _classesFuture = _loadClasses()),
                child: const Text('Δοκιμή ξανά'),
              ),
            );
          }
          final classes = snapshot.data ?? const [];
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _Card(
                  title: 'Λέξεις',
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
                      onChanged: _selectClass,
                      validator: (value) =>
                          value == null ? 'Επίλεξε τμήμα' : null,
                    ),
                    const SizedBox(height: 14),
                    if (_loadingUnits)
                      const Center(child: CircularProgressIndicator())
                    else
                      DropdownButtonFormField<_VocabularyUnit>(
                        initialValue: _selectedUnit,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Ενότητα',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final item in _units)
                            DropdownMenuItem(
                              value: item,
                              child: Text(
                                item.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _selectedUnit = value),
                        validator: (value) =>
                            value == null ? 'Επίλεξε ενότητα' : null,
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Important words',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        _selectedUnit == null
                            ? 'Μόνο λέξεις με is_important = true'
                            : '${_selectedUnit!.importantWordCount} σημαντικές λέξεις',
                      ),
                      value: _importantOnly,
                      onChanged: (value) =>
                          setState(() => _importantOnly = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Επιλογή αριθμού λέξεων'),
                      subtitle: const Text(
                        'Αλλιώς επιλέγονται τυχαία έως 15 λέξεις',
                      ),
                      value: _customWordCount,
                      onChanged: (value) =>
                          setState(() => _customWordCount = value),
                    ),
                    if (_customWordCount)
                      TextFormField(
                        controller: _wordCountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Αριθμός λέξεων',
                          border: OutlineInputBorder(),
                        ),
                        validator: _positiveInteger,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _Card(
                  title: 'Χρόνος',
                  children: [
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 5, label: Text('5 λεπτά')),
                        ButtonSegment(value: 10, label: Text('10 λεπτά')),
                        ButtonSegment(value: 0, label: Text('Custom')),
                      ],
                      selected: {_durationMinutes},
                      onSelectionChanged: (value) =>
                          setState(() => _durationMinutes = value.first),
                    ),
                    if (_durationMinutes == 0) ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _customMinutesController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Λεπτά (1–120)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final parsed = int.tryParse(value ?? '');
                          return parsed == null || parsed < 1 || parsed > 120
                              ? 'Δώσε χρόνο από 1 έως 120 λεπτά'
                              : null;
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _creating ? null : _createRoom,
                  icon: _creating
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.meeting_room_rounded),
                  label: const Text('Δημιουργία δωματίου'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _purple,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class TeacherDictationRoomPage extends StatefulWidget {
  const TeacherDictationRoomPage({
    super.key,
    required this.roomId,
    required this.initialCode,
  });
  final String roomId;
  final String initialCode;

  @override
  State<TeacherDictationRoomPage> createState() =>
      _TeacherDictationRoomPageState();
}

class _TeacherDictationRoomPageState extends State<TeacherDictationRoomPage> {
  Timer? _timer;
  _TeacherRoom? _room;
  bool _loading = true;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final value = await Supabase.instance.client.rpc(
        'get_teacher_live_activity_room',
        params: {'input_room_id': widget.roomId},
      );
      if (!mounted || value is! Map) return;
      setState(() {
        _room = _TeacherRoom.fromRow(Map<String, dynamic>.from(value));
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      await Supabase.instance.client.rpc(
        'start_live_activity_room',
        params: {'input_room_id': widget.roomId},
      );
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Δεν ξεκίνησε η ορθογραφία: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FF),
      appBar: AppBar(
        title: const Text(
          'Live ορθογραφία',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: _loading && room == null
          ? const Center(child: CircularProgressIndicator())
          : room == null
          ? const Center(child: Text('Δεν φορτώθηκε το δωμάτιο.'))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4D4AAD),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      Text(
                        room.status == 'waiting'
                            ? 'Κωδικός συμμετοχής'
                            : room.status == 'active'
                            ? 'Η ορθογραφία είναι σε εξέλιξη'
                            : 'Η ορθογραφία ολοκληρώθηκε',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        room.code.isEmpty ? widget.initialCode : room.code,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 7,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${room.wordCount} λέξεις · ${room.durationSeconds ~/ 60} λεπτά · ${room.unit}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Κατάταξη μαθητών',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Chip(label: Text('${room.participants.length}')),
                  ],
                ),
                const SizedBox(height: 8),
                if (room.participants.isEmpty)
                  const _EmptyParticipants()
                else
                  for (final entry in room.participants.indexed)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: entry.$2.score == null
                              ? const Color(0xFFE8E8F7)
                              : _rankingColor(entry.$1),
                          child: Text(
                            entry.$2.score == null
                                ? entry.$2.name.characters.first
                                : '#${entry.$1 + 1}',
                            style: TextStyle(
                              color: entry.$2.score == null
                                  ? const Color(0xFF4D4AAD)
                                  : Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        title: Text(
                          entry.$2.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          entry.$2.submitted
                              ? 'Υπέβαλε απαντήσεις'
                              : room.status == 'waiting'
                              ? 'Συνδέθηκε'
                              : 'Γράφει...',
                        ),
                        trailing: entry.$2.score == null
                            ? Icon(
                                entry.$2.submitted
                                    ? Icons.check_circle
                                    : Icons.circle,
                                color: entry.$2.submitted
                                    ? Colors.green
                                    : Colors.lightGreen,
                                size: 18,
                              )
                            : Text(
                                '${entry.$2.correctCount}/${room.wordCount}\n${entry.$2.score!.toStringAsFixed(0)}%',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                      ),
                    ),
                if (room.status == 'waiting') ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: room.participants.isEmpty || _starting
                        ? null
                        : _start,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      room.participants.isEmpty
                          ? 'Περιμένουμε μαθητές'
                          : 'Έναρξη',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF18A8EF),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
}

class _EmptyParticipants extends StatelessWidget {
  const _EmptyParticipants();
  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.groups_rounded, size: 48, color: Colors.grey),
          SizedBox(height: 8),
          Text(
            'Οι μαθητές θα εμφανιστούν εδώ μόλις βάλουν τον κωδικό.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
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
    name: row['name']?.toString().trim(),
    language: row['language']?.toString().trim() ?? '',
    daysHours: row['days_hours']?.toString().trim(),
  );
  final String id;
  final String? name;
  final String language;
  final String? daysHours;
  String get title => [
    if (name != null && name!.isNotEmpty) name!,
    if (language.isNotEmpty) language,
    if (daysHours != null && daysHours!.isNotEmpty) daysHours!,
  ].join(' · ');
}

class _VocabularyUnit {
  const _VocabularyUnit({
    required this.unit,
    required this.unitOrder,
    required this.level,
    required this.wordCount,
    required this.importantWordCount,
  });
  factory _VocabularyUnit.fromRow(Map<String, dynamic> row) => _VocabularyUnit(
    unit: row['unit']?.toString().trim() ?? '',
    unitOrder: (row['unit_order'] as num?)?.toInt(),
    level: row['level']?.toString().trim() ?? '',
    wordCount: (row['word_count'] as num?)?.toInt() ?? 0,
    importantWordCount: (row['important_word_count'] as num?)?.toInt() ?? 0,
  );
  final String unit;
  final int? unitOrder;
  final String level;
  final int wordCount;
  final int importantWordCount;
  String get label =>
      '$unit${level.isEmpty ? '' : ' · $level'} ($wordCount λέξεις)';
}

class _TeacherRoom {
  const _TeacherRoom({
    required this.code,
    required this.status,
    required this.unit,
    required this.durationSeconds,
    required this.wordCount,
    required this.participants,
  });
  factory _TeacherRoom.fromRow(Map<String, dynamic> row) => _TeacherRoom(
    code: row['code']?.toString() ?? '',
    status: row['status']?.toString() ?? 'waiting',
    unit: row['unit']?.toString() ?? '',
    durationSeconds: (row['duration_seconds'] as num?)?.toInt() ?? 300,
    wordCount: (row['word_count'] as num?)?.toInt() ?? 0,
    participants: (row['participants'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => _Participant.fromRow(Map<String, dynamic>.from(item)))
        .toList(),
  );
  final String code;
  final String status;
  final String unit;
  final int durationSeconds;
  final int wordCount;
  final List<_Participant> participants;
}

class _Participant {
  const _Participant({
    required this.name,
    required this.submitted,
    required this.correctCount,
    required this.score,
  });
  factory _Participant.fromRow(Map<String, dynamic> row) => _Participant(
    name: row['student_name']?.toString() ?? 'Μαθητής',
    submitted: row['submitted_at'] != null,
    correctCount: (row['correct_count'] as num?)?.toInt(),
    score: (row['score_percentage'] as num?)?.toDouble(),
  );
  final String name;
  final bool submitted;
  final int? correctCount;
  final double? score;
}

Color _rankingColor(int index) => switch (index) {
  0 => const Color(0xFFD4A017),
  1 => const Color(0xFF8A929A),
  2 => const Color(0xFFB87333),
  _ => const Color(0xFF4D4AAD),
};

String? _positiveInteger(String? value) {
  final parsed = int.tryParse(value ?? '');
  return parsed == null || parsed < 1 || parsed > 100
      ? 'Δώσε αριθμό από 1 έως 100'
      : null;
}
