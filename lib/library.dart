import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum _LibraryTab { books, articles }

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late Future<List<_Book>> _booksFuture = _loadBooks();
  late final Future<List<_Article>> _articlesFuture = _loadArticles();
  late final TextEditingController _searchController = TextEditingController();

  static const Color _headerColor = Color(0xFF89ACFF);
  static const Color _contentColor = Color(0xFF385DC9);
  static const List<_AgeFilter> _ageFilters = [
    _AgeFilter(label: 'Όλες', minAge: null, maxAge: null),
    _AgeFilter(label: '6-8', minAge: 6, maxAge: 8),
    _AgeFilter(label: '9-12', minAge: 9, maxAge: 12),
    _AgeFilter(label: '13-15', minAge: 13, maxAge: 15),
    _AgeFilter(label: '16-18', minAge: 16, maxAge: 18),
    _AgeFilter(label: '18+', minAge: 18, maxAge: null),
  ];

  _LibraryTab _selectedTab = _LibraryTab.books;
  _AgeFilter _selectedAgeFilter = _ageFilters.first;
  bool _availableOnly = false;
  String _searchText = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<_Book>> _loadBooks() async {
    final rows = await Supabase.instance.client
        .from('books')
        .select(
          'id, title, category, author, min_age, max_age, summary, img, language, level, total_quantity, available_quantity',
        )
        .order('created_at', ascending: false);

    return rows
        .map((row) => _Book.fromRow(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<_Article>> _loadArticles() async {
    final rows = await Supabase.instance.client
        .from('articles')
        .select('title, summary, text, img, min_age, max_age, important')
        .order('created_at', ascending: false);

    return rows
        .map((row) => _Article.fromRow(Map<String, dynamic>.from(row)))
        .toList();
  }

  List<_Book> _filterBooks(List<_Book> books) {
    return books.where((book) {
      final matchesSearch = _matchesSearch([
        book.title,
        book.author,
        book.category,
        book.language,
        book.level,
      ]);
      final matchesAge = _selectedAgeFilter.matches(book.minAge, book.maxAge);
      final matchesAvailability = !_availableOnly || book.availableQuantity > 0;

      return matchesSearch && matchesAge && matchesAvailability;
    }).toList();
  }

  List<_Article> _filterArticles(List<_Article> articles) {
    return articles.where((article) {
      final matchesSearch = _matchesSearch([article.title, article.summary]);
      final matchesAge = _selectedAgeFilter.matches(
        article.minAge,
        article.maxAge,
      );

      return matchesSearch && matchesAge;
    }).toList();
  }

  bool _matchesSearch(List<String?> values) {
    final query = _searchText.trim().toLowerCase();

    if (query.isEmpty) {
      return true;
    }

    return values.any((value) => value?.toLowerCase().contains(query) ?? false);
  }

  void _selectTab(_LibraryTab tab) {
    setState(() {
      _selectedTab = tab;
      _availableOnly = false;
      _selectedAgeFilter = _ageFilters.first;
      _searchText = '';
      _searchController.clear();
    });
  }

  Future<void> _reserveBook(_Book book) async {
    await Supabase.instance.client.rpc(
      'reserve_book',
      params: {'input_book_id': book.id},
    );

    setState(() {
      _booksFuture = _loadBooks();
    });
  }

  void _showBookDialog(_Book book) {
    var isReserving = false;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(horizontal: 22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 660),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: InkWell(
                          onTap: isReserving
                              ? null
                              : () => Navigator.of(dialogContext).pop(),
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
                      if (book.img != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: SizedBox(
                            height: 190,
                            child: Image.network(
                              book.img!,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const _BookDialogIcon();
                              },
                            ),
                          ),
                        ),
                      ] else
                        const Center(child: _BookDialogIcon()),
                      const SizedBox(height: 20),
                      Text(
                        book.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          height: 1.12,
                        ),
                      ),
                      if (book.author != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          book.author!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF737B8B),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 15),
                      _BookInfoPillGroup(
                        book: book,
                        alignment: WrapAlignment.center,
                      ),
                      if (book.summary != null) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.fromLTRB(18, 17, 18, 18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F9FF),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: const Color(0xFFE7ECFA),
                            ),
                          ),
                          child: Text(
                            book.summary!,
                            style: const TextStyle(
                              color: Color(0xFF535A64),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              height: 1.46,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Center(
                        child: _AvailabilityPill(
                          available: book.availableQuantity,
                          total: book.totalQuantity,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: book.availableQuantity <= 0 || isReserving
                            ? null
                            : () async {
                                final navigator = Navigator.of(dialogContext);
                                final messenger = ScaffoldMessenger.of(context);

                                setDialogState(() {
                                  isReserving = true;
                                });

                                try {
                                  await _reserveBook(book);

                                  if (!mounted) {
                                    return;
                                  }

                                  navigator.pop();
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Το βιβλίο κρατήθηκε με επιτυχία. Διάρκεια: 1 μήνας.',
                                      ),
                                    ),
                                  );
                                } catch (_) {
                                  if (!mounted) {
                                    return;
                                  }

                                  setDialogState(() {
                                    isReserving = false;
                                  });
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Δεν μπορέσαμε να κρατήσουμε το βιβλίο.',
                                      ),
                                    ),
                                  );
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: _contentColor,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFD4D9E6),
                          disabledForegroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: isReserving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Κράτησέ το',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showArticleDialog(_Article article) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 620),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
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
                  if (article.img != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: SizedBox(
                        height: 160,
                        child: Image.network(
                          article.img!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const _ArticleDialogIcon();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ] else ...[
                    const Center(child: _ArticleDialogIcon()),
                    const SizedBox(height: 18),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          article.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                            height: 1.12,
                          ),
                        ),
                      ),
                      if (article.important) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFFB800),
                          size: 26,
                        ),
                      ],
                    ],
                  ),
                  if (article.ageLabel.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Center(child: _InfoPill(article.ageLabel)),
                  ],
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 17, 18, 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FF),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE7ECFA)),
                    ),
                    child: Text(
                      article.text ?? article.summary ?? '',
                      style: const TextStyle(
                        color: Color(0xFF535A64),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.46,
                      ),
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
                          'Βιβλία/Άρθρα',
                          style: TextStyle(
                            color: _contentColor,
                            fontSize: 31,
                            fontWeight: FontWeight.w800,
                            height: 1.08,
                          ),
                        ),
                        SizedBox(height: 12),
                        Icon(
                          Icons.menu_book_rounded,
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
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
              children: [
                _LibraryTabSwitch(
                  selectedTab: _selectedTab,
                  onSelected: _selectTab,
                ),
                const SizedBox(height: 16),
                _LibrarySearchField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchText = value;
                    });
                  },
                ),
                const SizedBox(height: 14),
                _AgeFilterWrap(
                  filters: _ageFilters,
                  selectedFilter: _selectedAgeFilter,
                  onSelected: (filter) {
                    setState(() {
                      _selectedAgeFilter = filter;
                    });
                  },
                ),
                if (_selectedTab == _LibraryTab.books) ...[
                  const SizedBox(height: 10),
                  _AvailableOnlyChip(
                    selected: _availableOnly,
                    onTap: () {
                      setState(() {
                        _availableOnly = !_availableOnly;
                      });
                    },
                  ),
                ],
                const SizedBox(height: 20),
                if (_selectedTab == _LibraryTab.books)
                  _BooksList(
                    future: _booksFuture,
                    filter: _filterBooks,
                    onBookTap: _showBookDialog,
                  )
                else
                  _ArticlesList(
                    future: _articlesFuture,
                    filter: _filterArticles,
                    onArticleTap: _showArticleDialog,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryTabSwitch extends StatelessWidget {
  const _LibraryTabSwitch({
    required this.selectedTab,
    required this.onSelected,
  });

  final _LibraryTab selectedTab;
  final ValueChanged<_LibraryTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F3FA),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          _LibraryTabButton(
            title: 'Βιβλία',
            icon: Icons.menu_book_rounded,
            selected: selectedTab == _LibraryTab.books,
            onTap: () => onSelected(_LibraryTab.books),
          ),
          _LibraryTabButton(
            title: 'Άρθρα',
            icon: Icons.article_rounded,
            selected: selectedTab == _LibraryTab.articles,
            onTap: () => onSelected(_LibraryTab.articles),
          ),
        ],
      ),
    );
  }
}

