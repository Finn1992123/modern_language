import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PersonalDetailsPage extends StatefulWidget {
  const PersonalDetailsPage({super.key});

  @override
  State<PersonalDetailsPage> createState() => _PersonalDetailsPageState();
}

class _PersonalDetailsPageState extends State<PersonalDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _alternativeEmailController = TextEditingController();

  late Future<_PersonalDetailsData> _detailsFuture = _loadDetails();
  _PersonalDetailsData _initialDetails = const _PersonalDetailsData();
  String? _userId;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _emergencyContactController.dispose();
    _alternativeEmailController.dispose();
    super.dispose();
  }

  Future<_PersonalDetailsData> _loadDetails() async {
    final linkedUser = await Supabase.instance.client.rpc(
      'current_linked_user',
    );

    final userRow = linkedUser is Map<String, dynamic>
        ? linkedUser
        : linkedUser is Map
        ? Map<String, dynamic>.from(linkedUser)
        : null;

    if (userRow == null) {
      return const _PersonalDetailsData();
    }

    final details = _PersonalDetailsData.fromRow(userRow);
    _userId = details.id;
    _initialDetails = details;
    _setControllerValues(details);
    return details;
  }

  void _setControllerValues(_PersonalDetailsData details) {
    _nameController.text = details.name;
    _surnameController.text = details.surname;
    _emailController.text = details.email;
    _phoneController.text = details.phoneNumber;
    _emergencyContactController.text = details.emergencyContact;
    _alternativeEmailController.text = details.alternativeEmail;
  }

  Future<void> _saveDetails() async {
    if (_isSaving || !_formKey.currentState!.validate()) {
      return;
    }

    final updatedDetails = _currentDetails();
    if (updatedDetails.hasSameEditableFields(_initialDetails)) {
      _showMessage('Δεν υπάρχουν αλλαγές για αποθήκευση.');
      return;
    }

    final shouldSave = await _confirmSave();
    if (shouldSave != true) {
      return;
    }

    final userId = _userId;
    if (userId == null || userId.isEmpty) {
      _showMessage('Δεν βρέθηκε ο χρήστης.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await Supabase.instance.client
          .from('users')
          .update({
            'name': updatedDetails.name,
            'surname': _nullableText(updatedDetails.surname),
            'email': _nullableText(updatedDetails.email),
            'phone_number': _nullableText(updatedDetails.phoneNumber),
            'emergency_contact': _nullableText(updatedDetails.emergencyContact),
            'alternative_email': _nullableText(updatedDetails.alternativeEmail),
          })
          .eq('id', userId);

      if (!mounted) {
        return;
      }

      _showMessage('Τα στοιχεία ενημερώθηκαν.');
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        _showMessage('Δεν μπορέσαμε να αποθηκεύσουμε τα στοιχεία.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  _PersonalDetailsData _currentDetails() {
    return _PersonalDetailsData(
      id: _userId ?? '',
      name: _nameController.text.trim(),
      surname: _surnameController.text.trim(),
      email: _emailController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      emergencyContact: _emergencyContactController.text.trim(),
      alternativeEmail: _alternativeEmailController.text.trim(),
    );
  }

  Future<bool?> _confirmSave() {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Αποθήκευση στοιχείων;'),
          content: const Text('Οι αλλαγές που έκανες θα αποθηκευτούν.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Άκυρο'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Αποθήκευση'),
            ),
          ],
        );
      },
    );
  }

  void _closeKeyboard() {
    FocusScope.of(context).unfocus();
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
          child: FutureBuilder<_PersonalDetailsData>(
            future: _detailsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return _PersonalDetailsError(onRetry: _retry);
              }

              return Form(
                key: _formKey,
                child: ListView(
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
                            'Προσωπικά στοιχεία',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 28),
                    _DetailsField(
                      controller: _nameController,
                      label: 'Όνομα',
                      icon: Icons.person_rounded,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _closeKeyboard(),
                      validator: _requiredValidator,
                    ),
                    const SizedBox(height: 14),
                    _DetailsField(
                      controller: _surnameController,
                      label: 'Επίθετο',
                      icon: Icons.badge_rounded,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _closeKeyboard(),
                    ),
                    const SizedBox(height: 14),
                    _DetailsField(
                      controller: _emailController,
                      label: 'Email',
                      icon: Icons.email_rounded,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _closeKeyboard(),
                      validator: _optionalEmailValidator,
                    ),
                    const SizedBox(height: 14),
                    _DetailsField(
                      controller: _phoneController,
                      label: 'Τηλέφωνο',
                      icon: Icons.phone_rounded,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _closeKeyboard(),
                    ),
                    const SizedBox(height: 14),
                    _DetailsField(
                      controller: _emergencyContactController,
                      label: 'Επαφή έκτακτης ανάγκης',
                      icon: Icons.contact_emergency_rounded,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _closeKeyboard(),
                    ),
                    const SizedBox(height: 14),
                    _DetailsField(
                      controller: _alternativeEmailController,
                      label: 'Εναλλακτικό email',
                      icon: Icons.alternate_email_rounded,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _closeKeyboard(),
                      validator: _optionalEmailValidator,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _saveDetails,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2F6BFF),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.4,
                              ),
                            )
                          : const Icon(Icons.save_rounded),
                      label: const Text(
                        'Αποθήκευση',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _retry() {
    setState(() {
      _detailsFuture = _loadDetails();
    });
  }
}

class _DetailsField extends StatelessWidget {
  const _DetailsField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.92),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _PersonalDetailsError extends StatelessWidget {
  const _PersonalDetailsError({required this.onRetry});

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
              'Δεν μπορέσαμε να φορτώσουμε τα προσωπικά στοιχεία.',
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

class _PersonalDetailsData {
  const _PersonalDetailsData({
    this.id = '',
    this.name = '',
    this.surname = '',
    this.email = '',
    this.phoneNumber = '',
    this.emergencyContact = '',
    this.alternativeEmail = '',
  });

  factory _PersonalDetailsData.fromRow(Map<String, dynamic> row) {
    return _PersonalDetailsData(
      id: _readText(row['id']),
      name: _readText(row['name']),
      surname: _readText(row['surname']),
      email: _readText(row['email']),
      phoneNumber: _readText(row['phone_number']),
      emergencyContact: _readText(row['emergency_contact']),
      alternativeEmail: _readText(row['alternative_email']),
    );
  }

  final String id;
  final String name;
  final String surname;
  final String email;
  final String phoneNumber;
  final String emergencyContact;
  final String alternativeEmail;

  bool hasSameEditableFields(_PersonalDetailsData other) {
    return name == other.name &&
        surname == other.surname &&
        email == other.email &&
        phoneNumber == other.phoneNumber &&
        emergencyContact == other.emergencyContact &&
        alternativeEmail == other.alternativeEmail;
  }
}

String? _requiredValidator(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Συμπλήρωσε το πεδίο.';
  }

  return null;
}

String? _optionalEmailValidator(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) {
    return null;
  }

  if (!text.contains('@') || !text.contains('.')) {
    return 'Συμπλήρωσε έγκυρο email.';
  }

  return null;
}

String? _nullableText(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _readText(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }

  return '';
}
