import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'games.dart';
import 'myachievements.dart';
import 'myexercises.dart';
import 'mygrades.dart';
import 'myhomework.dart';
import 'profile.dart';

class StudentsMenuPage extends StatefulWidget {
  const StudentsMenuPage({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.profilePic,
    required this.heroTag,
    required this.accentColor,
  });

  final String studentId;
  final String studentName;
  final String? profilePic;
  final String heroTag;
  final Color accentColor;

  @override
  State<StudentsMenuPage> createState() => _StudentsMenuPageState();
}

class _StudentsMenuPageState extends State<StudentsMenuPage> {
  late final Future<List<_ClassGradeBreakdown>> _gradesFuture =
      _loadGradeBreakdown();

  Future<List<_ClassGradeBreakdown>> _loadGradeBreakdown() async {
    if (widget.studentId.isEmpty) {
      return const [];
    }

    final rows = await Supabase.instance.client.rpc(
      'get_student_language_averages',
      params: {'input_student_id': widget.studentId},
    );

    if (rows is! List) {
      return const [];
    }

    return rows
        .whereType<Map>()
        .map(
          (row) => _ClassGradeBreakdown.fromRow(Map<String, dynamic>.from(row)),
        )
        .where((breakdown) => breakdown.language.isNotEmpty)
        .toList()
      ..sort((a, b) => a.language.compareTo(b.language));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFF39D2C0)],
            stops: [0.32, 1],
          ),
        ),
        child: SafeArea(
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
              const SizedBox(height: 4),
              SizedBox(
                height: 150,
                child: Center(
                  child: Hero(
                    tag: widget.heroTag,
                    child: CrownedProfilePhoto(
                      imageUrl: widget.profilePic,
                      crownTop: -12,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.studentName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: widget.accentColor,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.12,
                ),
              ),
              const SizedBox(height: 18),
              FutureBuilder<List<_ClassGradeBreakdown>>(
                future: _gradesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return _InfoPanel(
                      icon: Icons.error_outline_rounded,
                      text: 'Δεν μπορέσαμε να φορτώσουμε τους βαθμούς.',
                      color: widget.accentColor,
                    );
                  }

                  final grades = snapshot.data ?? const [];

                  if (grades.isEmpty) {
                    return _InfoPanel(
                      icon: Icons.school_outlined,
                      text: 'Δεν υπάρχουν βαθμοί ακόμα.',
                      color: widget.accentColor,
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final breakdown in grades) ...[
                        _GradeBreakdownCard(
                          breakdown: breakdown,
                          studentId: widget.studentId,
                          accentColor: widget.accentColor,
                        ),
                        const SizedBox(height: 14),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradeBreakdownCard extends StatelessWidget {
  const _GradeBreakdownCard({
    required this.breakdown,
    required this.studentId,
    required this.accentColor,
  });

  final _ClassGradeBreakdown breakdown;
  final String studentId;
  final Color accentColor;

  void _openMyGrades(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MyGradesPage(
          studentId: studentId,
          classId: breakdown.classId,
          languageLabel: _languageLabel(breakdown.language),
        ),
      ),
    );
  }

  void _openMyHomework(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MyHomeworkPage(
          studentId: studentId,
          classId: breakdown.classId,
          languageLabel: _languageLabel(breakdown.language),
        ),
      ),
    );
  }

  void _openMyAchievements(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MyAchievementsPage(
          languageLabel: _languageLabel(breakdown.language),
        ),
      ),
    );
  }

  void _openMyExercises(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            MyExercisesPage(languageLabel: _languageLabel(breakdown.language)),
      ),
    );
  }

  void _openGames(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => GamesPage(
          studentId: studentId,
          classId: breakdown.classId,
          languageLabel: _languageLabel(breakdown.language),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Image.asset(
                _languageFlagAsset(breakdown.language),
                width: 34,
                height: 34,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _languageLabel(breakdown.language),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF173A8A),
                      ),
                    ),
                    if (breakdown.daysHours != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        breakdown.daysHours!,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final item in breakdown.items) ...[
            _GradeProgressRow(
              label: item.label,
              value: item.value,
              accentColor: accentColor,
            ),
            const SizedBox(height: 12),
          ],
          _GradeProgressRow(
            label: 'Overall',
            value: breakdown.overall,
            accentColor: accentColor,
            isOverall: true,
          ),
          const SizedBox(height: 16),
          _LessonActionGrid(
            onGradesTap: () => _openMyGrades(context),
            onHomeworkTap: () => _openMyHomework(context),
            onAchievementsTap: () => _openMyAchievements(context),
            onExercisesTap: () => _openMyExercises(context),
            onGamesTap: () => _openGames(context),
          ),
        ],
      ),
    );
  }
}

class _LessonActionGrid extends StatelessWidget {
  const _LessonActionGrid({
    required this.onGradesTap,
    required this.onHomeworkTap,
    required this.onAchievementsTap,
    required this.onExercisesTap,
    required this.onGamesTap,
  });

