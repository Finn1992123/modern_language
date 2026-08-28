import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeacherAnnouncementsPage extends StatefulWidget {
  const TeacherAnnouncementsPage({super.key, required this.role});

  final String? role;

  @override
  State<TeacherAnnouncementsPage> createState() =>
      _TeacherAnnouncementsPageState();
}

class _TeacherAnnouncementsPageState extends State<TeacherAnnouncementsPage> {
  static const _green = Color(0xFF2D7D10);

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _textController = TextEditingController();

  List<_AnnouncementClass> _classes = const [];
  _AnnouncementClass? _selectedClass;
  bool _sendToEveryone = true;
  bool _isLoading = true;
  bool _isPublishing = false;
  String? _loadError;

  bool get _isHeadteacher => widget.role == 'headteacher';

  @override
  void initState() {
    super.initState();
    _sendToEveryone = _isHeadteacher;
    _loadClasses();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    try {
      final response = await Supabase.instance.client.rpc(
        'get_announcement_target_classes',
      );
      final classes = response is List
          ? response
                .whereType<Map>()
                .map(
                  (row) => _AnnouncementClass.fromRow(
                    Map<String, dynamic>.from(row),
                  ),
                )
                .where((item) => item.id.isNotEmpty)
                .toList()
          : <_AnnouncementClass>[];

      if (!mounted) return;

      setState(() {
        _classes = classes;
        _selectedClass = classes.length == 1 ? classes.first : null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Δεν μπορέσαμε να φορτώσουμε τις τάξεις.';
        _isLoading = false;
      });
    }
  }

  Future<void> _publish() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (!_sendToEveryone && _selectedClass == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Επίλεξε την τάξη των παραληπτών.')),
      );
      return;
    }

    setState(() => _isPublishing = true);

    try {
      final notificationId = await Supabase.instance.client.rpc(
        'create_announcement',
        params: {
          'input_header': _titleController.text.trim(),
          'input_text': _textController.text.trim(),
          'input_audience_type': _sendToEveryone ? 'all' : 'class',
          'input_class_id': _sendToEveryone ? null : _selectedClass!.id,
        },
      );

      var pushSent = true;
      try {
        await Supabase.instance.client.functions.invoke(
          'send-announcement-notification',
          body: {'notification_id': notificationId.toString()},
        );
      } catch (_) {
        pushSent = false;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pushSent
                ? 'Η ανακοίνωση δημοσιεύτηκε και η ειδοποίηση στάλθηκε.'
                : 'Η ανακοίνωση δημοσιεύτηκε, αλλά δεν στάλθηκε push ειδοποίηση.',
          ),
          backgroundColor: pushSent ? _green : Colors.orange.shade800,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isPublishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Δεν μπορέσαμε να δημοσιεύσουμε την ανακοίνωση.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF6),
      appBar: AppBar(
        title: const Text('Νέα ανακοίνωση'),
        backgroundColor: Colors.white,
        foregroundColor: _green,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? _ErrorState(message: _loadError!, onRetry: _loadClasses)
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
                children: [
                  const Text(
                    'Παραλήπτες',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  if (_isHeadteacher)
                    _AudienceCard(
                      title: 'Όλοι',
                      subtitle: 'Όλοι οι χρήστες της εφαρμογής',
                      icon: Icons.public_rounded,
                      selected: _sendToEveryone,
                      onTap: () => setState(() => _sendToEveryone = true),
                    ),
                  if (_isHeadteacher) const SizedBox(height: 10),
                  _AudienceCard(
                    title: 'Συγκεκριμένη τάξη',
                    subtitle: 'Μόνο οι μαθητές της τάξης που θα επιλέξεις',
                    icon: Icons.school_rounded,
                    selected: !_sendToEveryone,
                    onTap: () => setState(() => _sendToEveryone = false),
                  ),
                  if (!_sendToEveryone) ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<_AnnouncementClass>(
                      initialValue: _selectedClass,
                      decoration: const InputDecoration(
                        labelText: 'Τάξη',
                        prefixIcon: Icon(Icons.groups_rounded),
                        border: OutlineInputBorder(),
                      ),
                      items: _classes
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _selectedClass = value),
                      validator: (value) => !_sendToEveryone && value == null
                          ? 'Επίλεξε τάξη'
                          : null,
                    ),
                    if (_classes.isEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Δεν υπάρχουν διαθέσιμες τάξεις.',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ],
                  ],
                  const SizedBox(height: 26),
                  TextFormField(
                    controller: _titleController,
                    maxLength: 120,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Τίτλος',
                      prefixIcon: Icon(Icons.title_rounded),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Γράψε έναν τίτλο'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _textController,
                    minLines: 6,
                    maxLines: 12,
                    maxLength: 4000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Κείμενο ανακοίνωσης',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Γράψε το κείμενο της ανακοίνωσης'
                        : null,
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _isPublishing ? null : _publish,
                    icon: _isPublishing
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(_isPublishing ? 'Δημοσίευση...' : 'Δημοσίευση'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _AudienceCard extends StatelessWidget {
  const _AudienceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFEAFBE5) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? _TeacherAnnouncementsPageState._green
                  : const Color(0xFFDDE3DD),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: _TeacherAnnouncementsPageState._green,
                size: 30,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected
                    ? _TeacherAnnouncementsPageState._green
                    : Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Δοκιμή ξανά')),
        ],
      ),
    );
  }
}

class _AnnouncementClass {
  const _AnnouncementClass({
    required this.id,
    required this.name,
    required this.language,
    required this.daysHours,
  });

  factory _AnnouncementClass.fromRow(Map<String, dynamic> row) {
    return _AnnouncementClass(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString().trim() ?? '',
      language: row['language']?.toString().trim() ?? '',
      daysHours: row['days_hours']?.toString().trim() ?? '',
    );
  }

  final String id;
  final String name;
  final String language;
  final String daysHours;

  String get label {
    final details = [language, daysHours].where((value) => value.isNotEmpty);
    return details.isEmpty ? name : '$name · ${details.join(' · ')}';
  }
}
