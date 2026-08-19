import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pages/auth_gate.dart';
import 'pages/splash_screen.dart';

// 1. We create a global 'light switch' for the app theme.
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://usabltioswnfzkmflhkb.supabase.co', // Keep your actual URL!
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVzYWJsdGlvc3duZnprbWZsaGtiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY5ODYyNTAsImV4cCI6MjEwMjU2MjI1MH0.UidHuQ_kdsiKTkXYcfXV2IksEBY2xw6qiYYDQ9nxSQs', // Keep your actual Key!
  );

  runApp(const ProductivityTrackerApp());
}

class ProductivityTrackerApp extends StatelessWidget {
  const ProductivityTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 2. We wrap our app in a listener that watches the 'light switch'
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, ThemeMode currentMode, child) {
        return MaterialApp(
          title: 'Arqelin',
          debugShowCheckedModeBanner: false,
          theme: ThemeData.light(useMaterial3: true), // Base Light Theme
          darkTheme: ThemeData.dark(useMaterial3: true), // Base Dark Theme
          themeMode:
              currentMode, // Dynamically changes when we flip the switch!
          home: const SplashScreen(),
        );
      },
    );
  }
}
