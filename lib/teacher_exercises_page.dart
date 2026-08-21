import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeacherExercisesPage extends StatefulWidget {
  const TeacherExercisesPage({super.key});

  @override
  State<TeacherExercisesPage> createState() => _TeacherExercisesPageState();
}

class _TeacherExercisesPageState extends State<TeacherExercisesPage> {
  static const _purple = Color(0xFF4D4AAD);
  static const _blue = Color(0xFF18A8EF);

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _requiredCountController = TextEditingController(text: '3');
  final _attemptsController = TextEditingController(text: '3');

  late Future<List<_TeacherClass>> _classesFuture = _loadClasses();
  late final Future<List<_GrammarTopicOption>> _grammarTopicsFuture =
      _loadGrammarTopics();
  List<_VocabularyUnit> _units = const [];
  _TeacherClass? _selectedClass;
  _VocabularyUnit? _selectedUnit;
  _ActivityType _activity = _ActivityType.reader;
  String _readerLevel = 'junior_a';
  String _vocabularyMode = 'multiple_choice';
  bool _importantOnly = false;
  bool _personalWords = false;
  bool _unlimitedAttempts = true;
  bool _noDueDate = true;
  DateTime? _dueDate;
  bool _loadingUnits = false;
  bool _submitting = false;
  String _standardLimitType = 'questions';
  final Set<String> _selectedGrammarTopics = {};

