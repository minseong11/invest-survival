import 'package:flutter/material.dart';
import 'screens/scenario_screen.dart';
import 'theme/toss_theme.dart';

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
      theme: buildTossTheme(),
      home: const ScenarioScreen(),
    );
  }
}