class _LibraryTabButton extends StatelessWidget {
  const _LibraryTabButton({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected
                    ? _LibraryPageState._contentColor
                    : const Color(0xFF8C93A3),
                size: 20,
              ),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  color: selected
                      ? _LibraryPageState._contentColor
                      : const Color(0xFF8C93A3),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibrarySearchField extends StatelessWidget {
  const _LibrarySearchField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Αναζήτηση',
        hintStyle: const TextStyle(
          color: Color(0xFF9BA2AF),
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: Color(0xFF8C93A3),
        ),
        filled: true,
        fillColor: const Color(0xFFF6F8FC),
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _AgeFilterWrap extends StatelessWidget {
  const _AgeFilterWrap({
    required this.filters,
    required this.selectedFilter,
    required this.onSelected,
  });

  final List<_AgeFilter> filters;
  final _AgeFilter selectedFilter;
  final ValueChanged<_AgeFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filter in filters)
          _SmallFilterChip(
            label: filter.label,
            selected: filter == selectedFilter,
            onTap: () => onSelected(filter),
          ),
      ],
    );
  }
}

class _AvailableOnlyChip extends StatelessWidget {
  const _AvailableOnlyChip({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: _SmallFilterChip(
        label: 'Μόνο διαθέσιμα',
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}

class _SmallFilterChip extends StatelessWidget {
  const _SmallFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? _LibraryPageState._contentColor
              : const Color(0xFFF1F3F8),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF727987),
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _BooksList extends StatelessWidget {
  const _BooksList({
    required this.future,
    required this.filter,
    required this.onBookTap,
  });

  final Future<List<_Book>> future;
  final List<_Book> Function(List<_Book>) filter;
  final ValueChanged<_Book> onBookTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_Book>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(top: 60),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return const _LibraryEmptyState(
            text: 'Δεν μπορέσαμε να φορτώσουμε τα βιβλία.',
          );
        }

        final books = filter(snapshot.data ?? const []);

        if (books.isEmpty) {
          return const _LibraryEmptyState(text: 'Δεν βρέθηκαν βιβλία.');
        }

        return Column(
          children: [
            for (var index = 0; index < books.length; index++) ...[
              _BookCard(
                book: books[index],
                onTap: () => onBookTap(books[index]),
              ),
              if (index != books.length - 1) const SizedBox(height: 14),
            ],
          ],
        );
      },
    );
  }
}

