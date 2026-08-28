import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ArticleDetailsData {
  const ArticleDetailsData({
    required this.id,
    required this.title,
    required this.summary,
    required this.legacyText,
    required this.coverImageUrl,
    required this.ageLabel,
    required this.important,
  });

  final String id;
  final String title;
  final String? summary;
  final String? legacyText;
  final String? coverImageUrl;
  final String ageLabel;
  final bool important;
}

class ArticleDetailsPage extends StatefulWidget {
  const ArticleDetailsPage({super.key, required this.article});

  final ArticleDetailsData article;

  @override
  State<ArticleDetailsPage> createState() => _ArticleDetailsPageState();
}

class _ArticleDetailsPageState extends State<ArticleDetailsPage> {
  static const _blue = Color(0xFF385DC9);

  late final Future<List<_ArticleSection>> _sectionsFuture;
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _sectionKeys = [];
  double _readingProgress = 0;

  @override
  void initState() {
    super.initState();
    _sectionsFuture = _loadSections();
    _scrollController.addListener(_updateReadingProgress);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateReadingProgress)
      ..dispose();
    super.dispose();
  }

  Future<List<_ArticleSection>> _loadSections() async {
    try {
      final rows = await Supabase.instance.client
          .from('article_sections')
          .select('id, title, body, image_url, sort_order')
          .eq('article_id', widget.article.id)
          .order('sort_order', ascending: true)
          .order('created_at', ascending: true);

      return rows
          .map((row) => _ArticleSection.fromRow(Map<String, dynamic>.from(row)))
          .toList();
    } catch (_) {
      // Keeps articles readable while the new migration is being deployed.
      return const [];
    }
  }

  List<_ArticleSection> _withLegacyFallback(List<_ArticleSection> sections) {
    if (sections.isNotEmpty) {
      return sections;
    }

    final legacyText = widget.article.legacyText?.trim();
    if (legacyText == null || legacyText.isEmpty) {
      return const [];
    }

    return [
      _ArticleSection(
        id: 'legacy',
        title: 'Το άρθρο',
        body: legacyText,
        imageUrl: null,
        sortOrder: 1,
      ),
    ];
  }

  void _updateReadingProgress() {
    if (!_scrollController.hasClients) {
      return;
    }

    final position = _scrollController.position;
    final progress = position.maxScrollExtent == 0
        ? 0.0
        : (position.pixels / position.maxScrollExtent).clamp(0.0, 1.0);

    if ((progress - _readingProgress).abs() > 0.01 && mounted) {
      setState(() => _readingProgress = progress);
    }
  }

  void _prepareSectionKeys(int count) {
    while (_sectionKeys.length < count) {
      _sectionKeys.add(GlobalKey());
    }
  }

  Future<void> _goToSection(int index) async {
    if (index < 0 || index >= _sectionKeys.length) {
      return;
    }

    final sectionContext = _sectionKeys[index].currentContext;
    if (sectionContext == null) {
      return;
    }

    await Scrollable.ensureVisible(
      sectionContext,
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeInOutCubic,
      alignment: 0.08,
    );
  }

  void _showContents(List<_ArticleSection> sections) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                const Text(
                  'Περιεχόμενα',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                for (var index = 0; index < sections.length; index++)
                  _ContentsTile(
                    number: index + 1,
                    title: sections[index].title,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _goToSection(index),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_ArticleSection>>(
      future: _sectionsFuture,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState != ConnectionState.done;
        final sections = _withLegacyFallback(snapshot.data ?? const []);
        _prepareSectionKeys(sections.length);

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFF),
          floatingActionButton: sections.length > 1
              ? FloatingActionButton.extended(
                  onPressed: () => _showContents(sections),
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.format_list_numbered_rounded),
                  label: const Text(
                    'Περιεχόμενα',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                )
              : null,
          body: Stack(
            children: [
              CustomScrollView(
                controller: _scrollController,
                slivers: [
                  _ArticleHeader(article: widget.article),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 110),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.article.summary case final summary?) ...[
                            _SummaryCard(summary: summary),
                            const SizedBox(height: 22),
                          ],
                          if (sections.length > 1) ...[
                            _ContentsCard(
                              sections: sections,
                              onSelected: _goToSection,
                            ),
                            const SizedBox(height: 28),
                          ],
                          if (isLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 54),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (sections.isEmpty)
                            const _EmptyArticle()
                          else
                            for (
                              var index = 0;
                              index < sections.length;
                              index++
                            ) ...[
                              _SectionCard(
                                key: _sectionKeys[index],
                                section: sections[index],
                                number: index + 1,
                              ),
                              if (index != sections.length - 1)
                                const SizedBox(height: 24),
                            ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: SafeArea(
                  bottom: false,
                  child: LinearProgressIndicator(
                    value: _readingProgress,
                    minHeight: 3,
                    color: _blue,
                    backgroundColor: Colors.transparent,
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

class _ArticleHeader extends StatelessWidget {
  const _ArticleHeader({required this.article});

  final ArticleDetailsData article;

  @override
  Widget build(BuildContext context) {
    final imageUrl = article.coverImageUrl;

    return SliverAppBar(
      expandedHeight: imageUrl == null ? 260 : 390,
      pinned: true,
      stretch: true,
      backgroundColor: const Color(0xFF89ACFF),
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl == null)
              const ColoredBox(
                color: Color(0xFF89ACFF),
                child: Icon(
                  Icons.article_rounded,
                  color: Color(0xFF385DC9),
                  size: 96,
                ),
              )
            else
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const ColoredBox(
                    color: Color(0xFF89ACFF),
                    child: Icon(
                      Icons.article_rounded,
                      color: Color(0xFF385DC9),
                      size: 96,
                    ),
                  );
                },
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xD9000000)],
                  stops: [0.35, 1],
                ),
              ),
            ),
            Positioned(
              left: 22,
              right: 22,
              bottom: 28,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (article.ageLabel.isNotEmpty)
                        _HeaderPill(
                          icon: Icons.people_alt_rounded,
                          text: article.ageLabel,
                        ),
                      if (article.important)
                        const _HeaderPill(
                          icon: Icons.star_rounded,
                          text: 'Σημαντικό',
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    article.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                      shadows: [Shadow(blurRadius: 12, color: Colors.black54)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: const Color(0xFF385DC9)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF385DC9),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final String summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3FF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDCE5FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.format_quote_rounded,
            color: Color(0xFF385DC9),
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              summary,
              style: const TextStyle(
                color: Color(0xFF454C59),
                fontSize: 17,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentsCard extends StatelessWidget {
  const _ContentsCard({required this.sections, required this.onSelected});

  final List<_ArticleSection> sections;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF385DC9).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.format_list_numbered_rounded,
                color: Color(0xFF385DC9),
              ),
              SizedBox(width: 10),
              Text(
                'Περιεχόμενα',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < sections.length; index++)
            _ContentsTile(
              number: index + 1,
              title: sections[index].title,
              onTap: () => onSelected(index),
            ),
        ],
      ),
    );
  }
}

