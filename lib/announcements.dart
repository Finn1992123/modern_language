import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({super.key});

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  late final Future<List<_Announcement>> _announcementsFuture =
      _loadAnnouncements();

  static const Color _headerColor = Color(0x9682FE63);
  static const Color _contentColor = Color(0xFF2D7D10);

  Future<List<_Announcement>> _loadAnnouncements() async {
    final rows = await Supabase.instance.client
        .from('announcements')
        .select('created_at, header, text')
        .order('created_at', ascending: false);

    return rows
        .map((row) => _Announcement.fromRow(Map<String, dynamic>.from(row)))
        .toList();
  }

  void _showAnnouncementDialog(_Announcement announcement) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 620),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    Center(
                      child: Image.asset(
                        'lib/img/logoTransp.png',
                        height: 132,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 35),
                    Text(
                      announcement.header,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        height: 1.12,
                      ),
                    ),
                    if (announcement.formattedDate.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F5F7),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            announcement.formattedDate,
                            style: const TextStyle(
                              color: Color(0xFF8E949E),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 17, 18, 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAF8),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFFE8F5E5)),
                      ),
                      child: Text(
                        announcement.text,
                        textAlign: TextAlign.left,
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
                          'Ανακοινώσεις',
                          style: TextStyle(
                            color: _contentColor,
                            fontSize: 31,
                            fontWeight: FontWeight.w800,
                            height: 1.08,
                          ),
                        ),
                        SizedBox(height: 12),
                        Icon(
                          Icons.campaign_rounded,
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
            child: FutureBuilder<List<_Announcement>>(
              future: _announcementsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Δεν μπορέσαμε να φορτώσουμε τις ανακοινώσεις.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }

                final announcements = snapshot.data ?? const [];

                if (announcements.isEmpty) {
                  return Center(
                    child: Text(
                      'Δεν υπάρχουν ανακοινώσεις.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                  itemCount: announcements.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final announcement = announcements[index];

                    return _AnnouncementCard(
                      announcement: announcement,
                      onTap: () => _showAnnouncementDialog(announcement),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Announcement {
  const _Announcement({
    required this.createdAt,
    required this.header,
    required this.text,
  });

  factory _Announcement.fromRow(Map<String, dynamic> row) {
    return _Announcement(
      createdAt: _readDate(row['created_at']),
      header: _readText(row['header'], fallback: 'Ανακοίνωση'),
      text: _readText(row['text']),
    );
  }

  final DateTime? createdAt;
  final String header;
  final String text;

  String get formattedDate {
    final date = createdAt;

    if (date == null) {
      return '';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  static DateTime? _readDate(dynamic value) {
    if (value is DateTime) {
      return value.toLocal();
    }

    if (value is String) {
      return DateTime.tryParse(value)?.toLocal();
    }

    return null;
  }

  static String _readText(dynamic value, {String fallback = ''}) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    return fallback;
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.announcement,
    required this.onTap,
  });

  final _Announcement announcement;
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
          padding: const EdgeInsets.fromLTRB(18, 17, 16, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE8F5E5)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2D7D10).withValues(alpha: 0.09),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAFBE5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: _AnnouncementsPageState._contentColor,
                  size: 26,
                ),
              ),
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
                            announcement.header,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              height: 1.12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFFB6BBC3),
                          size: 24,
                        ),
                      ],
                    ),
                    if (announcement.formattedDate.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F5F7),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          announcement.formattedDate,
                          style: const TextStyle(
                            color: Color(0xFF8E949E),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 11),
                    Text(
                      announcement.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF737984),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
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
