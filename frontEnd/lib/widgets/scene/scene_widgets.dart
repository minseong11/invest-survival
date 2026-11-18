import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/market.dart';
import '../../theme/toss_theme.dart';
import '../toss/toss_widgets.dart';

// =============================================
// 장면(Scene) 공통 위젯
//  선택해야 하는 순간(시작 브리핑·카드 선택·위기 대응)을 글 대신 '장면'으로 보여주기 위한 조각들.
//   - MarketMood : 시장 등락을 날씨로 바꿔 한눈에 (☀️ 맑음 ~ ⛈️ 폭풍)
//   - MoodHero   : 날씨 그림을 크게 띄우는 원형 일러스트
//   - Sparkline  : 축·숫자 없는 흐름선 (아래 은은한 채움)
//   - AssetMoveTile : 종목 하나의 등락 타일 (이모지 + 이름 + 등락)
//   - SceneSheet : 게임 화면을 덮는 장면 (위: 장면 태그, 가운데: 내용, 아래: 고정 버튼)
//   - RevealScope / Reveal : 장면 안 요소를 순서대로 착착 보여 주는 연출 (화면을 누르면 바로 전부)
// =============================================

// ── 순서대로 나타나기 ──────────────────────────
//  RevealScope 안의 Reveal(order: n)은 n × step 뒤에 아래에서 살짝 올라오며 나타난다.
//  전체가 1초 안에 끝나도록 step은 짧게. 화면 어디든 누르면 남은 연출을 건너뛰고 바로 전부 보인다.
//  레이아웃은 처음부터 자리를 차지하므로(투명도만 바뀜) 버튼이 늦게 나타나도 화면이 밀리지 않는다.
//  RevealScope가 없으면(예: 결과 '한 번에 보기') 연출 없이 바로 보인다.
class RevealScope extends StatefulWidget {
  final Widget child;
  final Duration step;
  const RevealScope({
    super.key,
    required this.child,
    this.step = const Duration(milliseconds: 90),
  });

  @override
  State<RevealScope> createState() => _RevealScopeState();
}

class _RevealScopeState extends State<RevealScope> {
  bool _skipped = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (!_skipped) setState(() => _skipped = true);
      },
      child: _RevealInherited(
        skipped: _skipped,
        step: widget.step,
        child: widget.child,
      ),
    );
  }
}

class _RevealInherited extends InheritedWidget {
  final bool skipped;
  final Duration step;
  const _RevealInherited({
    required this.skipped,
    required this.step,
    required super.child,
  });

  @override
  bool updateShouldNotify(_RevealInherited old) => old.skipped != skipped;
}

class Reveal extends StatefulWidget {
  final int order;
  final Widget child;
  const Reveal({super.key, required this.order, required this.child});

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 320));
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: TossMotion.enter);
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context.dependOnInheritedWidgetOfExactType<_RevealInherited>();
    if (scope == null || scope.skipped) {
      _timer?.cancel();
      _c.value = 1;
      return;
    }
    if (_started) return;
    _started = true;
    _timer = Timer(scope.step * widget.order, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (_, child) => Opacity(
        opacity: _a.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - _a.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

// ── 시장 날씨 ─────────────────────────────────
class MarketMood {
  final String emoji;
  final String label;     // "흐림"
  final String line;      // "방향을 못 정하고 있어요"
  final List<Color> sky;  // 그림 배경 그라데이션

  const MarketMood(this.emoji, this.label, this.line, this.sky);

  static const _sunny  = [Color(0xFFFFF6E5), Color(0xFFFFE6BA)];
  static const _partly = [Color(0xFFFFF8EC), Color(0xFFE3EFFF)];
  static const _cloudy = [Color(0xFFF2F4F6), Color(0xFFDDE2E8)];
  static const _rain   = [Color(0xFFE8F3FF), Color(0xFFCFE2FA)];
  static const _storm  = [Color(0xFFE5E8EB), Color(0xFFC3CAD4)];

  /// 여러 날에 걸친 등락(%) — 시작 전 20거래일, 게임 시작 후 등
  static MarketMood period(double change) {
    if (change >= 5)  return const MarketMood('☀️', '맑음', '시장이 활짝 웃고 있어요', _sunny);
    if (change >= 1)  return const MarketMood('🌤️', '대체로 맑음', '조금씩 오르고 있어요', _partly);
    if (change > -1)  return const MarketMood('☁️', '흐림', '방향을 못 정하고 있어요', _cloudy);
    if (change > -5)  return const MarketMood('🌧️', '비', '조금씩 내려가고 있어요', _rain);
    return const MarketMood('⛈️', '폭풍', '크게 흔들리고 있어요', _storm);
  }

  /// 하루 등락(%)
  static MarketMood day(double change) {
    if (change >= 2)    return const MarketMood('☀️', '맑음', '크게 올랐어요', _sunny);
    if (change >= 0.5)  return const MarketMood('🌤️', '대체로 맑음', '조금 올랐어요', _partly);
    if (change > -0.5)  return const MarketMood('☁️', '흐림', '잠잠한 하루예요', _cloudy);
    if (change > -2)    return const MarketMood('🌧️', '비', '조금 내렸어요', _rain);
    return const MarketMood('⛈️', '폭풍', '크게 떨어졌어요', _storm);
  }
}

// ── 날씨 그림 (원 안에 큰 이모지, 등장할 때 톡 튀어나옴) ──
class MoodHero extends StatelessWidget {
  final MarketMood mood;
  final double size;
  const MoodHero({super.key, required this.mood, this.size = 140});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutBack,
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: mood.sky,
          ),
        ),
        child: Text(mood.emoji, style: TextStyle(fontSize: size * 0.48)),
      ),
    );
  }
}