class _ContentsTile extends StatelessWidget {
  const _ContentsTile({
    required this.number,
    required this.title,
    required this.onTap,
  });

  final int number;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFFEFF3FF),
                shape: BoxShape.circle,
              ),
              child: Text(
                '$number',
                style: const TextStyle(
                  color: Color(0xFF385DC9),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF343A46),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(
              Icons.arrow_downward_rounded,
              size: 19,
              color: Color(0xFF8B94A7),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({super.key, required this.section, required this.number});

  final _ArticleSection section;
  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE5EAF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (section.imageUrl case final imageUrl?)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const ColoredBox(
                    color: Color(0xFFEFF3FF),
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: Color(0xFF8295CE),
                      size: 46,
                    ),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ΚΕΦΑΛΑΙΟ $number',
                  style: const TextStyle(
                    color: Color(0xFF6E86D4),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  section.title,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
                if (section.body case final body?) ...[
                  const SizedBox(height: 18),
                  _ArticleBody(body: body),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArticleBody extends StatelessWidget {
  const _ArticleBody({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    final lines = body.replaceAll('\r\n', '\n').split('\n');
    final widgets = <Widget>[];
    final paragraph = <String>[];

    void flushParagraph() {
      if (paragraph.isEmpty) {
        return;
      }
      widgets.add(
        SelectableText.rich(
          TextSpan(
            children: _inlineSpans(
              paragraph.join(' ').trim(),
              const TextStyle(
                color: Color(0xFF515866),
                fontSize: 16.5,
                fontWeight: FontWeight.w500,
                height: 1.62,
              ),
            ),
          ),
          style: const TextStyle(
            color: Color(0xFF515866),
            fontSize: 16.5,
            fontWeight: FontWeight.w500,
            height: 1.62,
          ),
        ),
      );
      paragraph.clear();
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        flushParagraph();
        continue;
      }

      final image = _bodyImageFromMarkdown(line);
      if (image != null) {
        flushParagraph();
        widgets.add(_BodyImage(imageUrl: image.url, caption: image.caption));
      } else if (line.startsWith('## ')) {
        flushParagraph();
        widgets.add(
          Text(
            line.substring(3).trim(),
            style: const TextStyle(
              color: Color(0xFF303744),
              fontSize: 20,
              fontWeight: FontWeight.w900,
              height: 1.25,
            ),
          ),
        );
      } else if (line.startsWith('- ') || line.startsWith('• ')) {
        flushParagraph();
        widgets.add(_BulletText(text: line.substring(2).trim()));
      } else {
        paragraph.add(line);
      }
    }
    flushParagraph();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < widgets.length; index++) ...[
          widgets[index],
          if (index != widgets.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _BulletText extends StatelessWidget {
  const _BulletText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Icon(Icons.circle, size: 7, color: Color(0xFF385DC9)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: SelectableText.rich(
            TextSpan(
              children: _inlineSpans(
                text,
                const TextStyle(
                  color: Color(0xFF515866),
                  fontSize: 16.5,
                  fontWeight: FontWeight.w500,
                  height: 1.55,
                ),
              ),
            ),
            style: const TextStyle(
              color: Color(0xFF515866),
              fontSize: 16.5,
              fontWeight: FontWeight.w500,
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }
}

class _BodyImage extends StatelessWidget {
  const _BodyImage({required this.imageUrl, required this.caption});

  final String imageUrl;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.network(
            imageUrl,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) {
                return child;
              }

              final expectedBytes = loadingProgress.expectedTotalBytes;
              final progress = expectedBytes == null
                  ? null
                  : loadingProgress.cumulativeBytesLoaded / expectedBytes;

              return Container(
                height: 190,
                alignment: Alignment.center,
                color: const Color(0xFFEFF3FF),
                child: CircularProgressIndicator(value: progress),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                height: 180,
                alignment: Alignment.center,
                color: const Color(0xFFEFF3FF),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.broken_image_outlined,
                      color: Color(0xFF8295CE),
                      size: 44,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Η εικόνα δεν είναι διαθέσιμη',
                      style: TextStyle(
                        color: Color(0xFF6F7C9F),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (caption case final caption?) ...[
          const SizedBox(height: 8),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF7A8291),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

_MarkdownBodyImage? _bodyImageFromMarkdown(String line) {
  final match = RegExp(r'^!\[(.*)\]\((https?://.+)\)$').firstMatch(line);
  if (match == null) {
    return null;
  }

  final caption = match.group(1)?.trim();
  final url = match.group(2)?.trim();
  if (url == null || Uri.tryParse(url)?.hasAbsolutePath != true) {
    return null;
  }

  return _MarkdownBodyImage(
    url: url,
    caption: caption == null || caption.isEmpty ? null : caption,
  );
}

class _MarkdownBodyImage {
  const _MarkdownBodyImage({required this.url, required this.caption});

  final String url;
  final String? caption;
}

List<InlineSpan> _inlineSpans(String text, TextStyle baseStyle) {
  final boldPattern = RegExp(r'\*\*(.+?)\*\*');
  final spans = <InlineSpan>[];
  var currentIndex = 0;

  for (final match in boldPattern.allMatches(text)) {
    if (match.start > currentIndex) {
      spans.add(TextSpan(text: text.substring(currentIndex, match.start)));
    }

    spans.add(
      TextSpan(
        text: match.group(1),
        style: baseStyle.copyWith(
          color: const Color(0xFF252B36),
          fontWeight: FontWeight.w900,
          letterSpacing: 0.08,
          shadows: const [
            Shadow(color: Color(0x55252B36), offset: Offset(0.2, 0)),
          ],
        ),
      ),
    );
    currentIndex = match.end;
  }

  if (currentIndex < text.length) {
    spans.add(TextSpan(text: text.substring(currentIndex)));
  }

  return spans.isEmpty ? [TextSpan(text: text)] : spans;
}

class _EmptyArticle extends StatelessWidget {
  const _EmptyArticle();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 54),
      child: Column(
        children: [
          Icon(Icons.menu_book_outlined, color: Color(0xFF8295CE), size: 58),
          SizedBox(height: 14),
          Text(
            'Το περιεχόμενο του άρθρου θα προστεθεί σύντομα.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF757D8D),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArticleSection {
  const _ArticleSection({
    required this.id,
    required this.title,
    required this.body,
    required this.imageUrl,
    required this.sortOrder,
  });

  factory _ArticleSection.fromRow(Map<String, dynamic> row) {
    return _ArticleSection(
      id: row['id']?.toString() ?? '',
      title: _nullableText(row['title']) ?? 'Κεφάλαιο',
      body: _nullableText(row['body']),
      imageUrl: _nullableText(row['image_url']),
      sortOrder: _readInt(row['sort_order']) ?? 0,
    );
  }

  final String id;
  final String title;
  final String? body;
  final String? imageUrl;
  final int sortOrder;
}

String? _nullableText(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _readInt(dynamic value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '');
}
