import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/market.dart';
import '../models/round_data.dart';
import '../theme/toss_theme.dart';
import 'market_chips.dart';

// =============================================
// (#125) 세로축 범위·눈금 계산
// 기존에는 눈금 간격을 (범위 ÷ 4)로 잡아 시작점이 간격의 배수가 아니었고,
// 그래서 맨 아래 눈금과 그 위 눈금이 겹쳐 보였다 (예: -18%와 -15%).
// 간격을 1·2·5·10… 단위로 고르고 위아래 끝을 그 배수에 맞춰 눈금이 일정하게 놓이게 한다.
// =============================================
class ChartAxis {
  final double min;
  final double max;
  final double interval;
  const ChartAxis(this.min, this.max, this.interval);
}

ChartAxis computeChartAxis(double minValue, double maxValue) {
  // 값이 축 끝에 붙지 않도록 여유를 둔다 (0%는 항상 포함)
  final rawMin = (minValue < 0 ? minValue : 0) * 1.15 - 2;
  final rawMax = (maxValue > 0 ? maxValue : 0) * 1.15 + 2;
  final range  = rawMax - rawMin;

  const steps = [1.0, 2.0, 5.0, 10.0, 20.0, 25.0, 50.0, 100.0, 200.0, 500.0];
  var interval = steps.last;
  for (final s in steps) {
    if (range / s <= 5) {   // 눈금이 5칸을 넘지 않는 가장 작은 간격
      interval = s;
      break;
    }
  }
  final min = (rawMin / interval).floorToDouble() * interval;
  final max = (rawMax / interval).ceilToDouble() * interval;
  return ChartAxis(min, max, interval);
}

class StockChart extends StatefulWidget {
  final List<RoundData> rounds;
  final double initialAsset;
  // (12주차) 카드를 고른 라운드의 위치(0부터) — 내 자산 선 위에 흰 점으로 표시
  final Set<int> cardIndexes;
  // (#125) 위기 대응을 한 라운드의 위치(0부터) — 내 자산 선 위에 주황 네모로 표시
  final Set<int> decisionIndexes;
  // (#125) S&P500 말고 겹쳐 그릴 종목 (차트 아래 종목 칩에서 고름). 색은 kTickerColors
  final Set<String> extraTickers;

  const StockChart({
    super.key,
    required this.rounds,
    this.initialAsset = 10000000,
    this.cardIndexes = const {},
    this.decisionIndexes = const {},
    this.extraTickers = const {},
  });

  @override
  State<StockChart> createState() => _StockChartState();
}

class _StockChartState extends State<StockChart> {
  static const _assetKey = '내 자산';

  // 종목의 첫 가격 대비 등락률(%) 선
  List<FlSpot> _tickerSpots(String ticker) => [
        for (final (i, rate) in changeSeries(widget.rounds, ticker))
          FlSpot(i.toDouble(), rate),
      ];

  List<FlSpot> get _spxSpots => _tickerSpots('^SPX');

  // 겹쳐 그릴 종목 (화면 순서대로, 가격이 없는 종목은 뺀다)
  List<(String, List<FlSpot>)> get _extraSeries => [
        for (final t in kMarketTickers)
          if (t != '^SPX' && widget.extraTickers.contains(t))
            if (_tickerSpots(t) case final spots when spots.isNotEmpty) (t, spots),
      ];

  List<FlSpot> get _assetSpots {
    final spots = <FlSpot>[];
    for (int i = 0; i < widget.rounds.length; i++) {
      final asset = widget.rounds[i].roundAsset;
      if (asset != null) {
        spots.add(FlSpot(
            i.toDouble(),
            (asset - widget.initialAsset) / widget.initialAsset * 100));
      }
    }
    return spots;
  }

  // 뉴스가 나온 날의 색 (위험: 주황 / 긍정: 초록 / 그 외: 회색). 뉴스 없으면 null
  Color? _newsColor(int idx) {
    if (idx < 0 || idx >= widget.rounds.length) return null;
    final news = widget.rounds[idx].news;
    if (news.isEmpty) return null;
    if (news.any((n) => n.level == 'danger')) return TossColors.orange500;
    if (news.any((n) => n.level == 'positive')) return TossColors.green500;
    return TossColors.grey500;
  }

  ChartAxis get _axis {
    double min = 0, max = 0;
    for (final s in [
      ..._spxSpots,
      ..._assetSpots,
      for (final (_, spots) in _extraSeries) ...spots,
    ]) {
      if (s.y < min) min = s.y;
      if (s.y > max) max = s.y;
    }
    return computeChartAxis(min, max);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rounds.isEmpty) {
      return const Center(
        child: Text('데이터 없음',
            style: TossText.caption),
      );
    }

