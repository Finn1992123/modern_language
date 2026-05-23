import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MyGradesPage extends StatefulWidget {
  const MyGradesPage({
    super.key,
    required this.studentId,
    required this.classId,
    required this.languageLabel,
  });

  final String studentId;
  final String classId;
  final String languageLabel;

  @override
  State<MyGradesPage> createState() => _MyGradesPageState();
}

class _MyGradesPageState extends State<MyGradesPage> {
  static const Color _headerColor = Color(0x9682FE63);
  static const Color _contentColor = Color(0xFF2D7D10);
  static const int _pageSize = 10;

  final List<_StudentGradeRow> _grades = [];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadNextGradesPage(isInitialLoad: true);
  }

  Future<void> _loadNextGradesPage({bool isInitialLoad = false}) async {
    if (_isLoadingMore || (!_hasMore && !isInitialLoad)) {
      return;
    }

    if (widget.studentId.isEmpty || widget.classId.isEmpty) {
      setState(() {
        _isInitialLoading = false;
        _hasMore = false;
      });
      return;
    }

    setState(() {
      _loadError = null;
      if (isInitialLoad) {
        _isInitialLoading = true;
      } else {
        _isLoadingMore = true;
      }
    });

    try {
      final rows = await Supabase.instance.client.rpc(
        'get_student_grade_rows',
        params: {
          'input_student_id': widget.studentId,
          'input_class_id': widget.classId,
          'input_limit': _pageSize,
          'input_offset': isInitialLoad ? 0 : _grades.length,
        },
      );

      final nextGrades = rows is List
          ? rows
                .whereType<Map>()
                .map(
                  (row) =>
                      _StudentGradeRow.fromRow(Map<String, dynamic>.from(row)),
                )
                .toList()
          : <_StudentGradeRow>[];

      if (!mounted) {
        return;
      }

      setState(() {
        if (isInitialLoad) {
          _grades
            ..clear()
            ..addAll(nextGrades);
        } else {
          _grades.addAll(nextGrades);
        }

        _hasMore = nextGrades.length == _pageSize;
        _isInitialLoading = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadError = 'Δεν μπορέσαμε να φορτώσουμε τους βαθμούς.';
        _isInitialLoading = false;
        _isLoadingMore = false;
      });
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
            height: 245,
            decoration: const BoxDecoration(
              color: _headerColor,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(48),
                bottomRight: Radius.circular(48),
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
                          'Οι βαθμοί μου',
                          style: TextStyle(
                            color: _contentColor,
                            fontSize: 31,
                            fontWeight: FontWeight.w800,
                            height: 1.08,
                          ),
                        ),
                        SizedBox(height: 12),
                        Icon(
                          Icons.text_increase_rounded,
                          color: _contentColor,
                          size: 82,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null && _grades.isEmpty) {
      return _GradesMessage(text: _loadError!, color: Colors.grey.shade700);
    }

    if (_grades.isEmpty) {
      return _GradesMessage(
        text: 'Δεν υπάρχουν βαθμοί για αυτό το μάθημα.',
        color: Colors.grey.shade600,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 30),
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            const Positioned(left: 16, child: _GradeLegendButton()),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  _languageFlagAsset(widget.languageLabel),
                  width: 30,
                  height: 30,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 10),
                Text(
                  widget.languageLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF173A8A),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _GradesTable(grades: _grades),
        if (_loadError != null) ...[
          const SizedBox(height: 12),
          _GradesMessage(text: _loadError!, color: Colors.grey.shade700),
        ],
        if (_hasMore) ...[
          const SizedBox(height: 16),
          Center(
            child: _LoadMoreGradesButton(
              isLoading: _isLoadingMore,
              onTap: () => _loadNextGradesPage(),
            ),
          ),
        ],
      ],
    );
  }
}

