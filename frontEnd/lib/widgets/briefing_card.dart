import 'package:flutter/material.dart';
import '../models/briefing.dart';
import '../theme/toss_theme.dart';
import 'toss/toss_widgets.dart';

// =============================================
// (#125) 시작 전 시장 브리핑 — 첫 카드를 고르기 전에만 보인다
//  첫 선택은 결과에 미치는 영향이 가장 큰데, 게임 중 시장 흐름이 아직 없어 정보 없이 골라야 했다.
//  게임 시작일 직전 20거래일의 종목별 등락과 시나리오 배경을 보여준다 (게임 시작 전 정보만).
// =============================================
class BriefingCard extends StatelessWidget {
  final Briefing briefing;
  const BriefingCard({super.key, required this.briefing});

  @override
  Widget build(BuildContext context) {
    final hasMarket = briefing.days > 0 && briefing.assets.isNotEmpty;

    return TossSection(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('시작 전 시장 브리핑', style: TossText.title3),
          if (briefing.intro.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(briefing.intro,
                style: TossText.sub.copyWith(color: TossColors.grey700)),
          ],
          if (hasMarket) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text('직전 ${briefing.days}거래일 동안',
                      style: TossText.small),
                ),
                if (briefing.spxSeries.length >= 2) ...[
                  const Text('S&P500', style: TossText.small),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 72,
                    height: 22,
                    child: CustomPaint(
                      painter: _SparklinePainter(briefing.spxSeries),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in briefing.assets) _assetChip(a),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _assetChip(BriefingAsset a) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: TossColors.grey50,
        borderRadius: BorderRadius.circular(TossRadius.sm + 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(a.name,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: TossColors.grey700)),
          const SizedBox(width: 6),
          Text(formatSigned(a.changeRate),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: TossColors.rate(a.changeRate),
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

// 작은 추세선 (축·숫자 없이 모양만)
class _SparklinePainter extends CustomPainter {
  final List<double> values;
  _SparklinePainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final range = (max - min).abs() < 1e-9 ? 1.0 : max - min;
    final up = values.last >= values.first;

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - (values[i] - min) / range * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = up ? TossColors.red500 : TossColors.blue500
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.values != values;
}
