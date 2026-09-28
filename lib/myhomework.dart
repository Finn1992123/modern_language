import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MyHomeworkPage extends StatefulWidget {
  const MyHomeworkPage({
    super.key,
    required this.studentId,
    required this.language,
    required this.languageLabel,
  });

  final String studentId;
  final String language;
  final String languageLabel;

  @override
  State<MyHomeworkPage> createState() => _MyHomeworkPageState();
}

class _MyHomeworkPageState extends State<MyHomeworkPage> {
  static const Color _headerColor = Color(0xFF89ACFF);
  static const Color _contentColor = Color(0xFF385DC9);
  static const int _pageSize = 10;

  final List<_CurriculumRow> _rows = [];
  List<_CurriculumRow> _personalRows = const [];
  bool _isInitialLoading = true;
  bool _isLoadingPersonal = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _loadError;
  String? _personalLoadError;

  @override
  void initState() {
    super.initState();
    _loadNextPage(isInitialLoad: true);
    _loadPersonalRows();
  }

  Future<void> _loadPersonalRows() async {
    if (widget.studentId.isEmpty || widget.language.isEmpty) {
      setState(() => _isLoadingPersonal = false);
      return;
    }
    try {
      final rows = await Supabase.instance.client.rpc(
        'get_student_language_personal_homework_rows',
        params: {
          'input_student_id': widget.studentId,
          'input_language': widget.language,
          'input_from_date': _formatIsoDate(DateTime.now()),
        },
      );
      if (!mounted) return;
      setState(() {
        _personalRows = rows is List
            ? rows
                  .whereType<Map>()
                  .map(
                    (row) =>
                        _CurriculumRow.fromRow(Map<String, dynamic>.from(row)),
                  )
                  .toList()
            : const [];
        _isLoadingPersonal = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingPersonal = false;
        _personalLoadError =
            'Δεν μπορέσαμε να φορτώσουμε τα προσωπικά καθήκοντα.';
      });
    }
  }

  Future<void> _loadNextPage({bool isInitialLoad = false}) async {
    if (_isLoadingMore || (!_hasMore && !isInitialLoad)) {
      return;
    }

    if (widget.studentId.isEmpty || widget.language.isEmpty) {
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
        'get_student_language_curriculum_rows',
        params: {
          'input_student_id': widget.studentId,
          'input_language': widget.language,
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

  Future<List<_CurriculumRow>> _loadUpcomingHomework() async {
    if (widget.studentId.isEmpty || widget.language.isEmpty) {
      return <_CurriculumRow>[];
    }

    final results = await Future.wait([
      Supabase.instance.client.rpc(
        'get_student_language_upcoming_curriculum_rows',
        params: {
          'input_student_id': widget.studentId,
          'input_language': widget.language,
          'input_from_date': _formatIsoDate(DateTime.now()),
        },
      ),
      Supabase.instance.client.rpc(
        'get_student_language_personal_homework_rows',
        params: {
          'input_student_id': widget.studentId,
          'input_language': widget.language,
          'input_from_date': _formatIsoDate(DateTime.now()),
        },
      ),
    ]);

    final rows = <_CurriculumRow>[];
    for (var index = 0; index < results.length; index++) {
      final result = results[index];
      if (result is! List) continue;
      rows.addAll(
        result.whereType<Map>().map((row) {
          final data = Map<String, dynamic>.from(row);
          if (index == 1) data['is_personal'] = true;
          return _CurriculumRow.fromRow(data);
        }),
      );
    }
    rows.sort((a, b) {
      final aDate = a.forDate;
      final bDate = b.forDate;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      final byDate = aDate.compareTo(bDate);
      return byDate != 0 ? byDate : _compareCreatedAtNewestFirst(a, b);
    });
    return rows;
  }

  void _showUpcomingHomeworkDialog() {
    final upcomingHomeworkFuture = _loadUpcomingHomework();

    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 620),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
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
                        width: 36,
                        height: 36,
                        child: Icon(
                          Icons.close_rounded,
                          color: Color(0xFF9AA0A9),
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  const Text(
                    'Τα επόμενα καθήκοντα μου',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _contentColor,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: FutureBuilder<List<_CurriculumRow>>(
                      future: upcomingHomeworkFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 44),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }

                        if (snapshot.hasError) {
                          return _HomeworkMessage(
                            text:
                                'Δεν μπορέσαμε να φορτώσουμε τα επόμενα καθήκοντα.',
                            color: Colors.grey.shade700,
                          );
                        }

                        final rows = snapshot.data ?? <_CurriculumRow>[];
                        if (rows.isEmpty) {
                          return _HomeworkMessage(
                            text: 'Δεν υπάρχουν επόμενα καθήκοντα.',
                            color: Colors.grey.shade600,
                          );
                        }

                        return _UpcomingHomeworkList(rows: rows);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
    if (_isInitialLoading || _isLoadingPersonal) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null && _rows.isEmpty && _personalRows.isEmpty) {
      return _HomeworkMessage(text: _loadError!, color: Colors.grey.shade700);
    }

    if (_rows.isEmpty && _personalRows.isEmpty) {
      if (_personalLoadError != null) {
        return _HomeworkMessage(
          text: _personalLoadError!,
          color: Colors.grey.shade700,
        );
      }
      return _HomeworkMessage(
        text: 'Δεν υπάρχουν καθήκοντα για αυτό το μάθημα.',
        color: Colors.grey.shade600,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 30),
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
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
            _UpcomingHomeworkButton(onTap: _showUpcomingHomeworkDialog),
          ],
        ),
        const SizedBox(height: 16),
        if (_personalRows.isNotEmpty) ...[
          _PersonalHomeworkList(rows: _personalRows),
          const SizedBox(height: 16),
        ],
        if (_rows.isNotEmpty) _HomeworkTable(rows: _rows),
        if (_personalLoadError != null)
          _HomeworkMessage(
            text: _personalLoadError!,
            color: Colors.grey.shade700,
          ),
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

class _UpcomingHomeworkButton extends StatelessWidget {
  const _UpcomingHomeworkButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.event_available_rounded, size: 18),
      label: const Text('Τα επόμενα καθήκοντα μου'),
      style: TextButton.styleFrom(
        foregroundColor: _MyHomeworkPageState._contentColor,
        backgroundColor: const Color(0xFFEAF0FF),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
          height: 1.1,
        ),
      ),
    );
  }
}

