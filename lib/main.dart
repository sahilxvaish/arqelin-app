import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/auth_gate.dart';
import 'pages/splash_screen.dart';

// 1. We create a global 'light switch' for the app theme.
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- 2. LOAD SAVED THEME ---
  final prefs = await SharedPreferences.getInstance();
  final isLightMode = prefs.getBool('isLightMode') ?? false;
  themeNotifier.value = isLightMode ? ThemeMode.light : ThemeMode.dark;

  // --- 3. AUTO-SAVE THEME CHANGES ---
  themeNotifier.addListener(() {
    prefs.setBool('isLightMode', themeNotifier.value == ThemeMode.light);
  });

  // --- 4. INITIALIZE SUPABASE ---
  await Supabase.initialize(
    url: 'https://usabltioswnfzkmflhkb.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVzYWJsdGlvc3duZnprbWZsaGtiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY5ODYyNTAsImV4cCI6MjEwMjU2MjI1MH0.UidHuQ_kdsiKTkXYcfXV2IksEBY2xw6qiYYDQ9nxSQs',
  );

  runApp(const ProductivityTrackerApp());
}

class ProductivityTrackerApp extends StatelessWidget {
  const ProductivityTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 5. We wrap our app in a listener that watches the 'light switch'
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, ThemeMode currentMode, child) {
        return MaterialApp(
          title: 'Arqelin',
          debugShowCheckedModeBanner: false,

          // Customizing the base themes slightly to match ARQELIN's premium look
          theme: ThemeData(
            brightness: Brightness.light,
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFFE8E8F0),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2B44FF),
              brightness: Brightness.light,
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFF101018),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2B44FF),
              brightness: Brightness.dark,
            ),
          ),

          themeMode:
              currentMode, // Dynamically changes and persists when flipped!
          home: const SplashScreen(),
        );
      },
    );
  }
}
