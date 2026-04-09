import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const NpsApp());
}

class NpsApp extends StatelessWidget {
  const NpsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NPS File Processor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