class _GradeLegendButton extends StatelessWidget {
  const _GradeLegendButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey.shade100,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () => _showLegend(context),
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            Icons.question_mark_rounded,
            color: Colors.grey.shade500,
            size: 20,
          ),
        ),
      ),
    );
  }

  void _showLegend(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(18),
                    child: const SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(
                        Icons.close_rounded,
                        color: Color(0xFF9AA0A9),
                        size: 24,
                      ),
                    ),
                  ),
                ),
                Text(
                  'Επεξήγηση βαθμών',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _MyGradesPageState._contentColor,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 16),
                const _LegendRow('Ημ/νία', 'Ημερομηνία που μπήκε ο βαθμός'),
                const _LegendRow('R', 'Ανάγνωση και κατανόηση'),
                const _LegendRow('V', 'Λεξιλόγιο'),
                const _LegendRow('G', 'Γραμματική'),
                const _LegendRow('W', 'Γραπτός λόγος'),
                const _LegendRow('L', 'Ακουστική κατανόηση'),
                const _LegendRow('S', 'Προφορικός λόγος'),
                const _LegendRow('H', 'Καθήκοντα'),
                const _LegendRow('E', 'Προσπάθεια'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow(this.abbreviation, this.description);

  final String abbreviation;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Text(
              abbreviation,
              style: const TextStyle(
                color: _MyGradesPageState._contentColor,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(
                color: Color(0xFF313A2E),
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GradesTable extends StatelessWidget {
  const _GradesTable({required this.grades});

  final List<_StudentGradeRow> grades;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE3EADF)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildGradeTable(
              _buildRow(const [
                'Ημ/νία',
                'R',
                'V',
                'G',
                'W',
                'L',
                'S',
                'H',
                'E',
              ], isHeader: true),
            ),
            for (final grade in grades)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildGradeTable(
                      _buildRow([
                        grade.formattedDate,
                        _formatGrade(grade.reading),
                        _formatGrade(grade.vocabulary),
                        _formatGrade(grade.grammar),
                        _formatGrade(grade.writing),
                        _formatGrade(grade.listening),
                        _formatGrade(grade.speaking),
                        _formatGrade(grade.homework),
                        _formatGrade(grade.effort),
                      ]),
                    ),
                    if (grade.comments != null)
                      _buildCommentBox(grade.formattedDate, grade.comments!),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradeTable(TableRow row) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.8),
        1: FlexColumnWidth(0.82),
        2: FlexColumnWidth(0.82),
        3: FlexColumnWidth(0.82),
        4: FlexColumnWidth(0.82),
        5: FlexColumnWidth(0.82),
        6: FlexColumnWidth(0.82),
        7: FlexColumnWidth(0.82),
        8: FlexColumnWidth(0.82),
      },
      border: TableBorder(
        verticalInside: BorderSide(color: Colors.grey.shade200),
      ),
      children: [row],
    );
  }

  TableRow _buildRow(List<String> values, {bool isHeader = false}) {
    return TableRow(
      decoration: BoxDecoration(
        color: isHeader ? const Color(0xFFEAF9E6) : Colors.white,
      ),
      children: [
        for (final value in values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 11),
            child: Text(
              value,
              textAlign: TextAlign.center,
              maxLines: isHeader ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isHeader
                    ? _MyGradesPageState._contentColor
                    : const Color(0xFF313A2E),
                fontSize: isHeader ? 11 : 10.5,
                fontWeight: isHeader ? FontWeight.w900 : FontWeight.w700,
                height: 1.08,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCommentBox(String date, String comment) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFAFCF8),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 11),
      child: Text.rich(
        TextSpan(
          children: [
            const TextSpan(
              text: 'Σχόλια καθηγητή ',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            TextSpan(
              text: '($date): ',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            TextSpan(text: comment),
          ],
        ),
        style: const TextStyle(
          color: Color(0xFF313A2E),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.28,
        ),
      ),
    );
  }
}

class _GradesMessage extends StatelessWidget {
  const _GradesMessage({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _LoadMoreGradesButton extends StatelessWidget {
  const _LoadMoreGradesButton({required this.isLoading, required this.onTap});

  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x9682FE63),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: Color(0xFF2D7D10),
                    ),
                  )
                : const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF2D7D10),
                    size: 34,
                  ),
          ),
        ),
      ),
    );
  }
}

class _StudentGradeRow {
  const _StudentGradeRow({
    required this.createdAt,
    required this.reading,
    required this.vocabulary,
    required this.grammar,
    required this.writing,
    required this.listening,
    required this.speaking,
    required this.homework,
    required this.effort,
    required this.comments,
  });

  factory _StudentGradeRow.fromRow(Map<String, dynamic> row) {
    return _StudentGradeRow(
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
      reading: _readGrade(row['reading']),
      vocabulary: _readGrade(row['vocabulary']),
      grammar: _readGrade(row['grammar']),
      writing: _readGrade(row['writing']),
      listening: _readGrade(row['listening']),
      speaking: _readGrade(row['speaking']),
      homework: _readGrade(row['homework']),
      effort: _readGrade(row['effort']),
      comments: _readOptionalText(row['comments']),
    );
  }

  final DateTime? createdAt;
  final double? reading;
  final double? vocabulary;
  final double? grammar;
  final double? writing;
  final double? listening;
  final double? speaking;
  final double? homework;
  final double? effort;
  final String? comments;

  String get formattedDate {
    final date = createdAt;

    if (date == null) {
      return '-';
    }

    final year = (date.year % 100).toString().padLeft(2, '0');
    return '${date.day}/${date.month}/$year';
  }
}

double? _readGrade(Object? value) => value is num ? value.toDouble() : null;

String _formatGrade(double? value) {
  if (value == null) {
    return '-';
  }

  final rounded = value.roundToDouble();
  return value == rounded
      ? rounded.toInt().toString()
      : value.toStringAsFixed(1);
}

String? _readOptionalText(Object? value) {
  if (value is! String) {
    return null;
  }

  final text = value.trim();
  return text.isEmpty ? null : text;
}

String _languageFlagAsset(String languageLabel) {
  switch (languageLabel.trim().toLowerCase()) {
    case 'english':
      return 'lib/img/uk.png';
    case 'spanish':
      return 'lib/img/spanish.png';
    case 'french':
      return 'lib/img/french.png';
    case 'german':
      return 'lib/img/germany.png';
    default:
      return 'lib/img/uk.png';
  }
}
