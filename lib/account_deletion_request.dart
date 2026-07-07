import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountDeletionRequestPage extends StatefulWidget {
  const AccountDeletionRequestPage({super.key});

  @override
  State<AccountDeletionRequestPage> createState() =>
      _AccountDeletionRequestPageState();
}

class _AccountDeletionRequestPageState
    extends State<AccountDeletionRequestPage> {
  final TextEditingController _reasonController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (_isSubmitting) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Επιβεβαίωση αιτήματος'),
          content: const Text(
            'Θα καταχωρηθεί αίτημα διαγραφής του λογαριασμού και των σχετικών προσωπικών δεδομένων. Η ομάδα του Modern Language θα το ελέγξει πριν ολοκληρωθεί η διαγραφή.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Άκυρο'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Καταχώρηση'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await Supabase.instance.client.rpc(
        'request_account_deletion',
        params: {
          'input_reason': _reasonController.text.trim().isEmpty
              ? null
              : _reasonController.text.trim(),
        },
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Δεν μπορέσαμε να καταχωρήσουμε το αίτημα. Δοκίμασε ξανά.',
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Διαγραφή λογαριασμού')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Μπορείς να ζητήσεις τη διαγραφή του λογαριασμού σου και των σχετικών προσωπικών δεδομένων που τηρούνται για την πρόσβαση στην εφαρμογή.',
              style: TextStyle(fontSize: 16, height: 1.45),
            ),
            const SizedBox(height: 14),
            const Text(
              'Το αίτημα θα ελεγχθεί από την ομάδα του Modern Language, ώστε να διαγραφούν ή να ανωνυμοποιηθούν τα δεδομένα που μπορούν να διαγραφούν νόμιμα.',
              style: TextStyle(fontSize: 16, height: 1.45),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _reasonController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Σχόλιο (προαιρετικό)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submitRequest,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_remove_rounded),
              label: const Text('Υποβολή αιτήματος διαγραφής'),
            ),
          ],
        ),
      ),
    );
  }
}
