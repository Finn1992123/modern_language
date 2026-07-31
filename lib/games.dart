import 'package:flutter/material.dart';

import 'hangman.dart';
import 'identify_the_tense.dart';
import 'reader.dart';
import 'studyyourgram.dart';
import 'studyyourvoc.dart';

class GamesPage extends StatelessWidget {
  const GamesPage({
    super.key,
    required this.studentId,
    required this.classId,
    required this.languageLabel,
  });

  final String studentId;
  final String classId;
  final String languageLabel;

  static const Color _headerColor = Color(0xFF4D4AAD);
  static const Color _contentColor = Color(0xFF18A8EF);

  void _openStudyYourVoc(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => StudyYourVocPage(
          studentId: studentId,
          classId: classId,
          languageLabel: languageLabel,
        ),
      ),
    );
  }

  void _openHangman(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => HangmanHomePage(languageLabel: languageLabel),
      ),
    );
  }

  void _openIdentifyTheTense(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            IdentifyTheTenseHomePage(studentId: studentId, classId: classId),
      ),
    );
  }

  void _openStudyYourGram(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            StudyYourGramPage(studentId: studentId, classId: classId),
      ),
    );
  }

  void _openReader(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            ReaderPage(studentId: studentId, classId: classId),
      ),
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
                          'Παιχνίδια',
                          style: TextStyle(
                            color: _contentColor,
                            fontSize: 31,
                            fontWeight: FontWeight.w800,
                            height: 1.08,
                          ),
                        ),
                        SizedBox(height: 12),
                        Icon(
                          Icons.sports_esports_rounded,
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
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
              children: [
                _GameCard(
                  title: 'Reader',
                  subtitle: 'Διάβασε το κείμενο και εντόπισε την απάντηση',
                  icon: Icons.auto_stories_rounded,
                  imageAsset: 'lib/img/reader.png',
                  imagePadding: 0,
                  backgroundColor: const Color(0xFFEAF7FF),
                  contentColor: _headerColor,
                  featured: true,
                  onTap: () => _openReader(context),
                ),
                const SizedBox(height: 14),
                _GameCard(
                  title: 'Study your voc',
                  subtitle: 'Μελέτη λεξιλογίου',
                  icon: Icons.style_rounded,
                  imageAsset: 'lib/img/studyyourvoc.png',
                  imagePadding: 0,
                  backgroundColor: const Color(0xFFEAF7FF),
                  contentColor: _headerColor,
                  featured: true,
                  onTap: () => _openStudyYourVoc(context),
                ),
                const SizedBox(height: 14),
                _GameCard(
                  title: 'Identify the tense',
                  subtitle: 'Αναγνώρισε τον σωστό χρόνο της πρότασης',
                  icon: Icons.schedule_rounded,
                  imageAsset: 'lib/img/identifythetense.png',
                  imagePadding: 0,
                  backgroundColor: const Color(0xFFEAF7FF),
                  contentColor: _headerColor,
                  featured: true,
                  onTap: () => _openIdentifyTheTense(context),
                ),
                const SizedBox(height: 14),
                _GameCard(
                  title: 'Study your gram',
                  subtitle: 'Εξάσκηση γραμματικής με θεωρία και παραδείγματα',
                  icon: Icons.menu_book_rounded,
                  imageAsset: 'lib/img/studyyourgram.png',
                  imagePadding: 0,
                  backgroundColor: const Color(0xFFEAF7FF),
                  contentColor: _headerColor,
                  featured: true,
                  onTap: () => _openStudyYourGram(context),
                ),
                const SizedBox(height: 14),
                _GameCard(
                  title: 'Κρεμάλα',
                  subtitle: 'Βρες τη λέξη πριν ολοκληρωθεί η κρεμάλα',
                  icon: Icons.sports_esports_rounded,
                  imageAsset: 'lib/img/hangmanicon.png',
                  imagePadding: 0,
                  imageScale: 1.3,
                  backgroundColor: const Color(0xFFEAF7FF),
                  contentColor: _headerColor,
                  onTap: () => _openHangman(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.imageAsset,
    this.imagePadding = 8,
    this.imageScale = 1,
    this.featured = false,
    required this.backgroundColor,
    required this.contentColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String? imageAsset;
  final double imagePadding;
  final double imageScale;
  final bool featured;
  final Color backgroundColor;
  final Color contentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: contentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: imageAsset == null
                    ? Icon(icon, color: contentColor, size: 34)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Padding(
                          padding: EdgeInsets.all(imagePadding),
                          child: Transform.scale(
                            scale: imageScale,
                            alignment: Alignment.center,
                            child: Image.asset(
                              imageAsset!,
                              fit: BoxFit.cover,
                              alignment: Alignment.center,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: contentColor,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (featured) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFFFC107),
                            size: 27,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: contentColor.withValues(alpha: 0.76),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: contentColor, size: 34),
            ],
          ),
        ),
      ),
    );
  }
}