class _UpcomingHomeworkList extends StatelessWidget {
  const _UpcomingHomeworkList({required this.rows});

  final List<_CurriculumRow> rows;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      itemCount: rows.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final row = rows[index];
        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9FF),
            border: Border.all(color: const Color(0xFFE4E9FA)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (row.className != null) ...[
                  Text(
                    row.className!,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                ],
                Text(
                  row.isPersonal
                      ? 'Προσωπικό · Για ${row.formattedDate}'
                      : 'Για ${row.formattedDate}',
                  style: const TextStyle(
                    color: _MyHomeworkPageState._contentColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  row.homework ?? '-',
                  style: const TextStyle(
                    color: Color(0xFF313A2E),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.28,
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
                    if (row.className != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          row.className!,
                          style: const TextStyle(
                            color: _MyHomeworkPageState._contentColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
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

class _PersonalHomeworkList extends StatelessWidget {
  const _PersonalHomeworkList({required this.rows});

  final List<_CurriculumRow> rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF4EEFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD9C7F5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.person_rounded, color: Color(0xFF7B4CC9)),
                SizedBox(width: 8),
                Text(
                  'Προσωπικά καθήκοντα',
                  style: TextStyle(
                    color: Color(0xFF7B4CC9),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < rows.length; index++) ...[
              if (index > 0) const Divider(height: 22),
              if (rows[index].className != null)
                Text(
                  rows[index].className!,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              Text(
                'Για ${rows[index].formattedDate}',
                style: const TextStyle(
                  color: Color(0xFF7B4CC9),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                rows[index].homework ?? '-',
                style: const TextStyle(
                  color: Color(0xFF313A2E),
                  fontWeight: FontWeight.w700,
                  height: 1.28,
                ),
              ),
            ],
          ],
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
    required this.isPersonal,
    required this.className,
  });

  factory _CurriculumRow.fromRow(Map<String, dynamic> row) {
    return _CurriculumRow(
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
      forDate: DateTime.tryParse(row['for_date']?.toString() ?? ''),
      inClass: _readOptionalText(row['in_class']),
      homework: _readOptionalText(row['homework']),
      isPersonal: row['is_personal'] == true,
      className: _readOptionalText(row['class_name']),
    );
  }

  final DateTime? createdAt;
  final DateTime? forDate;
  final String? inClass;
  final String? homework;
  final bool isPersonal;
  final String? className;

  String get formattedCreatedAt => _formatShortDate(createdAt);

  String get formattedDate => _formatShortDate(forDate);
}

int _compareCreatedAtNewestFirst(_CurriculumRow a, _CurriculumRow b) {
  final aCreatedAt = a.createdAt;
  final bCreatedAt = b.createdAt;

  if (aCreatedAt == null && bCreatedAt == null) {
    return 0;
  }
  if (aCreatedAt == null) {
    return 1;
  }
  if (bCreatedAt == null) {
    return -1;
  }

  return bCreatedAt.compareTo(aCreatedAt);
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
