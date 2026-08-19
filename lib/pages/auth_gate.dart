import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_page.dart';
import 'home_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;

    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // SOURCE OF TRUTH: the client's own session, not the stream payload.
        //
        // Supabase.initialize() is awaited in main() and restores the persisted
        // session from disk before the first frame, so currentSession is already
        // correct here. The stream is used only to trigger a rebuild when auth
        // state changes (sign in, sign out, OTP verify, token refresh).
        //
        // Reading currentSession instead of snapshot.data!.session is what keeps
        // a logged-in user logged in: a transient event carrying a null session
        // can no longer bounce them back to AuthPage, and an auto-refreshed
        // token keeps them signed in without any special handling.
        final session = client.auth.currentSession;

        // Only show the loader if the session genuinely isn't resolved yet.
        // In practice this is skipped entirely because initialize() already ran.
        final resolving =
            snapshot.connectionState == ConnectionState.waiting && session == null;

        if (resolving) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Scaffold(
            backgroundColor:
                isDark ? const Color(0xFF151521) : const Color(0xFFE8E8F0),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        // --- ANIMATED PAGE TRANSITION ---
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 800),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.95, end: 1.0).animate(animation),
                child: child,
              ),
            );
          },
          // Keys tell Flutter these are different screens.
          child: session != null
              ? const HomePage(key: ValueKey('HomePage'))
              : const AuthPage(key: ValueKey('AuthPage')),
        );
      },
    );
  }
}