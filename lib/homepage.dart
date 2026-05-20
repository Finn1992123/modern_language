import 'package:flutter/material.dart';
import 'package:rive/rive.dart' show RiveAnimation;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'announcements.dart';
import 'games.dart';
import 'library.dart';
import 'payments.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Future<_UserHomeData> _userDataFuture = _loadUserData();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<_UserHomeData> _loadUserData() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      return const _UserHomeData();
    }

    final userRow = await _loadLinkedUserRow();

    if (userRow == null) {
      return const _UserHomeData();
    }

    final studentRows = await supabase
        .from('students')
        .select('name, gender')
        .eq('user_id', userRow['id']);

    final name = userRow['name'];
    final role = userRow['role'];

    return _UserHomeData(
      name: name is String && name.trim().isNotEmpty ? name.trim() : 'χρήστη',
      role: role is String ? role.trim().toLowerCase() : null,
      students: studentRows.map(_StudentData.fromRow).toList(),
    );
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  void _openPayments() {
    _openMenuPage(const PaymentsPage());
  }

  void _openLibrary() {
    _openMenuPage(const LibraryPage());
  }

  void _openAnnouncements() {
    _openMenuPage(const AnnouncementsPage());
  }

  void _openGames() {
    _openMenuPage(const GamesPage());
  }

  void _openMenuPage(Widget page) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curvedAnimation),
            child: child,
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>?> _loadLinkedUserRow() async {
    final linkedUser = await Supabase.instance.client.rpc(
      'current_linked_user',
    );

    if (linkedUser is Map<String, dynamic>) {
      return linkedUser;
    }

    if (linkedUser is Map) {
      return Map<String, dynamic>.from(linkedUser);
    }

    return null;
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
            stops: [0.3, 1],
          ),
        ),
        child: SafeArea(
          child: FutureBuilder<_UserHomeData>(
            future: _userDataFuture,
            builder: (context, snapshot) {
              final userData = snapshot.data ?? const _UserHomeData();
              final showTeacherMenu =
                  userData.role == 'teacher' || userData.role == 'headteacher';
              final showPayments = !showTeacherMenu;

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Γεια σου, ${userData.name}',
                          style: const TextStyle(
                            fontSize: 29,
                            fontWeight: FontWeight.w800,
                            height: 1.08,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      InkWell(
                        onTap: _signOut,
                        borderRadius: BorderRadius.circular(28),
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            color: Color.fromARGB(255, 164, 205, 225),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            color: Colors.white,
                            size: 52,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 18,
                    crossAxisSpacing: 18,
                    childAspectRatio: 1,
                    children: [
                      if (showPayments)
                        _AnimatedMenuCard(
                          controller: _animationController,
                          index: 0,
                          child: _MenuCard(
                            title: 'Πληρωμές',
                            icon: Icons.savings_rounded,
                            backgroundColor: const Color(0x9FF9FF89),
                            contentColor: const Color(0xFFDB9538),
                            onTap: _openPayments,
                          ),
                        ),
                      _AnimatedMenuCard(
                        controller: _animationController,
                        index: showPayments ? 1 : 0,
                        child: _MenuCard(
                          title: 'Βιβλία/Άρθρα',
                          icon: Icons.menu_book_rounded,
                          backgroundColor: const Color(0xFF89ACFF),
                          contentColor: const Color(0xFF385DC9),
                          onTap: _openLibrary,
                        ),
                      ),
                      _AnimatedMenuCard(
                        controller: _animationController,
                        index: showPayments ? 2 : 1,
                        child: _MenuCard(
                          title: 'Ανακοινώσεις',
                          icon: Icons.campaign_rounded,
                          backgroundColor: const Color(0x9682FE63),
                          contentColor: const Color(0xFF2D7D10),
                          onTap: _openAnnouncements,
                        ),
                      ),
                      _AnimatedMenuCard(
                        controller: _animationController,
                        index: showPayments ? 3 : 2,
                        child: _MenuCard(
                          title: 'Παιχνίδια',
                          icon: Icons.sports_esports_rounded,
                          backgroundColor: const Color(0xFF4D4AAD),
                          contentColor: const Color(0xFF18A8EF),
                          onTap: _openGames,
                        ),
                      ),
                    ],
                  ),
                  if (showTeacherMenu) ...[
                    const SizedBox(height: 22),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _AnimatedMenuCard(
                        controller: _animationController,
                        index: 4,
                        child: const _TeacherMenuCard(),
                      ),
                    ),
                  ],
                  if (userData.students.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _StudentsPageView(students: userData.students),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AnimatedMenuCard extends StatelessWidget {
  const _AnimatedMenuCard({
    required this.controller,
    required this.index,
    required this.child,
  });

  final AnimationController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (index * 0.12).clamp(0.0, 0.72);
    final end = (start + 0.34).clamp(0.0, 1.0);
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-0.35, 0),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.title,
    required this.icon,
    required this.backgroundColor,
    required this.contentColor,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final Color backgroundColor;
  final Color contentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 200,
        height: 200,
        child: Material(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.left,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: contentColor,
                      fontSize: title == 'Ανακοινώσεις' ? 18 : 21,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Icon(icon, color: contentColor, size: 64),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TeacherMenuCard extends StatelessWidget {
  const _TeacherMenuCard();

  @override
  Widget build(BuildContext context) {
    const contentColor = Color(0xFF5AFF87);

    return SizedBox(
      width: 350,
      height: 122,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF627DE4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                'Μενού Καθηγητών',
                textAlign: TextAlign.left,
                style: TextStyle(
                  color: contentColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 8),
              Icon(Icons.co_present_rounded, color: contentColor, size: 48),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudentsPageView extends StatelessWidget {
  const _StudentsPageView({required this.students});

  final List<_StudentData> students;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 440,
      child: PageView.builder(
        itemCount: students.length,
        controller: PageController(viewportFraction: 0.9),
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: _StudentPage(student: students[index]),
          );
        },
      ),
    );
  }
}

class _StudentPage extends StatelessWidget {
  const _StudentPage({required this.student});

  final _StudentData student;

  @override
  Widget build(BuildContext context) {
    final isFemale = student.gender == 'f';
    final asset = isFemale ? 'lib/img/pinkball.riv' : 'lib/img/blueball.riv';
    final textColor = isFemale
        ? const Color(0xFFE91E63)
        : const Color(0xFF173A8A);

    return Column(
      children: [
        Expanded(
          child: RiveAnimation.asset(
            asset,
            fit: BoxFit.contain,
            animations: const ['Bounce'],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.55),
              width: 1.2,
            ),
          ),
          child: Text(
            'Πατήστε για τον ${student.name}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _UserHomeData {
  const _UserHomeData({
    this.name = 'χρήστη',
    this.role,
    this.students = const [],
  });

  final String name;
  final String? role;
  final List<_StudentData> students;
}

class _StudentData {
  const _StudentData({required this.name, required this.gender});

  factory _StudentData.fromRow(Map<String, dynamic> row) {
    final name = row['name'];
    final gender = row['gender'];

    return _StudentData(
      name: name is String && name.trim().isNotEmpty ? name.trim() : 'μαθητή',
      gender: gender is String ? gender.trim().toLowerCase() : 'm',
    );
  }

  final String name;
  final String gender;
}
