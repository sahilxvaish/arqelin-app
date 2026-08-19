import 'dart:ui';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import 'daily_tasks_page.dart';
import 'progress_page.dart';
import 'history_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  int _currentIndex = 0;
  late AnimationController _bgController;

  // --- USER DATA STATE ---
  String _fullName = 'Arqelin User';
  String _email = 'Loading...';
  String? _avatarUrl;

  // --- ANIMATION STATE ---
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat(reverse: true);

    _loadUserData();
  }

  void _loadUserData() {
    final user = supabase.auth.currentUser;
    if (user != null) {
      setState(() {
        _email = user.email ?? 'No Email';
        _fullName = user.userMetadata?['full_name'] ?? 'Arqelin User';
        _avatarUrl = user.userMetadata?['avatar_url'];
      });
    }
  }

  // --- CHANGE PROFILE PHOTO LOGIC (CLOUD ENABLED) ---
  Future<void> _changeProfilePhoto() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);

      if (image != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Uploading profile photo...')),
        );

        final user = supabase.auth.currentUser!;
        final imageExtension = image.path.split('.').last;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final imagePath = '${user.id}/profile-$timestamp.$imageExtension';

        await supabase.storage
            .from('avatars')
            .upload(
              imagePath,
              File(image.path),
              fileOptions: const FileOptions(upsert: true),
            );

        final imageUrl = supabase.storage
            .from('avatars')
            .getPublicUrl(imagePath);

        await supabase.auth.updateUser(
          UserAttributes(
            data: {'avatar_url': imageUrl, 'full_name': _fullName},
          ),
        );

        setState(() {
          _avatarUrl = imageUrl;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated successfully!')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error updating photo: $e')));
    }
  }

  // --- SMOOTH LOGOUT LOGIC & DIALOG ---
  Future<void> _handleLogoutSequence(bool isDark, Color textColor) async {
    // 1. Show Confirmation Dialog
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF151521).withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.1),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.redAccent.withValues(alpha: 0.1),
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      color: Colors.redAccent,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Ready to leave?',
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You are about to securely log out of your Arqelin account.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: textColor.withValues(alpha: 0.6),
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(context, false), // Cancel
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.outfit(
                            color: textColor.withValues(alpha: 0.6),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () =>
                            Navigator.pop(context, true), // Confirm
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withValues(
                            alpha: 0.1,
                          ),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Colors.redAccent.withValues(alpha: 0.3),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          'Log Out',
                          style: GoogleFonts.outfit(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // 2. If confirmed, trigger the smooth exit animation
    if (confirm == true) {
      // Close the side drawer first
      Navigator.pop(context);

      // Trigger the full-screen overlay animation
      setState(() {
        _isLoggingOut = true;
      });

      // Let the beautiful animation play for a second before we actually kill the session
      await Future.delayed(const Duration(milliseconds: 1500));
      await supabase.auth.signOut();
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    super.dispose();
  }

  List<Widget> _buildPages(bool isDark) {
    return [const DailyTasksPage(), const ProgressPage(), const HistoryPage()];
  }

  Widget _buildGlassNavItem(IconData icon, int index, bool isDark) {
    final isSelected = _currentIndex == index;
    final activeColor = isDark ? Colors.white : Colors.black87;
    final inactiveColor = isDark
        ? Colors.white.withValues(alpha: 0.4)
        : Colors.black.withValues(alpha: 0.3);

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          transform: Matrix4.identity()..scale(isSelected ? 1.2 : 1.0),
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: isSelected ? activeColor : inactiveColor,
            size: 28,
            shadows: isSelected
                ? [
                    Shadow(
                      color: activeColor.withValues(alpha: 0.5),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildGlassThemeToggle(bool isDark) {
    return GestureDetector(
      onTap: () {
        themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
      },
      child: Container(
        width: 100,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.1),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 500),
              curve: Curves.elasticOut,
              top: 4,
              bottom: 4,
              left: isDark ? 52 : 4,
              right: isDark ? 4 : 52,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.white,
                  boxShadow: isDark
                      ? []
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 5,
                          ),
                        ],
                ),
                child: Icon(
                  isDark ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                  size: 20,
                  color: isDark ? Colors.white : Colors.orangeAccent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF101018) : const Color(0xFFE8E8F0);
    final textColor = isDark ? Colors.white : Colors.black87;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: bgColor,

          drawer: Drawer(
            backgroundColor: Colors.transparent,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30.0, sigmaY: 30.0),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF151521).withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.6),
                  border: Border(
                    right: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.05),
                      width: 1,
                    ),
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(height: 40),
                      Text(
                        'Settings',
                        style: GoogleFonts.outfit(
                          fontSize: 24,
                          fontWeight: FontWeight.w300,
                          color: textColor,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 30),

                      // --- USER PROFILE SECTION ---
                      GestureDetector(
                        onTap: _changeProfilePhoto,
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.05),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : Colors.black.withValues(alpha: 0.1),
                              width: 2,
                            ),
                            image: _avatarUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(_avatarUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: _avatarUrl == null
                              ? Icon(
                                  Icons.person_outline,
                                  size: 40,
                                  color: textColor.withValues(alpha: 0.5),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _fullName,
                        style: GoogleFonts.outfit(
                          color: textColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _email,
                        style: GoogleFonts.outfit(
                          color: textColor.withValues(alpha: 0.6),
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      const SizedBox(height: 40),

                      // --- THEME TOGGLE ---
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Theme',
                              style: GoogleFonts.outfit(
                                color: textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            _buildGlassThemeToggle(isDark),
                          ],
                        ),
                      ),
                      const Spacer(),

                      // --- DEVELOPER NOTE ---
                      Text(
                        'Developed By Sahil Vaish',
                        style: GoogleFonts.outfit(
                          color: textColor.withValues(alpha: 0.4),
                          fontSize: 12,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // --- LOGOUT BUTTON ---
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 24.0,
                          right: 24.0,
                          bottom: 24.0,
                        ),
                        child: GestureDetector(
                          onTap: () => _handleLogoutSequence(isDark, textColor),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: Colors.redAccent.withValues(alpha: 0.1),
                              border: Border.all(
                                color: Colors.redAccent.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.logout,
                                  color: Colors.redAccent,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Logout',
                                  style: GoogleFonts.outfit(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: textColor),
            title: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : Colors.black.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.black.withValues(alpha: 0.08),
                      width: 1.0,
                    ),
                  ),
                  child: Text(
                    'ARQELIN',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w200,
                      color: textColor,
                      letterSpacing: 4.0,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
            centerTitle: true,
          ),

          body: Stack(
            children: [
              AnimatedBuilder(
                animation: _bgController,
                builder: (context, child) {
                  return Positioned(
                    bottom: -100,
                    left: -50 + (_bgController.value * 100),
                    child: Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? const Color(0xFF2B44FF).withValues(alpha: 0.15)
                            : const Color(0xFF2B44FF).withValues(alpha: 0.10),
                      ),
                    ),
                  );
                },
              ),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                switchInCurve: Curves.easeOutQuart,
                switchOutCurve: Curves.easeInQuart,
                child: Container(
                  key: ValueKey<int>(_currentIndex),
                  child: _buildPages(isDark)[_currentIndex],
                ),
              ),

              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(
                    bottom: 32.0,
                    left: 32.0,
                    right: 32.0,
                  ),
                  child: Container(
                    height: 75,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(40),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black.withValues(alpha: 0.3)
                              : Colors.black.withValues(alpha: 0.1),
                          blurRadius: 30,
                          spreadRadius: 5,
                          offset: const Offset(0, 15),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 25.0, sigmaY: 25.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(40),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : Colors.black.withValues(alpha: 0.1),
                              width: 1.2,
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                isDark
                                    ? Colors.white.withValues(alpha: 0.20)
                                    : Colors.black.withValues(alpha: 0.10),
                                isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.02),
                              ],
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildGlassNavItem(
                                Icons.check_circle_outline,
                                0,
                                isDark,
                              ),
                              _buildGlassNavItem(
                                Icons.insights_outlined,
                                1,
                                isDark,
                              ),
                              _buildGlassNavItem(Icons.history, 2, isDark),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // --- FULL SCREEN LOGOUT ANIMATION OVERLAY ---
        if (_isLoggingOut)
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 25 * value,
                    sigmaY: 25 * value,
                  ),
                  child: Container(
                    color: bgColor.withValues(alpha: 0.7 * value),
                    child: Center(
                      child: Opacity(
                        opacity: value,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF2B44FF),
                              ),
                            ),
                            const SizedBox(height: 30),
                            Text(
                              'Logging out securely...',
                              style: GoogleFonts.outfit(
                                color: textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w300,
                                letterSpacing: 1.5,
                                decoration: TextDecoration
                                    .none, // FIX: Removes the yellow underline!
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
