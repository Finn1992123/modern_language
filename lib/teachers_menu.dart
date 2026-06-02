import 'package:flutter/material.dart';

import 'studentscurriculum.dart';
import 'teacher_classes_page.dart';
import 'teacher_payments.dart';

class TeachersMenuPage extends StatelessWidget {
  const TeachersMenuPage({super.key});

  static const Color _contentColor = Color(0xFF173A8A);

  void _openPage(BuildContext context, Widget page) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (context) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
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
            const SizedBox(height: 8),
            const Text(
              'Μενού Καθηγητών',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _contentColor,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                height: 1.08,
              ),
            ),
            const SizedBox(height: 22),
            _TeacherMenuButton(
              label: 'Οι τάξεις μου',
              icon: Icons.school_rounded,
              color: const Color(0xFF627DE4),
              onTap: () => _openPage(context, const TeacherClassesPage()),
            ),
            const SizedBox(height: 12),
            _TeacherMenuButton(
              label: 'Πληρωμές',
              icon: Icons.savings_rounded,
              color: const Color(0xFFDB9538),
              onTap: () => _openPage(context, const TeacherPaymentsPage()),
            ),
            const SizedBox(height: 12),
            _TeacherMenuButton(
              label: 'Τα καθήκοντα',
              icon: Icons.assignment_rounded,
              color: const Color(0xFF385DC9),
              onTap: () => _openPage(context, const StudentsCurriculumPage()),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeacherMenuButton extends StatelessWidget {
  const _TeacherMenuButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 15),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
    );
  }
}
