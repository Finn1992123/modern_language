import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class JoinRoomPage extends StatefulWidget {
  const JoinRoomPage({
    super.key,
    required this.studentId,
    required this.classId,
  });

  final String studentId;
  final String classId;

  @override
  State<JoinRoomPage> createState() => _JoinRoomPageState();
}

class _JoinRoomPageState extends State<JoinRoomPage> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _joining = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _joining = true);
    try {
      final response = await Supabase.instance.client.rpc(
        'join_live_activity_room',
        params: {
          'input_code': _codeController.text.trim().toUpperCase(),
          'input_student_id': widget.studentId,
          'input_class_id': widget.classId,
        },
      );
      if (!mounted || response is! Map) return;
      final data = Map<String, dynamic>.from(response);
      final activityType = data['activity_type']?.toString();
      if (activityType != 'dictation') {
        throw StateError('Αυτός ο τύπος δωματίου δεν υποστηρίζεται ακόμη.');
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => StudentDictationRoomPage(
            participantId: data['participant_id'].toString(),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final text = error.toString().toLowerCase();
      final message = text.contains('room not found')
          ? 'Δεν βρέθηκε δωμάτιο με αυτόν τον κωδικό.'
          : text.contains('another class')
          ? 'Το δωμάτιο ανήκει σε άλλο τμήμα.'
          : text.contains('not accepting')
          ? 'Η δραστηριότητα έχει ολοκληρωθεί ή ο χρόνος έχει λήξει.'
          : 'Δεν ήταν δυνατή η συμμετοχή: $error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FF),
      appBar: AppBar(
        title: const Text(
          'Συμμετοχή σε δωμάτιο',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF4D4AAD),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.meeting_room_rounded,
                        color: Color(0xFF18A8EF),
                        size: 74,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Βάλε τον κωδικό που δείχνει ο καθηγητής',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _codeController,
                        autofocus: true,
                        textCapitalization: TextCapitalization.characters,
                        textAlign: TextAlign.center,
                        maxLength: 6,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp('[a-zA-Z2-9]'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Κωδικός δωματίου',
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                        validator: (value) =>
                            value == null || value.trim().length != 6
                            ? 'Ο κωδικός έχει 6 χαρακτήρες'
                            : null,
                        onFieldSubmitted: (_) => _join(),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _joining ? null : _join,
                        icon: _joining
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login_rounded),
                        label: const Text('Συμμετοχή'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF4D4AAD),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StudentDictationRoomPage extends StatefulWidget {
  const StudentDictationRoomPage({super.key, required this.participantId});
  final String participantId;

  @override
  State<StudentDictationRoomPage> createState() =>
      _StudentDictationRoomPageState();
}

class _StudentDictationRoomPageState extends State<StudentDictationRoomPage> {
  final Map<int, TextEditingController> _controllers = {};
  Timer? _timer;
  _StudentRoom? _room;
  bool _loading = true;
  bool _refreshing = false;
  bool _submitting = false;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
      _refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing || _submitting) return;
    _refreshing = true;
    try {
      final response = await Supabase.instance.client.rpc(
        'get_student_live_activity_room',
        params: {'input_participant_id': widget.participantId},
      );
      if (!mounted || response is! Map) return;
      final room = _StudentRoom.fromRow(Map<String, dynamic>.from(response));
      for (final word in room.words) {
        _controllers.putIfAbsent(word.position, TextEditingController.new);
      }
      setState(() {
        _room = room;
        _loading = false;
      });
      _updateRemaining();
      if (room.status == 'finished' &&
          !room.submitted &&
          room.words.isNotEmpty) {
        await _submit(automatic: true);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    } finally {
      _refreshing = false;
    }
  }

  void _updateRemaining() {
    final room = _room;
    final startedAt = room?.startedAt;
    if (room == null || startedAt == null || room.submitted) {
      return;
    }
    final end = startedAt.add(Duration(seconds: room.durationSeconds));
    final remaining = end.difference(DateTime.now().toUtc()).inSeconds;
    if (mounted) {
      setState(
        () => _remainingSeconds = remaining.clamp(0, room.durationSeconds),
      );
    }
    if (remaining <= 0 && room.words.isNotEmpty && !_submitting) {
      _submit(automatic: true);
    }
  }

  Future<void> _submit({bool automatic = false}) async {
    final room = _room;
    if (room == null || room.submitted || _submitting) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final response = await Supabase.instance.client.rpc(
        'submit_live_dictation_answers',
        params: {
          'input_participant_id': widget.participantId,
          'input_answers': [
            for (final word in room.words)
              {
                'position': word.position,
                'answer': _controllers[word.position]?.text.trim() ?? '',
              },
          ],
        },
      );
      if (!mounted) return;
      if (response is Map) {
        final result = Map<String, dynamic>.from(response);
        setState(
          () => _room = room.withResult(
            correctCount: (result['correct_count'] as num?)?.toInt() ?? 0,
            score: (result['score_percentage'] as num?)?.toDouble() ?? 0,
            words: (result['words'] as List? ?? const [])
                .whereType<Map>()
                .map(
                  (item) =>
                      _DictationWord.fromRow(Map<String, dynamic>.from(item)),
                )
                .toList(),
          ),
        );
      } else {
        await _refresh();
      }
      if (automatic && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ο χρόνος έληξε και οι απαντήσεις υποβλήθηκαν.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Οι απαντήσεις δεν υποβλήθηκαν: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    return PopScope(
      canPop: room?.status == 'waiting' || room?.submitted == true,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FF),
        appBar: AppBar(
          automaticallyImplyLeading:
              room?.status == 'waiting' || room?.submitted == true,
          title: const Text(
            'Live ορθογραφία',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          backgroundColor: Colors.white,
        ),
        body: _loading && room == null
            ? const Center(child: CircularProgressIndicator())
            : room == null
            ? const Center(child: Text('Δεν φορτώθηκε το δωμάτιο.'))
            : room.submitted
            ? _ResultView(room: room)
            : room.status == 'waiting'
            ? _WaitingView(code: room.code)
            : _buildActivity(room),
      ),
    );
  }

  Widget _buildActivity(_StudentRoom room) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: _remainingSeconds <= 60
              ? const Color(0xFFE05252)
              : const Color(0xFF4D4AAD),
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Text(
            _formatDuration(_remainingSeconds),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 100),
            itemCount: room.words.length,
            itemBuilder: (context, index) {
              final word = room.words[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${word.position}.  ${word.prompt}',
                        style: const TextStyle(
                          color: Color(0xFF173A8A),
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _controllers[word.position],
                        enabled: !_submitting,
                        autocorrect: false,
                        enableSuggestions: false,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Γράψε τη λέξη στα ελληνικά',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submitting ? null : () => _submit(),
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: const Text('Υποβολή απαντήσεων'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF18A8EF),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WaitingView extends StatelessWidget {
  const _WaitingView({required this.code});
  final String code;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 58,
            child: CircularProgressIndicator(strokeWidth: 6),
          ),
          const SizedBox(height: 24),
          const Text(
            'Συνδέθηκες!',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Δωμάτιο $code',
            style: const TextStyle(
              color: Color(0xFF4D4AAD),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Περίμενε τον καθηγητή να πατήσει Έναρξη.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ],
      ),
    ),
  );
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.room});
  final _StudentRoom room;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.emoji_events_rounded,
            color: Color(0xFFFFB300),
            size: 92,
          ),
          const SizedBox(height: 16),
          const Text(
            'Ολοκλήρωσες την ορθογραφία!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 20),
          Text(
            '${room.correctCount ?? 0} / ${room.words.length}',
            style: const TextStyle(
              color: Color(0xFF4D4AAD),
              fontSize: 42,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            '${room.score?.toStringAsFixed(0) ?? '0'}%',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 24),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Αναλυτική διόρθωση',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 10),
          for (final word in room.words) ...[
            _AnswerReviewCard(word: word),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Επιστροφή'),
          ),
        ],
      ),
    ),
  );
}

