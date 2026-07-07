import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_deletion_request.dart';
import 'personal_details.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<_ProfileData> _profileFuture = _loadProfile();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploading = false;

  Future<_ProfileData> _loadProfile() async {
    final supabase = Supabase.instance.client;
    final userRow = await _loadLinkedUserRow();

    if (userRow == null) {
      return const _ProfileData();
    }

    final userId = userRow['id'];
    final role = userRow['role'];

    final studentRows = userId != null
        ? await supabase
              .from('students')
              .select('id, name, profile_pic')
              .eq('user_id', userId)
        : const <Map<String, dynamic>>[];

    return _ProfileData(
      id: _readText(userId, fallback: ''),
      name: _readText(userRow['name'], fallback: 'Χρήστης'),
      role: role is String ? role.trim().toLowerCase() : null,
      profilePic: _readOptionalText(userRow['profile_pic']),
      students: studentRows.map(_ProfileStudent.fromRow).toList(),
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

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _refresh() {
    setState(() {
      _profileFuture = _loadProfile();
    });
  }

  Future<void> _pickAndUploadPhoto(_ProfilePhotoTarget target) async {
    if (_isUploading || target.id.isEmpty) {
      return;
    }

    final pickedImage = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 86,
    );

    if (pickedImage == null) {
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final bytes = await pickedImage.readAsBytes();
      final photoUrl = await _uploadProfilePhoto(
        target: target,
        bytes: bytes,
        fileName: pickedImage.name,
      );

      await _updateProfilePic(target, photoUrl);
      await _deleteStoredPhoto(target.currentPhotoUrl);

      if (!mounted) {
        return;
      }

      _showMessage('Η φωτογραφία ενημερώθηκε.');
      _refresh();
    } catch (_) {
      if (mounted) {
        _showMessage('Δεν μπορέσαμε να ανεβάσουμε τη φωτογραφία.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<String> _uploadProfilePhoto({
    required _ProfilePhotoTarget target,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final supabase = Supabase.instance.client;
    final authUserId = supabase.auth.currentUser?.id;

    if (authUserId == null) {
      throw StateError('No auth user');
    }

    final extension = _fileExtension(fileName);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path =
        '$authUserId/${target.folderName}/${target.id}/profile_$timestamp.$extension';
    final contentType = _contentTypeForExtension(extension);

    await supabase.storage
        .from('profile-pictures')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            contentType: contentType,
            upsert: true,
          ),
        );

    return supabase.storage.from('profile-pictures').getPublicUrl(path);
  }

  Future<void> _removePhoto(_ProfilePhotoTarget target) async {
    if (_isUploading || target.id.isEmpty) {
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      await _updateProfilePic(target, null);
      await _deleteStoredPhoto(target.currentPhotoUrl);

      if (!mounted) {
        return;
      }

      _showMessage('Η φωτογραφία αφαιρέθηκε.');
      _refresh();
    } catch (_) {
      if (mounted) {
        _showMessage('Δεν μπορέσαμε να αφαιρέσουμε τη φωτογραφία.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _updateProfilePic(
    _ProfilePhotoTarget target,
    String? photoUrl,
  ) async {
    final table = target.type == _ProfilePhotoType.user ? 'users' : 'students';

    await Supabase.instance.client
        .from(table)
        .update({'profile_pic': photoUrl})
        .eq('id', target.id);
  }

  Future<void> _deleteStoredPhoto(String? photoUrl) async {
    final path = _storagePathFromPublicUrl(photoUrl);
    if (path == null) {
      return;
    }

    await Supabase.instance.client.storage.from('profile-pictures').remove([
      path,
    ]);
  }

  void _showPhotoActions(_ProfilePhotoTarget target) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.add_a_photo_rounded),
                  title: const Text('Προσθήκη φωτογραφίας'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickAndUploadPhoto(target);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Αφαίρεση φωτογραφίας'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _removePhoto(target);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.close_rounded),
                  title: const Text('Άκυρο'),
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPersonalDetails() async {
    final didUpdate = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => const PersonalDetailsPage(),
      ),
    );

    if (didUpdate == true && mounted) {
      _refresh();
    }
  }

  Future<void> _openAccountDeletionRequest() async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => const AccountDeletionRequestPage(),
      ),
    );

    if (submitted == true && mounted) {
      _showMessage('Το αίτημα διαγραφής λογαριασμού καταχωρήθηκε.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFF39D2C0)],
            stops: [0.28, 1],
          ),
        ),
        child: SafeArea(
          child: FutureBuilder<_ProfileData>(
            future: _profileFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return _ProfileError(onRetry: _refresh);
              }

              final data = snapshot.data ?? const _ProfileData();
              final isBusy = _isUploading;

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                children: [
                  Row(
                    children: [
                      InkWell(
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
                      const Expanded(
                        child: Text(
                          'Προφίλ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ProfilePhotoButton(
                          imageUrl: data.profilePic,
                          size: 92,
                          showAddIcon: true,
                          onTap: isBusy || data.id.isEmpty
                              ? null
                              : () => _showPhotoActions(
                                  _ProfilePhotoTarget.user(
                                    data.id,
                                    data.profilePic,
                                  ),
                                ),
                        ),
                        if (isBusy)
                          const SizedBox(
                            width: 34,
                            height: 34,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    data.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  if (data.students.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 18,
                      runSpacing: 18,
                      children: [
                        for (final student in data.students)
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ProfilePhotoButton(
                                imageUrl: student.profilePic,
                                size: 64,
                                showAddIcon: true,
                                onTap: isBusy || student.id.isEmpty
                                    ? null
                                    : () => _showPhotoActions(
                                        _ProfilePhotoTarget.student(
                                          student.id,
                                          student.profilePic,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: 112,
                                child: Text(
                                  student.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 36),
                  _ProfileActionButton(
                    icon: Icons.badge_rounded,
                    label: 'Προσωπικά στοιχεία',
                    onPressed: _openPersonalDetails,
                  ),
                  const SizedBox(height: 12),
                  _ProfileActionButton(
                    icon: Icons.notifications_rounded,
                    label: 'Ειδοποιήσεις',
                    onPressed: () =>
                        _showMessage('Οι ειδοποιήσεις θα συνδεθούν σύντομα.'),
                  ),
                  const SizedBox(height: 12),
                  _ProfileActionButton(
                    icon: Icons.person_remove_rounded,
                    label: 'Αίτημα διαγραφής λογαριασμού',
                    isDestructive: true,
                    onPressed: _openAccountDeletionRequest,
                  ),
                  const SizedBox(height: 12),
                  _ProfileActionButton(
                    icon: Icons.logout_rounded,
                    label: 'Έξοδος',
                    isDestructive: true,
                    onPressed: _signOut,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class ProfilePhotoButton extends StatelessWidget {
  const ProfilePhotoButton({
    super.key,
    this.imageUrl,
    this.size = 56,
    this.showAddIcon = false,
    this.onTap,
  });

  final String? imageUrl;
  final double size;
  final bool showAddIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final image = _networkImageOrNull(imageUrl);

    return SizedBox(
      width: showAddIcon ? size + 8 : size,
      height: showAddIcon ? size + 8 : size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: const Color.fromARGB(255, 164, 205, 225),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Ink(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  image: image == null
                      ? null
                      : DecorationImage(image: image, fit: BoxFit.cover),
                ),
                child: image == null
                    ? Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: size * 0.92,
                      )
                    : null,
              ),
            ),
          ),
          if (showAddIcon)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: size * 0.34,
                height: size * 0.34,
                decoration: BoxDecoration(
                  color: const Color(0xFF2F6BFF),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: size * 0.24,
                ),
              ),
            ),
        ],
      ),
    );
  }

  ImageProvider? _networkImageOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    return NetworkImage(trimmed);
  }
}

class CrownedProfilePhoto extends StatelessWidget {
  const CrownedProfilePhoto({
    super.key,
    this.imageUrl,
    this.crownTop = 0,
  });

  final String? imageUrl;
  final double crownTop;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 154,
      height: 164,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          ProfilePhotoButton(
            imageUrl: imageUrl,
            size: 130,
          ),
          Positioned(
            top: crownTop,
            right: 22,
            child: Transform.rotate(
              angle: 0.18,
              child: Image.asset(
                'lib/img/crown.png',
                width: 70,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileActionButton extends StatelessWidget {
  const _ProfileActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = isDestructive
        ? const Color(0xFFB3261E)
        : const Color(0xFF173A8A);

    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.92),
        foregroundColor: foregroundColor,
        minimumSize: const Size.fromHeight(54),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: Icon(icon),
      label: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 42),
            const SizedBox(height: 12),
            const Text(
              'Δεν μπορέσαμε να φορτώσουμε το προφίλ.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Δοκιμή ξανά')),
          ],
        ),
      ),
    );
  }
}

