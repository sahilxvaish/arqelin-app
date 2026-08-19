import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart'; // Added for the premium branding text

// =============================================================================
// AUTH PAGE — EMAIL + PASSWORD ONLY
//
// Sign in, sign up and password reset. No phone, no OTP, no SMS, no social
// providers. Session persistence is handled entirely by supabase_flutter's
// built-in storage (Supabase.initialize() in main.dart) — nothing is stored
// or refreshed by hand here.
// =============================================================================
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isLoading = false;
  bool _isLogin = true; // true = Sign In, false = Create Account

  late AnimationController _liquidController;

  @override
  void initState() {
    super.initState();
    _liquidController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _liquidController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // FEEDBACK
  // ---------------------------------------------------------------------------

  void _snack(String message, {bool error = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.redAccent : const Color(0xFF2B44FF),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _friendly(AuthException e) {
    final m = e.message.toLowerCase();

    if (m.contains('invalid login credentials')) {
      return 'Incorrect email or password.';
    }
    if (m.contains('email not confirmed')) {
      return 'Please confirm your email first, then sign in.';
    }
    if (m.contains('user already registered') ||
        m.contains('already been registered')) {
      return 'An account with this email already exists. Try signing in.';
    }
    if (m.contains('password should be') || m.contains('weak password')) {
      return 'Password must be at least 6 characters.';
    }
    if (m.contains('unable to validate email') || m.contains('invalid email')) {
      return 'That email address doesn\'t look valid.';
    }
    if (m.contains('rate limit') ||
        m.contains('too many') ||
        m.contains('security purposes')) {
      return 'Too many attempts. Please wait a minute and try again.';
    }
    if (m.contains('signups not allowed') || m.contains('signup is disabled')) {
      return 'New sign-ups are currently disabled.';
    }
    if (m.contains('user not found')) {
      return 'No account found with that email address.';
    }
    if (m.contains('session') || m.contains('refresh token')) {
      return 'Your session expired. Please sign in again.';
    }
    if (m.contains('failed host lookup') ||
        m.contains('socketexception') ||
        m.contains('network') ||
        m.contains('timed out')) {
      return _networkMessage();
    }
    return 'Something went wrong. Please try again.';
  }

  String _networkMessage() =>
      'Connection problem. Check your internet and try again.';

  // ---------------------------------------------------------------------------
  // EMAIL AUTH
  // ---------------------------------------------------------------------------

  Future<void> _submitEmail() async {
    if (_isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _snack('Email and password are required');
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _snack('That email address doesn\'t look valid.');
      return;
    }
    if (password.length < 6) {
      _snack('Password must be at least 6 characters');
      return;
    }
    if (!_isLogin && name.isEmpty) {
      _snack('Please enter your name');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
      } else {
        final res = await supabase.auth.signUp(
          email: email,
          password: password,
          data: {'full_name': name},
        );

        if (res.session == null) {
          if (!mounted) return;
          setState(() {
            _isLogin = true;
            _passwordController.clear();
          });
          _snack(
            'Account created. Check your email to confirm it, then sign in.',
            error: false,
          );
        }
      }
    } on AuthException catch (e) {
      _snack(_friendly(e));
    } catch (_) {
      _snack(_networkMessage());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_isLoading) return;

    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _snack('Enter your email address first, then tap this again.');
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _snack('That email address doesn\'t look valid.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      await supabase.auth.resetPasswordForEmail(email);
      _snack('Password reset link sent to $email', error: false);
    } on AuthException catch (e) {
      _snack(_friendly(e));
    } catch (_) {
      _snack(_networkMessage());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI PIECES
  // ---------------------------------------------------------------------------

  BoxDecoration get _glassFieldDecoration => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: 0.15),
        Colors.white.withValues(alpha: 0.05),
      ],
    ),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.1),
        blurRadius: 10,
        spreadRadius: -2,
      ),
    ],
  );

  Widget _buildGlassTextField({
    required String hintText,
    required IconData icon,
    required TextEditingController controller,
    bool isPassword = false,
    TextInputType? keyboardType,
    EdgeInsets margin = const EdgeInsets.only(bottom: 16),
  }) {
    return Container(
      margin: margin,
      decoration: _glassFieldDecoration,
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        enabled: !_isLoading,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          counterText: '',
          hintText: hintText,
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.7),
            size: 20,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 20),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton(String label, VoidCallback onPressed) {
    if (_isLoading) {
      return const SizedBox(
        height: 56,
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF2B44FF)),
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF4A64FF), Color(0xFF2B44FF)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2B44FF).withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: Text(
            label,
            key: ValueKey<String>(label),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  // --- email form -----------------------------------------------------------

  Widget _buildEmailForm() {
    return Column(
      key: ValueKey<bool>(_isLogin),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Full Name appears only in sign-up mode.
        AnimatedSize(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutQuart,
          alignment: Alignment.topCenter,
          child: !_isLogin
              ? _buildGlassTextField(
                  hintText: 'Full Name',
                  icon: Icons.person_outline,
                  controller: _nameController,
                )
              : const SizedBox.shrink(),
        ),
        _buildGlassTextField(
          hintText: 'E-mail address',
          icon: Icons.email_outlined,
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
        ),
        _buildGlassTextField(
          hintText: 'Password',
          icon: Icons.lock_outline,
          controller: _passwordController,
          isPassword: true,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          child: _isLogin
              ? Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isLoading ? null : _resetPassword,
                    child: Text(
                      'Forgot your password?',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 24),
        _buildPrimaryButton(
          _isLogin ? 'SIGN IN' : 'CREATE ACCOUNT',
          _submitEmail,
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _isLogin
                  ? "Don't have an account? "
                  : "Already have an account? ",
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
            GestureDetector(
              onTap: _isLoading
                  ? null
                  : () => setState(() => _isLogin = !_isLogin),
              child: Container(
                padding: const EdgeInsets.all(4),
                color: Colors.transparent,
                child: Text(
                  _isLogin ? 'Create Account' : 'Sign In',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  String get _headline => _isLogin ? 'Welcome!' : 'Create\naccount';

  String get _subhead =>
      _isLogin ? 'Sign in to your account' : 'Sign up to get started';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF151521),
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _liquidController,
            builder: (context, child) {
              final sine = math.sin(_liquidController.value * 2 * math.pi);
              final cosine = math.cos(_liquidController.value * 2 * math.pi);
              return Stack(
                children: [
                  Positioned(
                    top: -100 + (sine * 40),
                    right: -100 + (cosine * 40),
                    child: Container(
                      width: 400,
                      height: 400,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF2B44FF).withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -150 + (cosine * 60),
                    left: -100 + (sine * 60),
                    child: Container(
                      width: 400,
                      height: 400,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF4A64FF).withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 80.0, sigmaY: 80.0),
            child: Container(color: Colors.transparent),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),

                    // --- ARQELIN BRANDING HEADER ---
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.05),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/app_logo.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'ARQELIN',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w200,
                              letterSpacing: 6.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),

                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      transitionBuilder:
                          (Widget child, Animation<double> animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.0, 0.2),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                      child: Text(
                        _headline,
                        key: ValueKey<String>(_headline),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      child: Text(
                        _subhead,
                        key: ValueKey<String>(_subhead),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutQuart,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        transitionBuilder: (child, animation) =>
                            FadeTransition(opacity: animation, child: child),
                        child: _buildEmailForm(),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