class _StudentRoom {
  const _StudentRoom({
    required this.code,
    required this.status,
    required this.durationSeconds,
    required this.startedAt,
    required this.submitted,
    required this.correctCount,
    required this.score,
    required this.words,
  });
  factory _StudentRoom.fromRow(Map<String, dynamic> row) => _StudentRoom(
    code: row['code']?.toString() ?? '',
    status: row['status']?.toString() ?? 'waiting',
    durationSeconds: (row['duration_seconds'] as num?)?.toInt() ?? 300,
    startedAt: DateTime.tryParse(row['started_at']?.toString() ?? '')?.toUtc(),
    submitted: row['submitted_at'] != null,
    correctCount: (row['correct_count'] as num?)?.toInt(),
    score: (row['score_percentage'] as num?)?.toDouble(),
    words: (row['words'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => _DictationWord.fromRow(Map<String, dynamic>.from(item)))
        .toList(),
  );
  final String code;
  final String status;
  final int durationSeconds;
  final DateTime? startedAt;
  final bool submitted;
  final int? correctCount;
  final double? score;
  final List<_DictationWord> words;
  _StudentRoom withResult({
    required int correctCount,
    required double score,
    required List<_DictationWord> words,
  }) => _StudentRoom(
    code: code,
    status: 'finished',
    durationSeconds: durationSeconds,
    startedAt: startedAt,
    submitted: true,
    correctCount: correctCount,
    score: score,
    words: words.isEmpty ? this.words : words,
  );
}

class _DictationWord {
  const _DictationWord({
    required this.position,
    required this.prompt,
    required this.answer,
    required this.correctAnswer,
    required this.isCorrect,
  });
  factory _DictationWord.fromRow(Map<String, dynamic> row) => _DictationWord(
    position: (row['position'] as num?)?.toInt() ?? 0,
    prompt: row['prompt']?.toString() ?? '',
    answer: row['answer']?.toString(),
    correctAnswer: row['correct_answer']?.toString(),
    isCorrect: row['is_correct'] as bool?,
  );
  final int position;
  final String prompt;
  final String? answer;
  final String? correctAnswer;
  final bool? isCorrect;
}

class _AnswerReviewCard extends StatelessWidget {
  const _AnswerReviewCard({required this.word});

  final _DictationWord word;

  @override
  Widget build(BuildContext context) {
    final correct = word.isCorrect == true;
    final answer = word.answer?.trim() ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: correct ? const Color(0xFFEAF8EC) : const Color(0xFFFFEEEE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: correct ? const Color(0xFF56A85C) : const Color(0xFFE05252),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: correct
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFFC62828),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${word.position}. ${word.prompt}',
                  style: const TextStyle(
                    color: Color(0xFF173A8A),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Η απάντησή σου: ${answer.isEmpty ? 'Δεν δόθηκε απάντηση' : answer}',
            style: TextStyle(
              color: correct
                  ? const Color(0xFF2E7D32)
                  : const Color(0xFFC62828),
              fontWeight: FontWeight.w800,
            ),
          ),
          if (!correct) ...[
            const SizedBox(height: 5),
            Text(
              'Σωστή απάντηση: ${word.correctAnswer ?? '—'}',
              style: const TextStyle(
                color: Color(0xFF2E7D32),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
}
