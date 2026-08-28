import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_notification_service.dart';

class ConnectCodePage extends StatefulWidget {
  const ConnectCodePage({required this.onConnected, super.key});

  final VoidCallback onConnected;

  @override
  State<ConnectCodePage> createState() => _ConnectCodePageState();
}

class _ConnectCodePageState extends State<ConnectCodePage> {
  final _connectCodeController = TextEditingController();
  bool _isSaving = false;
  String? _errorText;

  @override
  void dispose() {
    _connectCodeController.dispose();
    super.dispose();
  }

  Future<void> _linkUser() async {
    final connectCode = _connectCodeController.text.trim();

    if (connectCode.isEmpty) {
      setState(() {
        _errorText = 'Συμπλήρωσε τον κωδικό σύνδεσης.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      await Supabase.instance.client.rpc(
        'link_user_by_connect_code',
        params: {'input_connect_code': connectCode},
      );
      await PushNotificationService.syncCurrentDevice();

      if (mounted) {
        widget.onConnected();
      }
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
        _errorText = _connectCodeErrorMessage(error.message);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
        _errorText = 'Δεν μπορέσαμε να συνδέσουμε τα στοιχεία.';
      });
    }
  }

  Future<void> _goBackToLogin() async {
    await PushNotificationService.unregisterCurrentDevice();
    await Supabase.instance.client.auth.signOut();
  }

  String _connectCodeErrorMessage(String message) {
    final lowerMessage = message.toLowerCase();

    if (lowerMessage.contains('connect code not found')) {
      return 'Ο κωδικός σύνδεσης δεν βρέθηκε.';
    }

    if (lowerMessage.contains('connect code is required')) {
      return 'Συμπλήρωσε τον κωδικό σύνδεσης.';
    }

    return 'Δεν μπορέσαμε να συνδέσουμε τα στοιχεία.';
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
            stops: [0.3, 1],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Σύνδεση στοιχείων',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Πληκτρολόγησε τον κωδικό σύνδεσης που σου δόθηκε, για να συνδέσουμε τον λογαριασμό σου με τα στοιχεία που υπάρχουν στο φροντιστήριο.',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _connectCodeController,
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            if (!_isSaving) {
                              _linkUser();
                            }
                          },
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.key_rounded),
                            errorText: _errorText,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _isSaving ? null : _goBackToLogin,
                              child: const Text('Επιστροφή'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _isSaving ? null : _linkUser,
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Σύνδεση'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
