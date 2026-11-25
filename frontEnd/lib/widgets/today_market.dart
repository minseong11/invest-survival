import 'package:flutter/material.dart';
import '../models/market.dart';
import '../models/round_data.dart';
import '../theme/toss_theme.dart';
import 'scene/scene_widgets.dart';
import 'toss/toss_widgets.dart';

// =============================================
// (#125) 오늘 시장 — 카드 선택·위기 대응 라운드에서 고르기 전에 보여 준다
//  카드와 위기 대응은 그날 종가로 매매하고, AI 예측도 그날 종가까지의 시장을 보고 판단한다.
//  기존에는 화면이 전날까지만 보여 줘서 AI가 플레이어보다 하루를 더 알았다
//  (실제 플레이 영상: 코로나 25라운드에서 화면은 3/23, AI 설명은 3/24 반등(+9.4%)까지 반영).
// =============================================
class TodayMarketCard extends StatelessWidget {
  final RoundData today;   // 그날 날짜·종목별 가격·전날 대비 등락 (서버 nextEventMarket, 1라운드는 시작 응답)
  final String? caption;

  const TodayMarketCard({super.key, required this.today, this.caption});

  // '2020-03-24' → '3월 24일'
  static String koreanDate(String date) {
    final parts = date.split('-');
    if (parts.length < 3) return date;
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    return (m == null || d == null) ? date : '$m월 $d일';
  }

  @override
  Widget build(BuildContext context) {
    final spx = today.getPrice('^SPX');
    final mood = spx == null ? null : MarketMood.day(spx.changeRate);
    final others = <(String, double)>[
      for (final t in kMarketTickers)
        if (t != '^SPX')
          if (today.getPrice(t) case final p?) (t, p.changeRate),
    ];

    // (장면 개편) 글 대신 그날의 '시장 날씨' 그림 + 종목 칩
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: TossColors.grey50,
        borderRadius: BorderRadius.circular(TossRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (mood != null) ...[
                MoodHero(mood: mood, size: 56),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('오늘 ${koreanDate(today.date)} 시장',
                        style: TossText.small),
                    const SizedBox(height: 2),
                    if (spx != null)
                      Row(
                        children: [
                          const Text('S&P500 ',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: TossColors.grey800)),
                          Text(formatSigned(spx.changeRate),
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: TossColors.rate(spx.changeRate),
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ])),
                        ],
                      ),
                    if (mood != null)
                      Text('${mood.label} · ${mood.line}',
                          style: TossText.caption),
                  ],
                ),
              ),
            ],
          ),
          if (others.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final (t, rate) in others) _chip(t, rate)],
            ),
          ],
          if (caption != null) ...[
            const SizedBox(height: 10),
            Text(caption!, style: TossText.small),
          ],
        ],
      ),
    );
  }

  Widget _chip(String ticker, double rate) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: TossColors.white,
        borderRadius: BorderRadius.circular(TossRadius.sm + 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(assetEmoji(ticker), style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
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
  }
}