class _ProfileData {
  const _ProfileData({
    this.id = '',
    this.name = 'Χρήστης',
    this.role,
    this.profilePic,
    this.students = const [],
  });

  final String id;
  final String name;
  final String? role;
  final String? profilePic;
  final List<_ProfileStudent> students;
}

class _ProfileStudent {
  const _ProfileStudent({required this.id, required this.name, this.profilePic});

  factory _ProfileStudent.fromRow(Map<String, dynamic> row) {
    return _ProfileStudent(
      id: _readText(row['id'], fallback: ''),
      name: _readText(row['name'], fallback: 'Μαθητής'),
      profilePic: _readOptionalText(row['profile_pic']),
    );
  }

  final String id;
  final String name;
  final String? profilePic;
}

enum _ProfilePhotoType { user, student }

class _ProfilePhotoTarget {
  const _ProfilePhotoTarget._({
    required this.type,
    required this.id,
    this.currentPhotoUrl,
  });

  const _ProfilePhotoTarget.user(String id, String? currentPhotoUrl)
    : this._(
        type: _ProfilePhotoType.user,
        id: id,
        currentPhotoUrl: currentPhotoUrl,
      );

  const _ProfilePhotoTarget.student(String id, String? currentPhotoUrl)
    : this._(
        type: _ProfilePhotoType.student,
        id: id,
        currentPhotoUrl: currentPhotoUrl,
      );

  final _ProfilePhotoType type;
  final String id;
  final String? currentPhotoUrl;

  String get folderName =>
      type == _ProfilePhotoType.user ? 'users' : 'students';
}

String _readText(Object? value, {required String fallback}) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }

  return fallback;
}

String? _readOptionalText(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }

  return null;
}

String _fileExtension(String fileName) {
  final normalized = fileName.toLowerCase().trim();
  final dotIndex = normalized.lastIndexOf('.');
  final extension = dotIndex == -1 ? '' : normalized.substring(dotIndex + 1);

  if (extension == 'png' || extension == 'webp') {
    return extension;
  }

  return 'jpg';
}

String _contentTypeForExtension(String extension) {
  return switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

String? _storagePathFromPublicUrl(String? photoUrl) {
  final uri = Uri.tryParse(photoUrl ?? '');
  if (uri == null) {
    return null;
  }

  const marker = '/storage/v1/object/public/profile-pictures/';
  final markerIndex = uri.path.indexOf(marker);
  if (markerIndex == -1) {
    return null;
  }

  final encodedPath = uri.path.substring(markerIndex + marker.length);
  if (encodedPath.isEmpty) {
    return null;
  }

  return Uri.decodeComponent(encodedPath);
}
