import 'package:flutter/material.dart';

// =============================================
// 토스 스타일 디자인 토큰
//  - 회색 배경(grey100) 위에 흰 섹션을 쌓고, 테두리 대신 여백으로 구역을 나눔
//  - 포인트 색은 blue500 하나. 수익은 빨강, 손실은 파랑 (한국 증시 관례)
//  - 값은 토스 화면에서 널리 쓰이는 색을 기준으로 맞춘 추정치 (공식 TDS 값 아님)
// =============================================
class TossColors {
  TossColors._();

  // 포인트
  static const blue500 = Color(0xFF3182F6);
  static const blue600 = Color(0xFF2272EB);
  static const blue50  = Color(0xFFE8F3FF);

  // 회색 단계
  static const grey50  = Color(0xFFF9FAFB);
  static const grey100 = Color(0xFFF2F4F6);
  static const grey200 = Color(0xFFE5E8EB);
  static const grey300 = Color(0xFFD1D6DB);
  static const grey400 = Color(0xFFB0B8C1);
  static const grey500 = Color(0xFF8B95A1);
  static const grey600 = Color(0xFF6B7684);
  static const grey700 = Color(0xFF4E5968);
  static const grey800 = Color(0xFF333D4B);
  static const grey900 = Color(0xFF191F28);

  // 의미 색
  static const red500    = Color(0xFFF04452); // 수익·상승
  static const red50     = Color(0xFFFFEEEE);
  static const green500  = Color(0xFF03B26C); // 예측 완료·적중
  static const green50   = Color(0xFFE5F8EF);
  static const orange500 = Color(0xFFFE9800); // 카드 발동 강조

  static const white = Color(0xFFFFFFFF);
  static const background = grey100;

  // 수익률 색: 0 이상 빨강, 음수 파랑
  static Color rate(double v) => v >= 0 ? red500 : blue500;
}

class TossText {
  TossText._();

  static const _tabular = [FontFeature.tabularFigures()];

  static const display = TextStyle(
      fontSize: 28, fontWeight: FontWeight.w700, height: 1.3,
      letterSpacing: -0.6, color: TossColors.grey900, fontFeatures: _tabular);
  static const title1 = TextStyle(
      fontSize: 26, fontWeight: FontWeight.w700, height: 1.35,
      letterSpacing: -0.5, color: TossColors.grey900);
  static const title2 = TextStyle(
      fontSize: 20, fontWeight: FontWeight.w700, height: 1.4,
      letterSpacing: -0.3, color: TossColors.grey900);
  static const title3 = TextStyle(
      fontSize: 17, fontWeight: FontWeight.w700, height: 1.45,
      letterSpacing: -0.2, color: TossColors.grey900);
  static const body1 = TextStyle(
      fontSize: 16, fontWeight: FontWeight.w500, height: 1.5,
      color: TossColors.grey900);
  static const body2 = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w600, height: 1.45,
      color: TossColors.grey900);
  static const sub = TextStyle(
      fontSize: 14, fontWeight: FontWeight.w400, height: 1.5,
      color: TossColors.grey600);
  static const caption = TextStyle(
      fontSize: 13, fontWeight: FontWeight.w400, height: 1.45,
      color: TossColors.grey600);
  static const small = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w500, height: 1.4,
      color: TossColors.grey500);
  static const number = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w600,
      color: TossColors.grey900, fontFeatures: _tabular);
}

class TossRadius {
  TossRadius._();
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const sheet = 24.0;
}

class TossMotion {
  TossMotion._();
  static const fast   = Duration(milliseconds: 120);
  static const base   = Duration(milliseconds: 250);
  static const slow   = Duration(milliseconds: 450);
  static const enter  = Curves.easeOutCubic;
  static const spring = Curves.easeOutBack;
}

ThemeData buildTossTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: TossColors.blue500,
      primary: TossColors.blue500,
      surface: TossColors.white,
    ),
    scaffoldBackgroundColor: TossColors.background,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: TossColors.grey900,
      displayColor: TossColors.grey900,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: TossColors.blue500,
      linearTrackColor: TossColors.blue50,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: TossColors.grey800,
      contentTextStyle: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TossRadius.md)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: TossColors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: false,
    ),
  );
}
