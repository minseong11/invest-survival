import 'package:flutter/material.dart';
import 'screens/scenario_screen.dart';
import 'theme/toss_theme.dart';
import 'widgets/app_frame.dart';
import 'widgets/emoji_preload.dart';

void main() {
  runApp(const MyApp());
  // 웹: 첫 화면이 뜬 직후 이모지 글꼴을 미리 받아, 시작 브리핑에서 네모로 보이지 않게
  preloadEmojiFonts();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '투자 서바이벌',
      theme: buildTossTheme(),
      // (#125) 넓은 화면(노트북 브라우저 등)에서는 휴대폰 폭으로 가운데에
      builder: (context, child) => AppFrame(child: child ?? const SizedBox.shrink()),
      home: const ScenarioScreen(),
    );
  }
}
