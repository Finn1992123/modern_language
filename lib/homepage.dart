import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'announcements.dart';
import 'games.dart';
import 'library.dart';
import 'payments.dart';
import 'profile.dart';
import 'students_menu.dart';
import 'teachers_menu.dart';

const double _homeCardRadius = 28;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late Future<_UserHomeData> _userDataFuture = _loadUserData();

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
        .select('id, name, gender, profile_pic')
        .eq('user_id', userRow['id']);

    final name = userRow['name'];
    final role = userRow['role'];

    return _UserHomeData(
      name: name is String && name.trim().isNotEmpty ? name.trim() : 'χρήστη',
      role: role is String ? role.trim().toLowerCase() : null,
      profilePic: _readOptionalText(userRow['profile_pic']),
      students: studentRows.map(_StudentData.fromRow).toList(),
    );
  }

  void _openPayments() {
    _openMenuPage(const PaymentsPage(), refreshOnReturn: false);
  }

  void _openLibrary() {
    _openMenuPage(const LibraryPage(), refreshOnReturn: false);
  }

  void _openAnnouncements() {
    _openMenuPage(const AnnouncementsPage(), refreshOnReturn: false);
  }

  void _openGames() {
    _openMenuPage(const GamesPage(), refreshOnReturn: false);
  }

  void _openProfile() {
    _openMenuPage(const ProfilePage());
  }

  void _openTeachersMenu() {
    _openMenuPage(const TeachersMenuPage(), refreshOnReturn: false);
  }

  Future<void> _openMenuPage(Widget page, {bool refreshOnReturn = true}) async {
    await Navigator.of(context).push(
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

    if (!mounted || !refreshOnReturn) {
      return;
    }

    setState(() {
      _userDataFuture = _loadUserData();
    });
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
                        const Icon(Icons.error_outline_rounded, size: 42),
                        const SizedBox(height: 12),
                        const Text(
                          'Δεν μπορέσαμε να φορτώσουμε τα στοιχεία σου.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () {
                            setState(() {
                              _userDataFuture = _loadUserData();
                            });
                          },
                          child: const Text('Δοκιμή ξανά'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final userData = snapshot.data ?? const _UserHomeData();
              final showTeacherMenu =
                  userData.role == 'teacher' || userData.role == 'headteacher';

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
                      ProfilePhotoButton(
                        imageUrl: userData.profilePic,
                        onTap: _openProfile,
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
                        index: 1,
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
                        index: 2,
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
                        index: 3,
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
                        child: _TeacherMenuCard(onTap: _openTeachersMenu),
                      ),
                    ),
                  ],
                  if (userData.students.isNotEmpty) ...[
                    const SizedBox(height: 14),
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
          borderRadius: BorderRadius.circular(_homeCardRadius),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(_homeCardRadius),
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
  const _TeacherMenuCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const contentColor = Color(0xFF5AFF87);

    return SizedBox(
      width: 350,
      height: 122,
      child: Material(
        color: const Color(0xFF627DE4),
        borderRadius: BorderRadius.circular(_homeCardRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(_homeCardRadius),
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
      ),
    );
  }
}

class _StudentsPageView extends StatefulWidget {
  const _StudentsPageView({required this.students});

  final List<_StudentData> students;

  @override
  State<_StudentsPageView> createState() => _StudentsPageViewState();
}

class _StudentsPageViewState extends State<_StudentsPageView> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    if (index < 0 || index >= widget.students.length) {
      return;
    }

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = _currentIndex > 0;
    final canGoForward = _currentIndex < widget.students.length - 1;

    return SizedBox(
      height: 306,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.students.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 42),
                child: _StudentPage(student: widget.students[index]),
              );
            },
          ),
          if (canGoBack)
            Positioned(
              left: 0,
              top: 96,
              child: _StudentCarouselArrow(
                icon: Icons.chevron_left_rounded,
                onTap: () => _goToPage(_currentIndex - 1),
              ),
            ),
          if (canGoForward)
            Positioned(
              right: 0,
              top: 96,
              child: _StudentCarouselArrow(
                icon: Icons.chevron_right_rounded,
                onTap: () => _goToPage(_currentIndex + 1),
              ),
            ),
        ],
      ),
    );
  }
}

class _StudentCarouselArrow extends StatelessWidget {
  const _StudentCarouselArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.44),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: const Color(0xFF173A8A), size: 34),
        ),
      ),
    );
  }
}

class _StudentPage extends StatelessWidget {
  const _StudentPage({required this.student});

  final _StudentData student;

  void _openStudentsMenu(BuildContext context, Color textColor) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => StudentsMenuPage(
          studentId: student.id,
          studentName: student.name,
          profilePic: student.profilePic,
          heroTag: student.heroTag,
          accentColor: textColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFemale = student.gender == 'f';
    final textColor = isFemale
        ? const Color.fromARGB(255, 235, 93, 150)
        : const Color(0xFF173A8A);
    final article = isFemale ? '\u03C4\u03B7\u03BD' : '\u03C4\u03BF\u03BD';

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Hero(
              tag: student.heroTag,
              child: CrownedProfilePhoto(imageUrl: student.profilePic),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Material(
          color: Colors.white.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(36),
          child: InkWell(
            onTap: () => _openStudentsMenu(context, textColor),
            borderRadius: BorderRadius.circular(36),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(36),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.55),
                  width: 1.2,
                ),
              ),
              child: Text(
                '\u03A0\u03B1\u03C4\u03AE\u03C3\u03C4\u03B5 \u03B3\u03B9\u03B1 $article ${student.name}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
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
    this.profilePic,
    this.students = const [],
  });

  final String name;
  final String? role;
  final String? profilePic;
  final List<_StudentData> students;
}

class _StudentData {
  const _StudentData({
    required this.id,
    required this.name,
    required this.gender,
    this.profilePic,
  });

  factory _StudentData.fromRow(Map<String, dynamic> row) {
    final id = row['id'];
    final name = row['name'];
    final gender = row['gender'];

    return _StudentData(
      id: id is String ? id : '',
      name: name is String && name.trim().isNotEmpty ? name.trim() : 'μαθητή',
      gender: gender is String ? gender.trim().toLowerCase() : 'm',
      profilePic: _readOptionalText(row['profile_pic']),
    );
  }

  final String id;
  final String name;
  final String gender;
  final String? profilePic;

  String get heroTag =>
      id.isEmpty ? 'student-profile-$gender-$name' : 'student-profile-$id';
}

String? _readOptionalText(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }

  return null;
}
