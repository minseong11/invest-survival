import 'package:flutter/material.dart';
import '../models/market.dart';
import '../models/round_data.dart';
import '../theme/toss_theme.dart';
import 'toss/toss_widgets.dart';

// =============================================
// (#125) 종목별 흐름 칩 — 차트 아래
//  종목마다 게임 시작 후 등락을 보여주고, 누르면 차트에 그 종목 선을 겹쳐 그린다.
//  갖고 있지 않은 종목도 흐름을 보고 그 종목을 사는 카드를 고를지 판단할 수 있게.
//  S&P500은 기준선이라 차트에 항상 그려진다 (누를 수 없음).
// =============================================

/// 차트에 겹쳐 그릴 때의 색 — 내 자산 선(빨강·파랑), 뉴스 점(주황·초록·회색)과 겹치지 않게 고름
const Map<String, Color> kTickerColors = {
  '^SPX': TossColors.grey400,
  '^NDX': Color(0xFF8B5CF6),   // 보라
  'XAUUSD': Color(0xFFD4A017), // 금색
  'USO': Color(0xFF8D6E63),    // 갈색
  'AAPL': Color(0xFFEC4899),   // 분홍
  'TLT': Color(0xFF14B8A6),    // 청록
};

class MarketChips extends StatelessWidget {
  final List<RoundData> rounds;
  final Set<String> selected;          // 차트에 겹쳐 그리는 종목
  final ValueChanged<String> onToggle;

  const MarketChips({
    super.key,
    required this.rounds,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final items = <(String, double)>[
      for (final t in kMarketTickers)
        if (changeSinceStart(rounds, t) case final double rate) (t, rate),
    ];
    // S&P500만 있으면(예전 서버 응답) 차트와 같은 정보라 생략
    if (items.length < 2) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('종목별 흐름 · 게임 시작 후  (누르면 차트에 겹쳐 보여요)',
              style: TossText.small),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final (t, rate) in items) _chip(t, rate)],
          ),
        ],
      ),
    );
  }

  Widget _chip(String ticker, double rate) {
    final isBase = ticker == '^SPX';
    final on = !isBase && selected.contains(ticker);
    final color = kTickerColors[ticker] ?? TossColors.grey500;

    final chip = AnimatedContainer(
      duration: TossMotion.fast,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: on ? color.withValues(alpha: 0.10) : TossColors.grey50,
        borderRadius: BorderRadius.circular(TossRadius.sm + 2),
        border: Border.all(
            color: on ? color : Colors.transparent, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _marker(isBase, on, color),
          const SizedBox(width: 6),
          Text(kTickerNames[ticker] ?? ticker,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: TossColors.grey700)),
          const SizedBox(width: 6),
          Text(formatSigned(rate),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: TossColors.rate(rate),
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );

    if (isBase) return chip;
    return Semantics(
      button: true,
      selected: on,
      child: Pressable(
        onTap: () => onToggle(ticker),
        scale: 0.96,
        child: chip,
      ),
    );
  }

  // 왼쪽 표시: S&P500은 기준선(짧은 회색 선), 나머지는 켜면 그 색의 선, 끄면 그 색의 빈 동그라미
  Widget _marker(bool isBase, bool on, Color color) {
    if (isBase) {
      return Container(width: 12, height: 2, color: TossColors.grey400);
    }
    return AnimatedContainer(
      duration: TossMotion.fast,
      width: on ? 12 : 8,
      height: on ? 3 : 8,
      decoration: BoxDecoration(
        color: on ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(on ? 2 : 4),
        border: on ? null : Border.all(color: color, width: 1.5),
      ),
    );
  }
}
