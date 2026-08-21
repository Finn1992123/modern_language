import 'package:flutter/material.dart';

import 'hangman.dart';
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
        builder: (context) => HangmanHomePage(
          studentId: studentId,
          classId: classId,
          languageLabel: languageLabel,
        ),
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
                const SizedBox(height: 14),
                _GameCard(
                  title: 'Reader',
                  subtitle: 'Διάβασε το κείμενο και εντόπισε την απάντηση',
                  icon: Icons.auto_stories_rounded,
                  imageAsset: 'lib/img/reader.png',
                  imagePadding: 0,
                  backgroundColor: const Color(0xFFEAF7FF),
                  contentColor: _headerColor,
                  featured: true,
                  locked: true,
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
                  locked: true,
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
                  locked: true,
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
    this.locked = false,
    required this.backgroundColor,
    required this.contentColor,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String? imageAsset;
  final double imagePadding;
  final double imageScale;
  final bool featured;
  final bool locked;
  final Color backgroundColor;
  final Color contentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cardColor = locked ? const Color(0xFFE9EBEF) : backgroundColor;
    final textColor = locked ? const Color(0xFF7C828D) : contentColor;
    final image = imageAsset == null
        ? Icon(icon, color: textColor, size: 34)
        : ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: EdgeInsets.all(imagePadding),
              child: Transform.scale(
                scale: imageScale,
                alignment: Alignment.center,
                child: ColorFiltered(
                  colorFilter: locked
                      ? const ColorFilter.matrix(<double>[
                          0.2126,
                          0.7152,
                          0.0722,
                          0,
                          0,
                          0.2126,
                          0.7152,
                          0.0722,
                          0,
                          0,
                          0.2126,
                          0.7152,
                          0.0722,
                          0,
                          0,
                          0,
                          0,
                          0,
                          0.58,
                          0,
                        ])
                      : const ColorFilter.mode(
                          Colors.transparent,
                          BlendMode.dst,
                        ),
                  child: Image.asset(
                    imageAsset!,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
              ),
            ),
          );

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: locked ? null : onTap,
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: textColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: image,
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
                                  color: textColor,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (featured && !locked) ...[
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
                            color: textColor.withValues(alpha: 0.76),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 34,
                    child: locked
                        ? null
                        : Icon(
                            Icons.chevron_right_rounded,
                            color: textColor,
                            size: 34,
                          ),
                  ),
                ],
              ),
            ),
            if (locked)
              Positioned(
                top: 9,
                right: 10,
                child: Container(
                  width: 29,
                  height: 29,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4D7DD),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: Color(0xFF666C76),
                    size: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
