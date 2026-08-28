import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_navigation.dart';
import 'connect_code_page.dart';
import 'homepage.dart';
import 'login.dart';
import 'push_notification_service.dart';

const supabaseUrl = 'https://vjgvvcjtrptkgiyowuvx.supabase.co';
const supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZqZ3Z2Y2p0cnB0a2dpeW93dXZ4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg5MjU4ODcsImV4cCI6MjA5NDUwMTg4N30.1RhxT69eJOw3VF5iHjFizmrpOnooHGaW3ut73sFpRHs';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }

  await PushNotificationService.initialize();
  runApp(const MyApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    PushNotificationService.openPendingNotification();
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Modern Language',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F6BFF),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8FC),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Session? _session = Supabase.instance.client.auth.currentSession;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      if (!mounted) {
        return;
      }

      setState(() {
        _session = data.session;
      });
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;

    if (session == null) {
      return const LoginPage();
    }

    return _LinkedUserGate(authUserId: session.user.id);
  }
}

class _LinkedUserGate extends StatefulWidget {
  const _LinkedUserGate({required this.authUserId});

  final String authUserId;

  @override
  State<_LinkedUserGate> createState() => _LinkedUserGateState();
}

class _LinkedUserGateState extends State<_LinkedUserGate> {
  late Future<bool> _hasLinkedUserFuture = _hasLinkedUser();

  @override
  void didUpdateWidget(covariant _LinkedUserGate oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.authUserId != widget.authUserId) {
      _hasLinkedUserFuture = _hasLinkedUser();
    }
  }

  Future<bool> _hasLinkedUser() async {
    final linkedUser = await Supabase.instance.client.rpc(
      'current_linked_user',
    );

    return linkedUser != null;
  }

  void _refreshLinkedUser() {
    setState(() {
      _hasLinkedUserFuture = _hasLinkedUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasLinkedUserFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 42),
                    const SizedBox(height: 12),
                    const Text(
                      'Δεν μπορέσαμε να ελέγξουμε τη σύνδεση στοιχείων.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _refreshLinkedUser,
                      child: const Text('Δοκιμή ξανά'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (snapshot.data == true) {
          return const HomePage();
        }

        return ConnectCodePage(onConnected: _refreshLinkedUser);
      },
    );
  }
}
