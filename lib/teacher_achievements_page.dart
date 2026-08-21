import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_confetti/flutter_confetti.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeacherAchievementsPage extends StatefulWidget {
  const TeacherAchievementsPage({super.key});

  @override
  State<TeacherAchievementsPage> createState() =>
      _TeacherAchievementsPageState();
}

class _TeacherAchievementsPageState extends State<TeacherAchievementsPage> {
  static const _contentColor = Color(0xFF173A8A);

  List<_TeacherClass> _classes = const [];
  List<_Student> _students = const [];
  _TeacherClass? _selectedClass;
  final Set<String> _selectedStudentIds = {};
  List<_RankingEntry> _ranking = const [];
  int _achievementIndex = 0;
  bool _isLoadingClasses = true;
  bool _isLoadingStudents = false;
  bool _isAwarding = false;
  bool _isComplete = false;
  String? _loadError;

  _AchievementDefinition get _achievement => _awardOrder[_achievementIndex];

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() {
      _isLoadingClasses = true;
      _loadError = null;
    });

    try {
      final rows = await Supabase.instance.client.rpc('get_teacher_classes');
      final classes = rows is List
          ? rows
                .whereType<Map>()
                .map(
                  (row) =>
                      _TeacherClass.fromRow(Map<String, dynamic>.from(row)),
                )
                .where(
                  (teacherClass) =>
                      teacherClass.id.isNotEmpty &&
                      _isJuniorClass(teacherClass.name),
                )
                .toList()
          : <_TeacherClass>[];

      if (!mounted) return;
      setState(() {
        _classes = classes;
        _isLoadingClasses = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Δεν μπορέσαμε να φορτώσουμε τις τάξεις.';
        _isLoadingClasses = false;
      });
    }
  }

  Future<void> _selectClass(_TeacherClass? teacherClass) async {
    if (teacherClass == null) return;

    setState(() {
      _selectedClass = teacherClass;
      _students = const [];
      _selectedStudentIds.clear();
      _ranking = const [];
      _achievementIndex = 0;
      _isComplete = false;
      _isLoadingStudents = true;
      _loadError = null;
    });

    try {
      final rows = await Supabase.instance.client.rpc(
        'get_teacher_achievement_students',
        params: {'input_class_id': teacherClass.id},
      );
      final students = rows is List
          ? rows
                .whereType<Map>()
                .map((row) => _Student.fromRow(Map<String, dynamic>.from(row)))
                .where((student) => student.id.isNotEmpty)
                .toList()
          : <_Student>[];
      students.sort((a, b) => a.name.compareTo(b.name));

      if (!mounted || _selectedClass?.id != teacherClass.id) return;
      setState(() {
        _students = students;
        _isLoadingStudents = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Δεν μπορέσαμε να φορτώσουμε τους μαθητές.';
        _isLoadingStudents = false;
      });
    }
  }

  void _toggleStudent(String studentId) {
    if (_isAwarding) return;

    setState(() {
      if (_achievement.allowsMultiple) {
        if (!_selectedStudentIds.add(studentId)) {
          _selectedStudentIds.remove(studentId);
        }
      } else {
        _selectedStudentIds
          ..clear()
          ..add(studentId);
      }
    });

    if (!_achievement.allowsMultiple) {
      _awardAchievement();
    }
  }

  Future<void> _awardAchievement() async {
    final teacherClass = _selectedClass;
    if (teacherClass == null || _selectedStudentIds.isEmpty) return;

    setState(() => _isAwarding = true);
    try {
      final rows = await Supabase.instance.client.rpc(
        'award_junior_achievement_to_students',
        params: {
          'input_class_id': teacherClass.id,
          'input_achievement_type': _achievement.id,
          'input_student_ids': _selectedStudentIds.toList(),
        },
      );
      final ranking = rows is List
          ? rows
                .whereType<Map>()
                .map(
                  (row) =>
                      _RankingEntry.fromRow(Map<String, dynamic>.from(row)),
                )
                .toList()
          : <_RankingEntry>[];

      if (!mounted) return;
      setState(() {
        _isAwarding = false;
        _ranking = ranking;
      });
      await Future<void>.delayed(Duration.zero);
      await _showAwardAnimation();
      if (!mounted) return;
      _nextAchievement();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isAwarding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Η απονομή δεν ολοκληρώθηκε. Δοκιμάστε ξανά.'),
        ),
      );
    }
  }

  Future<void> _showAwardAnimation() async {
    final recipients = _students
        .where((student) => _selectedStudentIds.contains(student.id))
        .toList();

    var isDialogOpen = true;
    final dialog = showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Απονομή επιτεύγματος',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, _, _) => _AwardCelebration(
        achievement: _achievement,
        recipients: recipients,
        ranking: _ranking,
      ),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.82, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          child: child,
        ),
      ),
    );
    dialog.whenComplete(() => isDialogOpen = false);

    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (mounted && isDialogOpen) {
      Confetti.launch(
        context,
        options: const ConfettiOptions(particleCount: 100, spread: 70, y: 0.6),
      );
    }
    await dialog;
  }

  void _nextAchievement() {
    setState(() {
      _selectedStudentIds.clear();
      _ranking = const [];
      if (_achievementIndex == _awardOrder.length - 1) {
        _isComplete = true;
      } else {
        _achievementIndex += 1;
      }
    });
  }

  void _restartAwards() {
    setState(() {
      _achievementIndex = 0;
      _selectedStudentIds.clear();
      _ranking = const [];
      _isComplete = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLargeDisplay = _isLargeDisplay(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: isLargeDisplay ? 76 : kToolbarHeight,
        title: Text(
          'Απονομή επιτευγμάτων',
          style: TextStyle(
            fontSize: isLargeDisplay ? 26 : 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: const Color(0xFFE4D562),
        foregroundColor: _contentColor,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            isLargeDisplay ? 36 : 18,
            isLargeDisplay ? 30 : 20,
            isLargeDisplay ? 36 : 18,
            isLargeDisplay ? 48 : 32,
          ),
          children: [
            if (_isLoadingClasses)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_classes.isEmpty)
              _MessageCard(
                message:
                    _loadError ??
                    'Δεν υπάρχουν τάξεις JA, JB, SA ή SB για απονομή.',
                onRetry: _loadError == null ? null : _loadClasses,
              )
            else ...[
              _ClassCircleSelector(
                classes: _classes,
                selectedClassId: _selectedClass?.id,
                enabled: !_isAwarding,
                onSelected: _selectClass,
              ),
              if (_isLoadingStudents)
                const Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_loadError != null) ...[
                const SizedBox(height: 18),
                _MessageCard(
                  message: _loadError!,
                  onRetry: () => _selectClass(_selectedClass),
                ),
              ] else if (_selectedClass != null && _students.isEmpty) ...[
                const SizedBox(height: 18),
                const _MessageCard(
                  message: 'Δεν υπάρχουν μαθητές σε αυτή την τάξη.',
                ),
              ] else if (_selectedClass != null) ...[
                const SizedBox(height: 20),
                if (_isComplete)
                  _CompletionCard(onRestart: _restartAwards)
                else if (_ranking.isNotEmpty)
                  _RankingCard(
                    achievement: _achievement,
                    ranking: _ranking,
                    selectedStudentIds: _selectedStudentIds,
                  )
                else
                  _AwardSelectionCard(
                    key: ValueKey(_achievement.id),
                    achievement: _achievement,
                    students: _students,
                    selectedStudentIds: _selectedStudentIds,
                    isAwarding: _isAwarding,
                    onStudentTap: _toggleStudent,
                    onAward: _awardAchievement,
                    onSkip: _nextAchievement,
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ClassCircleSelector extends StatelessWidget {
  const _ClassCircleSelector({
    required this.classes,
    required this.selectedClassId,
    required this.enabled,
    required this.onSelected,
  });

  final List<_TeacherClass> classes;
  final String? selectedClassId;
  final bool enabled;
  final ValueChanged<_TeacherClass?> onSelected;

  @override
  Widget build(BuildContext context) {
    final isLargeDisplay = _isLargeDisplay(context);
    final circleSize = isLargeDisplay ? 108.0 : 78.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Επιλογή τμήματος',
          style: TextStyle(
            color: Color(0xFF173A8A),
            fontSize: isLargeDisplay ? 21 : 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: isLargeDisplay ? 118 : 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: classes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final teacherClass = classes[index];
              final selected = teacherClass.id == selectedClassId;

              return Semantics(
                button: true,
                selected: selected,
                label: 'Τμήμα ${teacherClass.name}',
                child: InkWell(
                  onTap: enabled ? () => onSelected(teacherClass) : null,
                  customBorder: const CircleBorder(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    width: circleSize,
                    height: circleSize,
                    padding: EdgeInsets.all(isLargeDisplay ? 13 : 9),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? const Color(0xFFE4D562)
                          : const Color(0xFFEAF0FF),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFFCFB010)
                            : const Color(0xFFB9C8ED),
                        width: selected ? 3 : 1.5,
                      ),
                      boxShadow: selected
                          ? const [
                              BoxShadow(
                                color: Color(0x44CFB010),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          teacherClass.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF173A8A),
                            fontSize: isLargeDisplay ? 28 : 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AwardSelectionCard extends StatelessWidget {
  const _AwardSelectionCard({
    super.key,
    required this.achievement,
    required this.students,
    required this.selectedStudentIds,
    required this.isAwarding,
    required this.onStudentTap,
    required this.onAward,
    required this.onSkip,
  });

  final _AchievementDefinition achievement;
  final List<_Student> students;
  final Set<String> selectedStudentIds;
  final bool isAwarding;
  final ValueChanged<String> onStudentTap;
  final VoidCallback onAward;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final isLargeDisplay = _isLargeDisplay(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1450),
          curve: Curves.easeInOut,
          builder: (context, value, child) => Opacity(
            opacity: value.clamp(0, 1),
            child: Transform.scale(scale: 0.9 + (value * 0.1), child: child),
          ),
          child: Center(
            child: Image.asset(
              achievement.asset,
              width: isLargeDisplay ? 230 : 154,
              height: isLargeDisplay ? 230 : 154,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          achievement.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _TeacherAchievementsPageState._contentColor,
            fontSize: isLargeDisplay ? 34 : 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          achievement.description,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: isLargeDisplay ? 19 : 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1000
                ? 7
                : constraints.maxWidth >= 650
                ? 5
                : 3;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: students.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: isLargeDisplay ? 22 : 14,
                crossAxisSpacing: isLargeDisplay ? 18 : 10,
                childAspectRatio: 0.78,
              ),
              itemBuilder: (context, index) {
                final student = students[index];
                return _AnimatedStudentProfileChoice(
                  key: ValueKey('${achievement.id}-${student.id}'),
                  delay: Duration(milliseconds: 1500 + (index * 160)),
                  child: _StudentProfileChoice(
                    student: student,
                    selected: selectedStudentIds.contains(student.id),
                    showCheck: achievement.allowsMultiple,
                    disabled: isAwarding,
                    onTap: () => onStudentTap(student.id),
                  ),
                );
              },
            );
          },
        ),
        if (achievement.allowsMultiple) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: selectedStudentIds.isEmpty || isAwarding
                ? null
                : onAward,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF173A8A),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: isLargeDisplay ? 22 : 15),
              textStyle: TextStyle(
                fontSize: isLargeDisplay ? 20 : 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            icon: isAwarding
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.workspace_premium_rounded),
            label: Text(isAwarding ? 'Απονομή...' : 'Απονομή επιτεύγματος'),
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: isAwarding ? null : onSkip,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF6D7485),
            padding: EdgeInsets.symmetric(vertical: isLargeDisplay ? 18 : 13),
            textStyle: TextStyle(
              fontSize: isLargeDisplay ? 18 : 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          icon: const Icon(Icons.skip_next_rounded),
          label: const Text('Παράλειψη'),
        ),
      ],
    );
  }
}

class _AnimatedStudentProfileChoice extends StatefulWidget {
  const _AnimatedStudentProfileChoice({
    super.key,
    required this.delay,
    required this.child,
  });

  final Duration delay;
  final Widget child;

  @override
  State<_AnimatedStudentProfileChoice> createState() =>
      _AnimatedStudentProfileChoiceState();
}

class _AnimatedStudentProfileChoiceState
    extends State<_AnimatedStudentProfileChoice> {
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) {
        setState(() => _isVisible = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _isVisible ? 1 : 0,
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOut,
      child: AnimatedScale(
        scale: _isVisible ? 1 : 0.45,
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeOutBack,
        child: IgnorePointer(ignoring: !_isVisible, child: widget.child),
      ),
    );
  }
}

class _StudentProfileChoice extends StatelessWidget {
  const _StudentProfileChoice({
    required this.student,
    required this.selected,
    required this.showCheck,
    required this.disabled,
    required this.onTap,
  });

  final _Student student;
  final bool selected;
  final bool showCheck;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLargeDisplay = _isLargeDisplay(context);

    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: AnimatedScale(
                scale: selected ? 1.08 : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? const Color(0xFFFFD43B)
                            : const Color(0xFFE7E9F2),
                        boxShadow: selected
                            ? const [
                                BoxShadow(
                                  color: Color(0x66FFD43B),
                                  blurRadius: 14,
                                  spreadRadius: 3,
                                ),
                              ]
                            : null,
                      ),
                      child: _StudentAvatar(student: student),
                    ),
                    if (selected && showCheck)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: isLargeDisplay ? 38 : 28,
                          height: isLargeDisplay ? 38 : 28,
                          decoration: const BoxDecoration(
                            color: Color(0xFF35B86B),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.white, spreadRadius: 2),
                            ],
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: isLargeDisplay ? 28 : 20,
                          ),
                        ),
                      ),
                    if (disabled && selected && !showCheck)
                      const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            student.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF173A8A),
              fontSize: isLargeDisplay ? 17 : 13,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentAvatar extends StatelessWidget {
  const _StudentAvatar({required this.student});

  final _Student student;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(student.profilePic ?? '');
    final hasNetworkImage =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

    return ClipOval(
      child: hasNetworkImage
          ? Image.network(
              uri.toString(),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _StudentInitials(name: student.name),
            )
          : _StudentInitials(name: student.name),
    );
  }
}