class _ArticlesList extends StatelessWidget {
  const _ArticlesList({
    required this.future,
    required this.filter,
    required this.onArticleTap,
  });

  final Future<List<_Article>> future;
  final List<_Article> Function(List<_Article>) filter;
  final ValueChanged<_Article> onArticleTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_Article>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(top: 60),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return const _LibraryEmptyState(
            text: 'Δεν μπορέσαμε να φορτώσουμε τα άρθρα.',
          );
        }

        final articles = filter(snapshot.data ?? const []);

        if (articles.isEmpty) {
          return const _LibraryEmptyState(text: 'Δεν βρέθηκαν άρθρα.');
        }

        return Column(
          children: [
            for (var index = 0; index < articles.length; index++) ...[
              _ArticleCard(
                article: articles[index],
                onTap: () => onArticleTap(articles[index]),
              ),
              if (index != articles.length - 1) const SizedBox(height: 14),
            ],
          ],
        );
      },
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.book, required this.onTap});

  final _Book book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE7ECFA)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF385DC9).withValues(alpha: 0.08),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LibraryImage(url: book.img, icon: Icons.menu_book_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                      ),
                    ),
                    if (book.author != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        book.author!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF737B8B),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 9),
                    _BookInfoPillGroup(book: book),
                    if (book.summary != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        book.summary!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF777D87),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.32,
                        ),
                      ),
                    ],
                    const SizedBox(height: 11),
                    _AvailabilityPill(
                      available: book.availableQuantity,
                      total: book.totalQuantity,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFB6BBC3),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookDialogIcon extends StatelessWidget {
  const _BookDialogIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 132,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3FF),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Icon(
        Icons.menu_book_rounded,
        color: _LibraryPageState._contentColor,
        size: 50,
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.article, required this.onTap});

  final _Article article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE7ECFA)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF385DC9).withValues(alpha: 0.08),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LibraryImage(url: article.img, icon: Icons.article_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            article.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              height: 1.12,
                            ),
                          ),
                        ),
                        if (article.important) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFFFB800),
                            size: 25,
                          ),
                        ],
                      ],
                    ),
                    if (article.ageLabel.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      _InfoPill(article.ageLabel),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      article.previewText,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF777D87),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.34,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArticleDialogIcon extends StatelessWidget {
  const _ArticleDialogIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3FF),
        borderRadius: BorderRadius.circular(26),
      ),
      child: const Icon(
        Icons.article_rounded,
        color: _LibraryPageState._contentColor,
        size: 44,
      ),
    );
  }
}

class _LibraryImage extends StatelessWidget {
  const _LibraryImage({required this.url, required this.icon});

