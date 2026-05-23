import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MyHomeworkPage extends StatefulWidget {
  const MyHomeworkPage({
    super.key,
    required this.studentId,
    required this.classId,
    required this.languageLabel,
  });

  final String studentId;
  final String classId;
  final String languageLabel;

  @override
  State<MyHomeworkPage> createState() => _MyHomeworkPageState();
}

class _MyHomeworkPageState extends State<MyHomeworkPage> {
  static const Color _headerColor = Color(0xFF89ACFF);
  static const Color _contentColor = Color(0xFF385DC9);
  static const int _pageSize = 10;

  final List<_CurriculumRow> _rows = [];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadNextPage(isInitialLoad: true);
  }

  Future<void> _loadNextPage({bool isInitialLoad = false}) async {
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
        'get_student_curriculum_rows',
        params: {
          'input_student_id': widget.studentId,
          'input_class_id': widget.classId,
          'input_limit': _pageSize,
          'input_offset': isInitialLoad ? 0 : _rows.length,
        },
      );

      final nextRows = rows is List
          ? rows
                .whereType<Map>()
                .map(
                  (row) =>
                      _CurriculumRow.fromRow(Map<String, dynamic>.from(row)),
                )
                .toList()
          : <_CurriculumRow>[];

      if (!mounted) {
        return;
      }

      setState(() {
        if (isInitialLoad) {
          _rows
            ..clear()
            ..addAll(nextRows);
        } else {
          _rows.addAll(nextRows);
        }

        _hasMore = nextRows.length == _pageSize;
        _isInitialLoading = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadError = 'Δεν μπορέσαμε να φορτώσουμε τα καθήκοντα.';
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
                          'Τα καθήκοντα μου',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _contentColor,
                            fontSize: 31,
                            fontWeight: FontWeight.w800,
                            height: 1.08,
                          ),
                        ),
                        SizedBox(height: 12),
                        Icon(
                          Icons.edit_rounded,
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

    if (_loadError != null && _rows.isEmpty) {
      return _HomeworkMessage(text: _loadError!, color: Colors.grey.shade700);
    }

    if (_rows.isEmpty) {
      return _HomeworkMessage(
        text: 'Δεν υπάρχουν καθήκοντα για αυτό το μάθημα.',
        color: Colors.grey.shade600,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 30),
      children: [
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
        const SizedBox(height: 16),
        _HomeworkTable(rows: _rows),
        if (_loadError != null) ...[
          const SizedBox(height: 12),
          _HomeworkMessage(text: _loadError!, color: Colors.grey.shade700),
        ],
        if (_hasMore) ...[
          const SizedBox(height: 16),
          Center(
            child: _LoadMoreHomeworkButton(
              isLoading: _isLoadingMore,
              onTap: () => _loadNextPage(),
            ),
          ),
        ],
      ],
    );
  }
}

class _HomeworkTable extends StatelessWidget {
  const _HomeworkTable({required this.rows});

  final List<_CurriculumRow> rows;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE4E9FA)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildInfoTable(
              _buildRow(const ['Ημ/νία', 'Ύλη που παραδόθηκε'], isHeader: true),
            ),
            for (final row in rows)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildInfoTable(
                      _buildRow([row.formattedCreatedAt, row.inClass ?? '-']),
                    ),
                    if (row.homework != null)
                      _buildHomeworkBox(row.formattedDate, row.homework!),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTable(TableRow row) {
    return Table(
      columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(2.4)},
      border: TableBorder(
        verticalInside: BorderSide(color: Colors.grey.shade200),
      ),
      children: [row],
    );
  }

  TableRow _buildRow(List<String> values, {bool isHeader = false}) {
    return TableRow(
      decoration: BoxDecoration(
        color: isHeader ? const Color(0xFFEAF0FF) : Colors.white,
      ),
      children: [
        for (final value in values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Text(
              value,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isHeader
                    ? _MyHomeworkPageState._contentColor
                    : const Color(0xFF313A2E),
                fontSize: isHeader ? 12 : 12.5,
                fontWeight: isHeader ? FontWeight.w900 : FontWeight.w700,
                height: 1.12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHomeworkBox(String date, String homework) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FF),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 11),
      child: Text.rich(
        TextSpan(
          children: [
            const TextSpan(
              text: 'Καθήκοντα για ',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            TextSpan(
              text: '$date: ',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            TextSpan(text: homework),
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

class _HomeworkMessage extends StatelessWidget {
  const _HomeworkMessage({required this.text, required this.color});

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

class _LoadMoreHomeworkButton extends StatelessWidget {
  const _LoadMoreHomeworkButton({required this.isLoading, required this.onTap});

  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF89ACFF),
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
                      color: Color(0xFF385DC9),
                    ),
                  )
                : const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF385DC9),
                    size: 34,
                  ),
          ),
        ),
      ),
    );
  }
}

class _CurriculumRow {
  const _CurriculumRow({
    required this.createdAt,
    required this.forDate,
    required this.inClass,
    required this.homework,
  });

  factory _CurriculumRow.fromRow(Map<String, dynamic> row) {
    return _CurriculumRow(
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
      forDate: DateTime.tryParse(row['for_date']?.toString() ?? ''),
      inClass: _readOptionalText(row['in_class']),
      homework: _readOptionalText(row['homework']),
    );
  }

  final DateTime? createdAt;
  final DateTime? forDate;
  final String? inClass;
  final String? homework;

  String get formattedCreatedAt => _formatShortDate(createdAt);

  String get formattedDate => _formatShortDate(forDate);
}

String _formatShortDate(DateTime? date) {
  if (date == null) {
    return '-';
  }

  final year = (date.year % 100).toString().padLeft(2, '0');
  return '${date.day}/${date.month}/$year';
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
