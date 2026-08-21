import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MyAchievementsPage extends StatelessWidget {
  const MyAchievementsPage({
    super.key,
    required this.studentId,
    required this.classId,
    required this.languageLabel,
    this.showJuniorAchievements = true,
  });

  final String studentId;
  final String classId;
  final String languageLabel;
  final bool showJuniorAchievements;

  static const Color _headerColor = Color(0xFFE4D562);
  static const Color _contentColor = Color(0xFFCFB010);

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
                          'Επιτεύγματα',
                          style: TextStyle(
                            color: _contentColor,
                            fontSize: 31,
                            fontWeight: FontWeight.w800,
                            height: 1.08,
                          ),
                        ),
                        SizedBox(height: 12),
                        Icon(
                          Icons.star_rounded,
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
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 22, 0, 30),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      _languageFlagAsset(languageLabel),
                      width: 30,
                      height: 30,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      languageLabel,
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
                if (showJuniorAchievements)
                  _JuniorAchievementsContent(
                    studentId: studentId,
                    classId: classId,
                    languageLabel: languageLabel,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JuniorAchievementsContent extends StatefulWidget {
  const _JuniorAchievementsContent({
    required this.studentId,
    required this.classId,
    required this.languageLabel,
  });

  final String studentId;
  final String classId;
  final String languageLabel;

  @override
  State<_JuniorAchievementsContent> createState() =>
      _JuniorAchievementsContentState();
}

class _JuniorAchievementsContentState
    extends State<_JuniorAchievementsContent> {
  late Future<Map<String, int>> _countsFuture = _loadCounts();

  Future<Map<String, int>> _loadCounts() async {
    final rows = await Supabase.instance.client.rpc(
      'get_student_junior_achievements',
      params: {
        'input_student_id': widget.studentId,
        'input_class_id': widget.classId,
      },
    );

    if (rows is! List) {
      return const {};
    }

    return {
      for (final row in rows.whereType<Map>())
        if (row['achievement_type'] is String)
          row['achievement_type'] as String: _readCount(
            row['achievement_count'],
          ),
    };
  }

  void _retry() {
    setState(() {
      _countsFuture = _loadCounts();
    });
  }

  void _openClassAchievements() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ClassAchievementsPage(
          studentId: widget.studentId,
          classId: widget.classId,
          languageLabel: widget.languageLabel,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: _countsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(36),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
            child: Column(
              children: [
                const Text(
                  'Δεν μπορέσαμε να φορτώσουμε τα επιτεύγματα.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF173A8A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Δοκιμή ξανά'),
                ),
              ],
            ),
          );
        }

        final counts = snapshot.data ?? const {};

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 700 ? 4 : 3;

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _achievements.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 18,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.78,
                    ),
                    itemBuilder: (context, index) {
                      final achievement = _achievements[index];
                      return _AchievementCard(
                        achievement: achievement,
                        count: counts[achievement.id] ?? 0,
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openClassAchievements,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF173A8A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  icon: const Icon(Icons.emoji_events_rounded),
                  label: const Text(
                    'Επιτεύγματα τάξης',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ClassAchievementsPage extends StatefulWidget {
  const _ClassAchievementsPage({
    required this.studentId,
    required this.classId,
    required this.languageLabel,
  });

  final String studentId;
  final String classId;
  final String languageLabel;

  @override
  State<_ClassAchievementsPage> createState() => _ClassAchievementsPageState();
}

class _ClassAchievementsPageState extends State<_ClassAchievementsPage> {
  late Future<List<_LeaderboardEntry>> _entriesFuture = _loadEntries();
  String _selectedAchievementId = _achievements.first.id;

  Future<List<_LeaderboardEntry>> _loadEntries() async {
    final rows = await Supabase.instance.client.rpc(
      'get_junior_achievement_leaderboard',
      params: {
        'input_student_id': widget.studentId,
        'input_class_id': widget.classId,
      },
    );

    if (rows is! List) {
      return const [];
    }

    return rows
        .whereType<Map>()
        .map((row) => _LeaderboardEntry.fromRow(Map<String, dynamic>.from(row)))
        .where((entry) => entry.studentId.isNotEmpty)
        .toList();
  }

  void _retry() {
    setState(() {
      _entriesFuture = _loadEntries();
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedAchievement = _achievements.firstWhere(
      (achievement) => achievement.id == _selectedAchievementId,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        title: const Text('Επιτεύγματα τάξης'),
        backgroundColor: const Color(0xFFE4D562),
        foregroundColor: const Color(0xFF173A8A),
      ),
      body: FutureBuilder<List<_LeaderboardEntry>>(
        future: _entriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Δεν μπορέσαμε να φορτώσουμε την κατάταξη.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Δοκιμή ξανά'),
                    ),
                  ],
                ),
              ),
            );
          }

          final entries = (snapshot.data ?? const [])
              .where((entry) => entry.achievementType == _selectedAchievementId)
              .toList();

          return Column(
            children: [
              const SizedBox(height: 16),
              SizedBox(
                height: 88,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _achievements.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final achievement = _achievements[index];
                    final selected = achievement.id == _selectedAchievementId;

                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedAchievementId = achievement.id;
                        });
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 78,
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: selected ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF173A8A)
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Image.asset(
                          achievement.asset,
                          fit: BoxFit.contain,
                          semanticLabel: achievement.label,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Image.asset(
                      selectedAchievement.asset,
                      width: 52,
                      height: 52,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        selectedAchievement.label,
                        style: const TextStyle(
                          color: Color(0xFF173A8A),
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: entries.isEmpty
                    ? const Center(child: Text('Δεν υπάρχουν μαθητές.'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return _LeaderboardRow(
                            entry: entry,
                            isCurrentStudent:
                                entry.studentId == widget.studentId,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.entry, required this.isCurrentStudent});

  final _LeaderboardEntry entry;
  final bool isCurrentStudent;

  @override
  Widget build(BuildContext context) {
    final positionColor = switch (entry.position) {
      1 => const Color(0xFFFFC928),
      2 => const Color(0xFFB7C2D0),
      3 => const Color(0xFFD9955B),
      _ => const Color(0xFFE7E9F2),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isCurrentStudent ? const Color(0xFFEAF0FF) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrentStudent
              ? const Color(0xFF173A8A)
              : const Color(0xFFE7E9F2),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: positionColor,
            foregroundColor: const Color(0xFF173A8A),
            child: Text(
              '${entry.position}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isCurrentStudent
                  ? '${entry.studentName} (Εσύ)'
                  : entry.studentName,
              style: const TextStyle(
                color: Color(0xFF173A8A),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            'x ${entry.count}',
            style: const TextStyle(
              color: Color(0xFF173A8A),
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardEntry {
  const _LeaderboardEntry({
    required this.achievementType,
    required this.studentId,
    required this.studentName,
    required this.count,
    required this.position,
  });

  factory _LeaderboardEntry.fromRow(Map<String, dynamic> row) {
    return _LeaderboardEntry(
      achievementType: row['achievement_type']?.toString() ?? '',
      studentId: row['student_id']?.toString() ?? '',
      studentName: row['student_name']?.toString().trim().isNotEmpty == true
          ? row['student_name'].toString().trim()
          : 'Μαθητής',
      count: _readCount(row['achievement_count']),
      position: _readCount(row['rank_position'], fallback: 1),
    );
  }

  final String achievementType;
  final String studentId;
  final String studentName;
  final int count;
  final int position;
}

int _readCount(Object? value, {int fallback = 0}) {
  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.achievement, required this.count});

  final _Achievement achievement;
  final int count;

  @override
  Widget build(BuildContext context) {
    final safeCount = count < 0 ? 0 : count;

    return Semantics(
      label: '${achievement.label}, $safeCount',
      child: Column(
        children: [
          Expanded(
            child: Image.asset(
              achievement.asset,
              fit: BoxFit.contain,
              semanticLabel: achievement.label,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'x $safeCount',
            style: const TextStyle(
              color: Color(0xFF173A8A),
              fontSize: 18,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _Achievement {
  const _Achievement(this.id, this.label, this.asset);

  final String id;
  final String label;
  final String asset;
}

const List<_Achievement> _achievements = [
  _Achievement('quiet', 'Ο πιο ήσυχος', 'lib/img/quiet.png'),
  _Achievement('reading', 'Ανάγνωση', 'lib/img/reading.png'),
  _Achievement('speaking', 'Προφορικός λόγος', 'lib/img/speaking.png'),
  _Achievement('try', 'Προσπάθεια', 'lib/img/try.png'),
  _Achievement('vocabulary', 'Λεξιλόγιο', 'lib/img/vocabulary.png'),
  _Achievement('dictation', 'Ορθογραφία', 'lib/img/dictation.png'),
  _Achievement('participation', 'Συμμετοχή', 'lib/img/participation.png'),
  _Achievement('grammar', 'Γραμματική', 'lib/img/grammar.png'),
];

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