  final String? url;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 82,
        height: 112,
        color: const Color(0xFFEFF3FF),
        child: imageUrl == null
            ? Icon(icon, color: _LibraryPageState._contentColor, size: 38)
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    icon,
                    color: _LibraryPageState._contentColor,
                    size: 38,
                  );
                },
              ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD9E2FF)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _LibraryPageState._contentColor,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class _BookInfoPillGroup extends StatelessWidget {
  const _BookInfoPillGroup({
    required this.book,
    this.alignment = WrapAlignment.start,
  });

  final _Book book;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final pills = [
      if (book.category != null) book.category!,
      if (book.language != null) book.language!,
      if (book.level != null) book.level!,
      if (book.ageLabel.isNotEmpty) book.ageLabel,
    ];

    if (pills.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      alignment: alignment,
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final pill in pills) _InfoPill(pill),
      ],
    );
  }
}

class _AvailabilityPill extends StatelessWidget {
  const _AvailabilityPill({required this.available, required this.total});

  final int available;
  final int total;

  @override
  Widget build(BuildContext context) {
    final isAvailable = available > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: isAvailable ? const Color(0xFFEAF8F0) : const Color(0xFFF2F3F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isAvailable ? 'Διαθέσιμα $available/$total' : 'Μη διαθέσιμο',
        style: TextStyle(
          color: isAvailable ? const Color(0xFF19894A) : const Color(0xFF8D94A1),
          fontSize: 12,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _LibraryEmptyState extends StatelessWidget {
  const _LibraryEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 56),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF8D94A1),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _Book {
  const _Book({
    required this.id,
    required this.title,
    required this.category,
    required this.author,
    required this.minAge,
    required this.maxAge,
    required this.summary,
    required this.img,
    required this.language,
    required this.level,
    required this.totalQuantity,
    required this.availableQuantity,
  });

  factory _Book.fromRow(Map<String, dynamic> row) {
    return _Book(
      id: _readText(row['id']),
      title: _readText(row['title'], fallback: 'Βιβλίο'),
      category: _readNullableText(row['category']),
      author: _readNullableText(row['author']),
      minAge: _readInt(row['min_age']),
      maxAge: _readInt(row['max_age']),
      summary: _readNullableText(row['summary']),
      img: _readNullableText(row['img']),
      language: _readNullableText(row['language']),
      level: _readNullableText(row['level']),
      totalQuantity: _readInt(row['total_quantity']) ?? 1,
      availableQuantity: _readInt(row['available_quantity']) ?? 0,
    );
  }

  final String id;
  final String title;
  final String? category;
  final String? author;
  final int? minAge;
  final int? maxAge;
  final String? summary;
  final String? img;
  final String? language;
  final String? level;
  final int totalQuantity;
  final int availableQuantity;

  String get ageLabel => _formatAge(minAge, maxAge);
}

class _Article {
  const _Article({
    required this.title,
    required this.summary,
    required this.text,
    required this.img,
    required this.minAge,
    required this.maxAge,
    required this.important,
  });

  factory _Article.fromRow(Map<String, dynamic> row) {
    return _Article(
      title: _readText(row['title'], fallback: 'Άρθρο'),
      summary: _readNullableText(row['summary']),
      text: _readNullableText(row['text']),
      img: _readNullableText(row['img']),
      minAge: _readInt(row['min_age']),
      maxAge: _readInt(row['max_age']),
      important: row['important'] == true,
    );
  }

  final String title;
  final String? summary;
  final String? text;
  final String? img;
  final int? minAge;
  final int? maxAge;
  final bool important;

  String get previewText => summary ?? text ?? '';
  String get ageLabel => _formatAge(minAge, maxAge);
}

class _AgeFilter {
  const _AgeFilter({
    required this.label,
    required this.minAge,
    required this.maxAge,
  });

  final String label;
  final int? minAge;
  final int? maxAge;

  bool matches(int? itemMinAge, int? itemMaxAge) {
    if (minAge == null && maxAge == null) {
      return true;
    }

    final filterMinAge = minAge ?? 0;
    final filterMaxAge = maxAge ?? 999;
    final min = itemMinAge ?? 0;
    final max = itemMaxAge ?? 999;

    return min <= filterMaxAge && max >= filterMinAge;
  }
}

String _readText(dynamic value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }

  return fallback;
}

String? _readNullableText(dynamic value) {
  final text = _readText(value);

  return text.isEmpty ? null : text;
}

int? _readInt(dynamic value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  if (value is String) {
    return int.tryParse(value);
  }

  return null;
}

String _formatAge(int? minAge, int? maxAge) {
  if (minAge == null && maxAge == null) {
    return '';
  }

  if (minAge != null && maxAge == null) {
    return '$minAge+';
  }

  if (minAge == null && maxAge != null) {
    return 'έως $maxAge';
  }

  return '$minAge-$maxAge';
}
