import 'package:flutter/material.dart';
import 'screens/scenario_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '투자 서바이벌',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3C3489),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFAF9F5),
      ),
      home: const ScenarioScreen(), // ← HomeScreen 대신 ScenarioScreen
    );
  }
}