class _StudentInitials extends StatelessWidget {
  const _StudentInitials({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final isLargeDisplay = _isLargeDisplay(context);
    final words = name.trim().split(RegExp(r'\s+'));
    final initials = words
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word[0].toUpperCase())
        .join();

    return ColoredBox(
      color: const Color(0xFF627DE4),
      child: Center(
        child: Text(
          initials.isEmpty ? '?' : initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: isLargeDisplay ? 32 : 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({
    required this.achievement,
    required this.ranking,
    required this.selectedStudentIds,
  });

  final _AchievementDefinition achievement;
  final List<_RankingEntry> ranking;
  final Set<String> selectedStudentIds;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Image.asset(achievement.asset, height: 112),
          const SizedBox(height: 8),
          Text(
            'Κατάταξη · ${achievement.label}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF173A8A),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          for (final entry in ranking) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selectedStudentIds.contains(entry.studentId)
                    ? const Color(0xFFFFF5C7)
                    : const Color(0xFFF7F8FC),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: _rankColor(entry.position),
                    foregroundColor: const Color(0xFF173A8A),
                    child: Text(
                      '${entry.position}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      entry.studentName,
                      style: const TextStyle(
                        color: Color(0xFF173A8A),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    'x ${entry.count}',
                    style: const TextStyle(
                      color: Color(0xFF173A8A),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
          ],
        ],
      ),
    );
  }
}

class _AwardCelebration extends StatefulWidget {
  const _AwardCelebration({
    required this.achievement,
    required this.recipients,
    required this.ranking,
  });

  final _AchievementDefinition achievement;
  final List<_Student> recipients;
  final List<_RankingEntry> ranking;

  @override
  State<_AwardCelebration> createState() => _AwardCelebrationState();
}

class _AwardCelebrationState extends State<_AwardCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isLargeDisplay = _isLargeDisplay(context);
    final dialogWidth = isLargeDisplay
        ? math.min(screenSize.width * 0.76, 720.0)
        : math.min(screenSize.width - 32, 340.0);
    final horizontalPadding = isLargeDisplay ? 40.0 : 24.0;
    final contentWidth = dialogWidth - (horizontalPadding * 2);
    final recipientWidth = isLargeDisplay ? 138.0 : 104.0;
    final recipientGap = isLargeDisplay ? 18.0 : 12.0;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final pulse = 1 + (_controller.value * 0.08);
            return GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: dialogWidth,
                constraints: BoxConstraints(maxHeight: screenSize.height * 0.9),
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  isLargeDisplay ? 38 : 30,
                  horizontalPadding,
                  isLargeDisplay ? 34 : 24,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 28,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(
                        scale: pulse,
                        child: Image.asset(
                          widget.achievement.asset,
                          width: isLargeDisplay ? 250 : 172,
                          height: isLargeDisplay ? 250 : 172,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Συγχαρητήρια!',
                        style: TextStyle(
                          color: Color(0xFF173A8A),
                          fontSize: isLargeDisplay ? 38 : 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: isLargeDisplay ? 174 : 128,
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.symmetric(
                            horizontal: math.max(
                              0,
                              (contentWidth -
                                      (widget.recipients.length *
                                          recipientWidth) -
                                      ((widget.recipients.length - 1) *
                                          recipientGap)) /
                                  2,
                            ),
                          ),
                          scrollDirection: Axis.horizontal,
                          itemCount: widget.recipients.length,
                          separatorBuilder: (_, _) =>
                              SizedBox(width: recipientGap),
                          itemBuilder: (context, index) {
                            final student = widget.recipients[index];
                            return SizedBox(
                              width: recipientWidth,
                              child: Column(
                                children: [
                                  SizedBox(
                                    width: isLargeDisplay ? 122 : 88,
                                    height: isLargeDisplay ? 122 : 88,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFFFD43B),
                                        shape: BoxShape.circle,
                                      ),
                                      child: _StudentAvatar(student: student),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    student.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFF173A8A),
                                      fontSize: isLargeDisplay ? 18 : 13,
                                      fontWeight: FontWeight.w900,
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(height: 30),
                      Text(
                        'Κατάταξη',
                        style: TextStyle(
                          color: Color(0xFF173A8A),
                          fontSize: isLargeDisplay ? 28 : 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final entry in widget.ranking) ...[
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isLargeDisplay ? 17 : 11,
                            vertical: isLargeDisplay ? 13 : 9,
                          ),
                          decoration: BoxDecoration(
                            color:
                                widget.recipients.any(
                                  (student) => student.id == entry.studentId,
                                )
                                ? const Color(0xFFFFF5C7)
                                : const Color(0xFFF7F8FC),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: isLargeDisplay ? 23 : 16,
                                backgroundColor: _rankColor(entry.position),
                                foregroundColor: const Color(0xFF173A8A),
                                child: Text(
                                  '${entry.position}',
                                  style: TextStyle(
                                    fontSize: isLargeDisplay ? 18 : 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  entry.studentName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Color(0xFF173A8A),
                                    fontSize: isLargeDisplay ? 19 : 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Text(
                                'x ${entry.count}',
                                style: TextStyle(
                                  color: Color(0xFF173A8A),
                                  fontSize: isLargeDisplay ? 20 : 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CompletionCard extends StatelessWidget {
  const _CompletionCard({required this.onRestart});

  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        children: [
          const Icon(
            Icons.celebration_rounded,
            size: 88,
            color: Color(0xFFCFB010),
          ),
          const SizedBox(height: 16),
          const Text(
            'Η απονομή ολοκληρώθηκε!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF173A8A),
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRestart,
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Νέα απονομή'),
          ),
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: child,
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        children: [
          const Icon(Icons.info_outline_rounded, size: 44),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Δοκιμή ξανά')),
          ],
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
    name: row['name']?.toString().trim() ?? '',
    language: row['language']?.toString().trim() ?? '',
    daysHours: row['days_hours']?.toString().trim() ?? '',
  );

  final String id;
  final String name;
  final String language;
  final String daysHours;

  String get title =>
      [name, language, daysHours].where((part) => part.isNotEmpty).join(' · ');
}

class _Student {
  const _Student({required this.id, required this.name, this.profilePic});

  factory _Student.fromRow(Map<String, dynamic> row) => _Student(
    id: row['student_id']?.toString() ?? '',
    name: row['student_name']?.toString().trim().isNotEmpty == true
        ? row['student_name'].toString().trim()
        : 'Μαθητής',
    profilePic: row['profile_pic']?.toString().trim().isNotEmpty == true
        ? row['profile_pic'].toString().trim()
        : null,
  );

  final String id;
  final String name;
  final String? profilePic;
}

class _RankingEntry {
  const _RankingEntry({
    required this.studentId,
    required this.studentName,
    required this.count,
    required this.position,
  });

  factory _RankingEntry.fromRow(Map<String, dynamic> row) => _RankingEntry(
    studentId: row['ranking_student_id']?.toString() ?? '',
    studentName:
        row['ranking_student_name']?.toString().trim().isNotEmpty == true
        ? row['ranking_student_name'].toString().trim()
        : 'Μαθητής',
    count: _readInt(row['achievement_count']),
    position: _readInt(row['rank_position'], fallback: 1),
  );

  final String studentId;
  final String studentName;
  final int count;
  final int position;
}

class _AchievementDefinition {
  const _AchievementDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.asset,
    required this.allowsMultiple,
  });

  final String id;
  final String label;
  final String description;
  final String asset;
  final bool allowsMultiple;
}

const _awardOrder = [
  _AchievementDefinition(
    id: 'try',
    label: 'Προσπάθεια',
    description: 'Οι μαθητές που προσπάθησαν περισσότερο σήμερα.',
    asset: 'lib/img/try.png',
    allowsMultiple: true,
  ),
  _AchievementDefinition(
    id: 'dictation',
    label: 'Ορθογραφία',
    description: 'Ποιοι μαθητές τα πήγαν καλά στην ορθογραφία τους;',
    asset: 'lib/img/dictation.png',
    allowsMultiple: true,
  ),
  _AchievementDefinition(
    id: 'participation',
    label: 'Συμμετοχή',
    description: 'Ποιοι μαθητές συμμετείχαν περισσότερο στην τάξη;',
    asset: 'lib/img/participation.png',
    allowsMultiple: true,
  ),
  _AchievementDefinition(
    id: 'quiet',
    label: 'Ο πιο ήσυχος',
    description: 'Οι πιο φρόνιμοι μαθητές στην τάξη.',
    asset: 'lib/img/quiet.png',
    allowsMultiple: true,
  ),
  _AchievementDefinition(
    id: 'reading',
    label: 'Ανάγνωση',
    description:
        'Ποιοι κατέβαλαν τη μεγαλύτερη προσπάθεια σήμερα και έκαναν τα λιγότερα λάθη;',
    asset: 'lib/img/reading.png',
    allowsMultiple: true,
  ),
  _AchievementDefinition(
    id: 'speaking',
    label: 'Προφορικός λόγος',
    description: 'Ποιοι μίλησαν περισσότερο στα αγγλικά στην τάξη;',
    asset: 'lib/img/speaking.png',
    allowsMultiple: true,
  ),
  _AchievementDefinition(
    id: 'vocabulary',
    label: 'Λεξιλόγιο',
    description:
        'Ποιοι διάβασαν καλύτερα το λεξιλόγιο και το χρησιμοποίησαν στην τάξη;',
    asset: 'lib/img/vocabulary.png',
    allowsMultiple: true,
  ),
  _AchievementDefinition(
    id: 'grammar',
    label: 'Γραμματική',
    description: 'Ποιοι θυμούνταν και χρησιμοποίησαν καλύτερα τη γραμματική;',
    asset: 'lib/img/grammar.png',
    allowsMultiple: true,
  ),
];

bool _isJuniorClass(String name) =>
    RegExp(r'^(JA|JB|SA|SB)').hasMatch(name.trim().toUpperCase());

bool _isLargeDisplay(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= 600;

Color _rankColor(int position) => switch (position) {
  1 => const Color(0xFFFFC928),
  2 => const Color(0xFFB7C2D0),
  3 => const Color(0xFFD9955B),
  _ => const Color(0xFFE7E9F2),
};

int _readInt(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