    final spxSpots   = _spxSpots;
    final assetSpots = _assetSpots;
    final extras     = _extraSeries;
    final hasAsset   = assetSpots.isNotEmpty;
    // lineBarsData 순서와 같은 이름 목록 (툴팁에서 선을 구분할 때 사용)
    final seriesKeys = [
      for (final (t, _) in extras) t,
      if (spxSpots.isNotEmpty) '^SPX',
      if (hasAsset) _assetKey,
    ];
    // 내 자산 선: 지금 수익이면 빨강, 손실이면 파랑 (토스증권 방식)
    final assetColor = hasAsset ? TossColors.rate(assetSpots.last.y) : TossColors.red500;
    final axis       = _axis;
    final minY       = axis.min;
    final maxY       = axis.max;
    final interval   = axis.interval;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 범례 (항목이 많아 좁은 화면에서는 두 줄로 넘어감)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            runSpacing: 4,
            children: [
              if (widget.cardIndexes.isNotEmpty)
                _legendRing(assetColor, '카드 선택'),
              if (widget.decisionIndexes.isNotEmpty)
                _legendSquare(TossColors.orange500, '위기 대응'),
              _legendItem(TossColors.orange500, '뉴스'),
              if (hasAsset) _legendItem(assetColor, '내 자산'),
              _legendItemDash(TossColors.grey400, 'S&P 500'),
            ],
          ),
        ),

        Expanded(
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              minX: 0,
              maxX: (widget.rounds.length - 1).toDouble(),
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => TossColors.grey800,
                  // (#125) 겹쳐 본 종목이 많으면 툴팁이 넓어져 화면 오른쪽 끝에서 잘리지 않게
                  fitInsideHorizontally: true,
                  getTooltipItems: (spots) {
                    // (#125) 겹쳐 그린 종목이 있으면 선마다 한 줄씩 (색 점 + 이름 + 등락률)
                    return spots.map((spot) {
                      final key = spot.barIndex < seriesKeys.length
                          ? seriesKeys[spot.barIndex]
                          : '';
                      final isAsset = key == _assetKey;
                      final label = isAsset ? _assetKey : tickerName(key);
                      final dot = isAsset
                          ? assetColor
                          : (kTickerColors[key] ?? TossColors.grey400);
                      final val = spot.y;
                      return LineTooltipItem(
                        '● ',
                        TextStyle(color: dot, fontSize: 11),
                        textAlign: TextAlign.left,
                        children: [
                          TextSpan(
                            text: '$label ${val >= 0 ? '+' : ''}${val.toStringAsFixed(2)}%',
                            style: TextStyle(
                              color: isAsset ? Colors.white : TossColors.grey200,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      );
                    }).toList();
                  },
                ),
              ),
              lineBarsData: [
                // (#125) 겹쳐 보는 종목 — 내 자산·S&P500 아래에 얇은 실선
                for (final (t, spots) in extras)
                  LineChartBarData(
                    spots: spots,
                    color: kTickerColors[t] ?? TossColors.grey500,
                    barWidth: 1.6,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
                // S&P 500
                if (spxSpots.isNotEmpty)
                  LineChartBarData(
                    spots: spxSpots,
                    color: TossColors.grey300,
                    barWidth: 1.5,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    dashArray: [6, 4],
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, _, __, idx) {
                        final last = idx == spxSpots.length - 1;
                        // 뉴스가 나온 날: 시장 선 위에 색 점
                        final newsColor = _newsColor(spot.x.toInt());
                        if (newsColor != null) {
                          return FlDotCirclePainter(
                            radius: 3,
                            color: newsColor,
                            strokeWidth: 1.5,
                            strokeColor: Colors.white,
                          );
                        }
                        return FlDotCirclePainter(
                          radius: last ? 2.5 : 0,
                          color: TossColors.grey400,
                          strokeWidth: last ? 1.5 : 0,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(show: false),
                  ),
                // 내 자산
                if (hasAsset)
                  LineChartBarData(
                    spots: assetSpots,
                    color: assetColor,
                    barWidth: 2.5,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, _, __, idx) {
                        final last = idx == assetSpots.length - 1;
                        // (#125) 위기 대응을 한 날: 주황 네모
                        if (!last &&
                            widget.decisionIndexes.contains(spot.x.toInt())) {
                          return FlDotSquarePainter(
                            size: 7,
                            color: TossColors.orange500,
                            strokeWidth: 1.5,
                            strokeColor: Colors.white,
                          );
                        }
                        // 카드를 고른 날: 흰 점 + 선 색 테두리
                        if (!last &&
                            widget.cardIndexes.contains(spot.x.toInt())) {
                          return FlDotCirclePainter(
                            radius: 3.5,
                            color: Colors.white,
                            strokeWidth: 2.5,
                            strokeColor: assetColor,
                          );
                        }
                        return FlDotCirclePainter(
                          radius: last ? 4.5 : 0,
                          color: assetColor,
                          strokeWidth: last ? 2 : 0,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          assetColor.withValues(alpha: 0.14),
                          assetColor.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
              ],
              gridData: const FlGridData(show: false),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: 0,
                    color: TossColors.grey200,
                    strokeWidth: 1,
                    dashArray: [3, 3],
                  ),
                ],
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    interval: interval,
                    getTitlesWidget: (value, _) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        '${value >= 0 ? '+' : ''}${value.toStringAsFixed(0)}%',
                        style: const TextStyle(
                            fontSize: 10, color: TossColors.grey400),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ),
                ),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: (widget.rounds.length / 4).ceilToDouble(),
                    getTitlesWidget: (value, _) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= widget.rounds.length) {
                        return const SizedBox.shrink();
                      }
                      final parts = widget.rounds[idx].date.split('-');
                      final label = parts.length >= 3
                          ? '${parts[1]}/${parts[2]}'
                          : widget.rounds[idx].date;
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(label,
                            style: const TextStyle(
                                fontSize: 10, color: TossColors.grey400)),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: TossColors.grey600)),
      ],
    );
  }

  // 속이 빈 점 범례 (카드 선택 표시용)
  Widget _legendRing(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2)),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: TossColors.grey600)),
      ],
    );
  }

  // 네모 범례 (위기 대응 표시용)
  Widget _legendSquare(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, color: color),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: TossColors.grey600)),
      ],
    );
  }

  // 점선 범례 (S&P500용)
  Widget _legendItemDash(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 8,
          child: CustomPaint(
            painter: _DashPainter(color: color),
          ),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: TossColors.grey600)),
      ],
    );
  }
}

// 점선 범례 페인터
class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, size.height / 2),
          Offset((x + 4).clamp(0, size.width), size.height / 2), paint);
      x += 7;
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}