  final VoidCallback onGradesTap;
  final VoidCallback onHomeworkTap;
  final VoidCallback onAchievementsTap;
  final VoidCallback onExercisesTap;
  final VoidCallback onGamesTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: [
            _LessonActionTile(
              label: 'Οι βαθμοί μου',
              icon: Icons.text_increase_rounded,
              backgroundColor: const Color(0x9682FE63),
              foregroundColor: const Color(0xFF2D7D10),
              onTap: onGradesTap,
            ),
            _LessonActionTile(
              label: 'Τα καθήκοντα μου',
              icon: Icons.edit_rounded,
              backgroundColor: const Color(0xFF89ACFF),
              foregroundColor: const Color(0xFF385DC9),
              onTap: onHomeworkTap,
            ),
            _LessonActionTile(
              label: 'Επιτεύγματα',
              icon: Icons.star_rounded,
              backgroundColor: const Color(0xFFE4D562),
              foregroundColor: const Color(0xFFCFB010),
              onTap: onAchievementsTap,
            ),
            _LessonActionTile(
              label: 'Ασκήσεις',
              icon: Icons.edit_note_rounded,
              backgroundColor: const Color(0x57FF1010),
              foregroundColor: const Color(0xFF7D1010),
              onTap: onExercisesTap,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _LessonActionButton(
          label: 'Παιχνίδια',
          icon: Icons.sports_esports_rounded,
          backgroundColor: const Color(0xFF4D4AAD),
          foregroundColor: const Color(0xFF18A8EF),
          onTap: onGamesTap,
        ),
      ],
    );
  }
}

class _LessonActionTile extends StatelessWidget {
  const _LessonActionTile({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  height: 1.08,
                ),
              ),
              const SizedBox(height: 8),
              _BubblyIcon(icon: icon, color: foregroundColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _LessonActionButton extends StatelessWidget {
  const _LessonActionButton({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        padding: const EdgeInsets.symmetric(vertical: 15),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _BubblyIcon extends StatelessWidget {
  const _BubblyIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const size = 34.0;
    const offsets = [
      Offset.zero,
      Offset(0.7, 0),
      Offset(-0.7, 0),
      Offset(0, 0.7),
    ];

    return SizedBox.square(
      dimension: 38,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final offset in offsets)
            Transform.translate(
              offset: offset,
              child: Icon(icon, color: color, size: size),
            ),
        ],
      ),
    );
  }
}

class _GradeProgressRow extends StatelessWidget {
  const _GradeProgressRow({
    required this.label,
    required this.value,
    required this.accentColor,
    this.isOverall = false,
  });

  final String label;
  final double? value;
  final Color accentColor;
  final bool isOverall;

  @override
  Widget build(BuildContext context) {
    final progress = _gradeProgress(value);
    final color = isOverall ? accentColor : const Color(0xFF173A8A);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: isOverall ? 16 : 14,
                  fontWeight: isOverall ? FontWeight.w900 : FontWeight.w800,
                ),
              ),
            ),
            Text(
              value == null ? '-' : '${value!.toStringAsFixed(1)}%',
              style: TextStyle(
                color: color,
                fontSize: isOverall ? 18 : 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: isOverall ? 12 : 9,
            backgroundColor: Colors.white.withValues(alpha: 0.78),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF173A8A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassGradeBreakdown {
  const _ClassGradeBreakdown({
    required this.classId,
    required this.language,
    required this.daysHours,
    required this.reading,
    required this.vocabulary,
    required this.grammar,
    required this.writing,
    required this.listening,
    required this.speaking,
    required this.homework,
    required this.effort,
    required this.overall,
  });

  factory _ClassGradeBreakdown.fromRow(Map<String, dynamic> row) {
    final classId = row['class_id'];
    final language = row['language'];
    final daysHours = row['days_hours'];

    return _ClassGradeBreakdown(
      classId: classId is String ? classId : '',
      language: language is String ? language.trim().toLowerCase() : '',
      daysHours: daysHours is String && daysHours.trim().isNotEmpty
          ? daysHours.trim()
          : null,
      reading: _readGrade(row['reading']),
      vocabulary: _readGrade(row['vocabulary']),
      grammar: _readGrade(row['grammar']),
      writing: _readGrade(row['writing']),
      listening: _readGrade(row['listening']),
      speaking: _readGrade(row['speaking']),
      homework: _readGrade(row['homework']),
      effort: _readGrade(row['effort']),
      overall: _readGrade(row['overall']),
    );
  }

  final String classId;
  final String language;
  final String? daysHours;
  final double? reading;
  final double? vocabulary;
  final double? grammar;
  final double? writing;
  final double? listening;
  final double? speaking;
  final double? homework;
  final double? effort;
  final double? overall;

  List<_GradeItem> get items => [
    _GradeItem('Reading', reading),
    _GradeItem('Vocabulary', vocabulary),
    _GradeItem('Grammar', grammar),
    _GradeItem('Writing', writing),
    _GradeItem('Listening', listening),
    _GradeItem('Speaking', speaking),
    _GradeItem('Homework', homework),
    _GradeItem('Effort', effort),
  ];
}

class _GradeItem {
  const _GradeItem(this.label, this.value);

  final String label;
  final double? value;
}

double? _readGrade(Object? value) => value is num ? value.toDouble() : null;

double _gradeProgress(double? value) {
  if (value == null) {
    return 0;
  }

  final maxGrade = value > 10 ? 100 : 10;
  return (value / maxGrade).clamp(0.0, 1.0);
}

String _languageFlagAsset(String language) {
  switch (language) {
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

String _languageLabel(String language) {
  switch (language) {
    case 'english':
      return 'English';
    case 'spanish':
      return 'Spanish';
    case 'french':
      return 'French';
    case 'german':
      return 'German';
    default:
      return language;
  }
}