// ── 흐름선 ────────────────────────────────────
class Sparkline extends StatelessWidget {
  final List<double> values;
  final double height;
  final double strokeWidth;
  final bool fill;
  const Sparkline({
    super.key,
    required this.values,
    this.height = 64,
    this.strokeWidth = 2.4,
    this.fill = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, t, __) => CustomPaint(
          painter: _SparklinePainter(values, strokeWidth, fill, t),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final double strokeWidth;
  final bool fill;
  final double progress; // 0~1: 왼쪽부터 그려지는 연출
  _SparklinePainter(this.values, this.strokeWidth, this.fill, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0) return;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final range = (max - min).abs() < 1e-9 ? 1.0 : max - min;
    final up = values.last >= values.first;
    final color = up ? TossColors.red500 : TossColors.blue500;
    final pad = strokeWidth;

    final n = values.length;
    final shown = (2 + ((n - 2) * progress).round()).clamp(2, n);
    Offset at(int i) => Offset(
          size.width * i / (n - 1),
          pad + (size.height - pad * 2) * (1 - (values[i] - min) / range),
        );

    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (int i = 1; i < shown; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }

    if (fill) {
      final area = Path.from(line)
        ..lineTo(at(shown - 1).dx, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    // 끝점
    canvas.drawCircle(at(shown - 1), strokeWidth * 1.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.progress != progress;
}

// ── 종목 이모지 ───────────────────────────────
String assetEmoji(String ticker) => switch (priceTicker(ticker)) {
      '^SPX'   => '📈',
      '^NDX'   => '💻',
      'XAUUSD' => '🪙',
      'USO'    => '🛢️',
      'AAPL'   => '🍎',
      'TLT'    => '🏦',
      _        => '💹',
    };

// ── 종목 등락 타일 ─────────────────────────────
class AssetMoveTile extends StatelessWidget {
  final String ticker;
  final String name;
  final double change;
  const AssetMoveTile({
    super.key,
    required this.ticker,
    required this.name,
    required this.change,
  });

  @override
  Widget build(BuildContext context) {
    final up = change >= 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: TossColors.grey50,
        borderRadius: BorderRadius.circular(TossRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(assetEmoji(ticker), style: const TextStyle(fontSize: 26)),
              const Spacer(),
              Icon(
                up ? Icons.north_east_rounded : Icons.south_east_rounded,
                size: 18,
                color: TossColors.rate(change),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: TossColors.grey600)),
          const SizedBox(height: 1),
          Text(formatSigned(change),
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: TossColors.rate(change),
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

// ── 장면 태그 ("📅 25라운드 · 9월 26일") ───────
class SceneTag extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const SceneTag(this.text,
      {super.key, this.bg = TossColors.grey100, this.fg = TossColors.grey700});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

// ── 장면 시트 ─────────────────────────────────
//  게임 화면 위로 올라오는 흰 시트. 내용은 스크롤되고, 확정 버튼은 항상 아래에 고정된다.
//  (기존: 선택지가 게임 화면 맨 아래 붙어 있어 고를 때마다 스크롤해서 내려가야 했다)
class SceneSheet extends StatelessWidget {
  final Widget? tag;
  final Widget? trailing;     // 오른쪽 위 (건너뛰기 등)
  final Widget body;          // 스크롤되는 내용
  final Widget bottom;        // 고정 버튼
  final bool fullScreen;      // 시작 브리핑: 화면 전체
  final bool scrollBody;      // false면 body가 스스로 스크롤을 가진다 (넘겨 보는 장면)
  final ScrollController? controller;

  const SceneSheet({
    super.key,
    required this.body,
    required this.bottom,
    this.tag,
    this.trailing,
    this.fullScreen = false,
    this.scrollBody = true,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Material(
      color: TossColors.white,
      borderRadius: fullScreen
          ? BorderRadius.zero
          : const BorderRadius.vertical(top: Radius.circular(TossRadius.sheet)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (!fullScreen)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: TossColors.grey200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          if (tag != null || trailing != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
              child: Row(
                children: [
                  if (tag != null) tag!,
                  const Spacer(),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          Expanded(
            child: scrollBody
                ? SingleChildScrollView(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: body,
                  )
                : body,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottomInset),
            child: bottom,
          ),
        ],
      ),
    );
  }
}