  @override
  void dispose() {
    _titleController.dispose();
    _instructionsController.dispose();
    _requiredCountController.dispose();
    _attemptsController.dispose();
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

  Future<List<_GrammarTopicOption>> _loadGrammarTopics() async {
    final rows = await Supabase.instance.client
        .from('study_gram_topics')
        .select('slug, title, sort_order')
        .eq('is_active', true)
        .order('sort_order');
    return rows
        .map(_GrammarTopicOption.fromRow)
        .where((topic) => topic.slug.isNotEmpty)
        .toList();
  }

  Future<void> _selectClass(_TeacherClass? teacherClass) async {
    setState(() {
      _selectedClass = teacherClass;
      _selectedUnit = null;
      _units = const [];
      _loadingUnits = teacherClass != null;
    });
    if (teacherClass == null) return;
    try {
      final rows = await Supabase.instance.client.rpc(
        'get_teacher_assignment_vocabulary_units',
        params: {'input_class_id': teacherClass.id},
      );
      if (!mounted || _selectedClass?.id != teacherClass.id) return;
      setState(() {
        _units = rows is List
            ? rows
                  .whereType<Map>()
                  .map(
                    (row) =>
                        _VocabularyUnit.fromRow(Map<String, dynamic>.from(row)),
                  )
                  .where((item) => item.unit.isNotEmpty)
                  .toList()
            : const [];
        _loadingUnits = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingUnits = false);
      _showMessage('Δεν φορτώθηκαν οι ενότητες του τμήματος.');
    }
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(
      () => _dueDate = DateTime(picked.year, picked.month, picked.day, 23, 59),
    );
  }

  void _changeActivity(_ActivityType? value) {
    if (value == null) return;
    setState(() {
      _activity = value;
      _selectedUnit = null;
      _personalWords = false;
      _requiredCountController.text = switch (value) {
        _ActivityType.reader => '3',
        _ActivityType.vocabulary => '1',
        _ActivityType.hangman => '5',
        _ActivityType.identifyTense => '20',
        _ActivityType.studyGrammar => '20',
      };
      _titleController.text = value.label;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final teacherClass = _selectedClass;
    if (teacherClass == null) {
      _showMessage('Επίλεξε τμήμα.');
      return;
    }
    if ((_activity == _ActivityType.vocabulary ||
            _activity == _ActivityType.hangman) &&
        !_personalWords &&
        _selectedUnit == null) {
      _showMessage('Επίλεξε ενότητα.');
      return;
    }

    final enteredCount = int.parse(_requiredCountController.text);
    final standardActivity =
        _activity == _ActivityType.identifyTense ||
        _activity == _ActivityType.studyGrammar;
    final requiredCount = standardActivity && _standardLimitType == 'time'
        ? enteredCount * 60
        : enteredCount;
    final maxAttempts = _unlimitedAttempts
        ? null
        : int.parse(_attemptsController.text);
    final unit = _selectedUnit;
    final settings = <String, dynamic>{
      'required_count': requiredCount,
      if (_activity == _ActivityType.reader) 'level': _readerLevel,
      if (unit != null) ...{
        'unit': unit.unit,
        'unit_order': unit.unitOrder,
        'level': unit.level,
      },
      if (_activity == _ActivityType.vocabulary) ...{
        'mode': _vocabularyMode,
        'important_only': _importantOnly,
      },
      if (_activity == _ActivityType.vocabulary ||
          _activity == _ActivityType.hangman) ...{
        'personal_words': _personalWords,
      },
      if (standardActivity) ...{
        'limit_type': _standardLimitType,
        'topic_slugs': _selectedGrammarTopics.toList(),
      },
    };

    setState(() => _submitting = true);
    try {
      await Supabase.instance.client.rpc(
        'create_exercise_assignment',
        params: {
          'input_class_ids': [teacherClass.id],
          'input_activity_type': _activity.databaseValue,
          'input_title': _titleController.text.trim(),
          'input_instructions': _instructionsController.text.trim(),
          'input_available_from': DateTime.now().toUtc().toIso8601String(),
          'input_due_at': _noDueDate
              ? null
              : _dueDate?.toUtc().toIso8601String(),
          'input_max_attempts': maxAttempts,
          'input_settings': settings,
        },
      );
      if (!mounted) return;
      _showMessage('Η άσκηση ανατέθηκε στο τμήμα ${teacherClass.title}.');
      _formKey.currentState!.reset();
      setState(() {
        _titleController.clear();
        _instructionsController.clear();
        _selectedUnit = null;
        _personalWords = false;
        _selectedGrammarTopics.clear();
        _unlimitedAttempts = true;
        _noDueDate = true;
        _dueDate = null;
      });
    } catch (error) {
      if (!mounted) return;
      _showMessage('Η ανάθεση δεν αποθηκεύτηκε: $error');
    } finally {
      if (mounted) setState(() => _submitting = false);
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
      backgroundColor: const Color(0xFFF7F8FF),
      appBar: AppBar(
        title: const Text(
          'Δημιουργία άσκησης',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.white,
        foregroundColor: _purple,
      ),
      body: FutureBuilder<List<_TeacherClass>>(
        future: _classesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(
              onRetry: () {
                setState(() {
                  _classesFuture = _loadClasses();
                });
              },
            );
          }
          final classes = snapshot.data ?? const [];
          if (classes.isEmpty) {
            return const Center(
              child: Text('Δεν υπάρχουν τμήματα για ανάθεση.'),
            );
          }
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _SectionCard(
                  title: 'Τμήμα και δραστηριότητα',
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _selectClass,
                      validator: (value) =>
                          value == null ? 'Επίλεξε τμήμα' : null,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<_ActivityType>(
                      initialValue: _activity,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Δραστηριότητα',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final item in _ActivityType.values)
                          DropdownMenuItem(
                            value: item,
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _changeActivity,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Ρυθμίσεις',
                  children: _buildActivitySettings(),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Ανάθεση',
                  children: [
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Τίτλος',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Γράψε έναν τίτλο'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _instructionsController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Οδηγίες (προαιρετικά)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Χωρίς ημερομηνία λήξης'),
                      value: _noDueDate,
                      onChanged: (value) => setState(() {
                        _noDueDate = value;
                        if (!value && _dueDate == null) {
                          _dueDate = DateTime.now().add(
                            const Duration(days: 7),
                          );
                        }
                      }),
                    ),
                    if (!_noDueDate)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_rounded),
                        title: Text(
                          _dueDate == null
                              ? 'Επίλεξε ημερομηνία'
                              : '${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _pickDueDate,
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Απεριόριστες προσπάθειες'),
                      value: _unlimitedAttempts,
                      onChanged: (value) =>
                          setState(() => _unlimitedAttempts = value),
                    ),
                    if (!_unlimitedAttempts)
                      TextFormField(
                        controller: _attemptsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Μέγιστες προσπάθειες',
                          border: OutlineInputBorder(),
                        ),
                        validator: _positiveIntegerValidator,
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: const Text('Ανάθεση στο τμήμα'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    minimumSize: const Size.fromHeight(56),
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

  List<Widget> _buildActivitySettings() {
    if (_activity == _ActivityType.reader) {
      return [
        DropdownButtonFormField<String>(
          initialValue: _readerLevel,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Επίπεδο κειμένων',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final item in _readerLevels.entries)
              DropdownMenuItem(
                value: item.key,
                child: Text(
                  item.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _readerLevel = value);
          },
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _requiredCountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Πόσα κείμενα',
            border: OutlineInputBorder(),
          ),
          validator: _positiveIntegerValidator,
        ),
      ];
    }

    if (_activity == _ActivityType.identifyTense ||
        _activity == _ActivityType.studyGrammar) {
      return [
        DropdownButtonFormField<String>(
          initialValue: _standardLimitType,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Τρόπος ολοκλήρωσης',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: 'questions',
              child: Text(
                'Αριθμός ερωτήσεων',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: 'time',
              child: Text(
                'Χρόνος',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _standardLimitType = value;
              _requiredCountController.text = value == 'time' ? '5' : '20';
            });
          },
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _requiredCountController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: _standardLimitType == 'time'
                ? 'Διάρκεια σε λεπτά'
                : 'Πόσες ερωτήσεις',
            border: const OutlineInputBorder(),
          ),
          validator: _positiveIntegerValidator,
        ),
        const SizedBox(height: 8),
        const Text(
          'Για ολοκλήρωση απαιτείται βαθμολογία τουλάχιστον 71%.',
          style: TextStyle(
            color: Color(0xFF625F7E),
            fontWeight: FontWeight.w700,
          ),
        ),
        if (_activity == _ActivityType.studyGrammar) ...[
          const SizedBox(height: 18),
          const Text(
            'Γραμματικά φαινόμενα',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<_GrammarTopicOption>>(
            future: _grammarTopicsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final topics = snapshot.data ?? const [];
              return FormField<Set<String>>(
                initialValue: _selectedGrammarTopics,
                validator: (_) => _selectedGrammarTopics.isEmpty
                    ? 'Επίλεξε τουλάχιστον ένα φαινόμενο'
                    : null,
                builder: (field) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final topic in topics)
                          FilterChip(
                            label: Text(topic.title),
                            selected: _selectedGrammarTopics.contains(
                              topic.slug,
                            ),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedGrammarTopics.add(topic.slug);
                                } else {
                                  _selectedGrammarTopics.remove(topic.slug);
                                }
                              });
                              field.didChange(_selectedGrammarTopics);
                            },
                          ),
                      ],
                    ),
                    if (field.hasError) ...[
                      const SizedBox(height: 6),
                      Text(
                        field.errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ];
    }

    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Προσωπικές λέξεις'),
        subtitle: const Text(
          'Κάθε μαθητής θα πάρει λέξεις από τη δική του λίστα λαθών.',
        ),
        value: _personalWords,
        onChanged: (value) {
          setState(() {
            _personalWords = value;
            _selectedUnit = null;
            _importantOnly = false;
            _requiredCountController.text = value
                ? '10'
                : (_activity == _ActivityType.hangman ? '5' : '1');
            if (value && _vocabularyMode == 'speaking') {
              _vocabularyMode = 'multiple_choice';
            }
          });
        },
      ),
      if (_personalWords) ...[
        const SizedBox(height: 8),
        TextFormField(
          controller: _requiredCountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Μέγιστος αριθμός προσωπικών λέξεων',
            helperText:
                'Αν ένας μαθητής έχει λιγότερες, θα πάρει όσες διαθέτει.',
            border: OutlineInputBorder(),
          ),
          validator: _positiveIntegerValidator,
        ),
        const SizedBox(height: 14),
      ],
      if (_loadingUnits && !_personalWords)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (!_personalWords)
        DropdownButtonFormField<_VocabularyUnit>(
          initialValue: _selectedUnit,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Ενότητα και επίπεδο',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final item in _units)
              DropdownMenuItem(
                value: item,
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) => setState(() => _selectedUnit = value),
          validator: (value) => value == null ? 'Επίλεξε ενότητα' : null,
        ),
      if (_activity == _ActivityType.vocabulary) ...[
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _vocabularyMode,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Είδος εξάσκησης',
            border: OutlineInputBorder(),
          ),
          items: [
            if (!_personalWords)
              const DropdownMenuItem(
                value: 'speaking',
                child: Text(
                  'Προφορά λέξεων',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const DropdownMenuItem(
              value: 'multiple_choice',
              child: Text(
                'Πολλαπλής επιλογής',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: 'write_foreign',
              child: Text(
                'Ελληνικά → ξένη γλώσσα',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: 'write_greek',
              child: Text(
                'Ξένη γλώσσα → ελληνικά',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _vocabularyMode = value);
          },
        ),
        if (!_personalWords)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Μόνο σημαντικές λέξεις'),
            subtitle: const Text('Απαιτείται βαθμολογία τουλάχιστον 71%'),
            value: _importantOnly,
            onChanged: (value) => setState(() => _importantOnly = value),
          ),
      ] else if (!_personalWords) ...[
        const SizedBox(height: 14),
        TextFormField(
          controller: _requiredCountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Πόσες λέξεις πρέπει να βρει',
            border: OutlineInputBorder(),
          ),
          validator: _positiveIntegerValidator,
        ),
      ],
    ];
  }
}

String? _positiveIntegerValidator(String? value) {
  final parsed = int.tryParse(value ?? '');
  return parsed == null || parsed < 1 ? 'Δώσε θετικό αριθμό' : null;
}

enum _ActivityType {
  reader('reader', 'Reader'),
  vocabulary('vocabulary', 'Study your voc'),
  hangman('hangman', 'Hangman'),
  identifyTense('identify_tense', 'Identify the tense'),
  studyGrammar('study_grammar', 'Study your gram');

  const _ActivityType(this.databaseValue, this.label);
  final String databaseValue;
  final String label;
}

class _GrammarTopicOption {
  const _GrammarTopicOption({required this.slug, required this.title});

  factory _GrammarTopicOption.fromRow(Map<String, dynamic> row) =>
      _GrammarTopicOption(
        slug: row['slug']?.toString() ?? '',
        title: row['title']?.toString() ?? '',
      );

  final String slug;
  final String title;
}

const _readerLevels = <String, String>{
  'junior_a': 'Junior A',
  'junior_b': 'Junior B',
  'senior_a': 'Senior A',
  'senior_b': 'Senior B',
  'senior_c': 'Senior C',
  'senior_d': 'Senior D',
  'pre_lower': 'Pre-Lower',
  'lower': 'Lower',
  'advanced': 'Advanced',
  'proficiency': 'Proficiency',
};

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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x124D4AAD),
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
              color: _TeacherExercisesPageState._purple,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 15),
          ...children,
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Δοκιμή ξανά'),
      ),
    );
  }
}
