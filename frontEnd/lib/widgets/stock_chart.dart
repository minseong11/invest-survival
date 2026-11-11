import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/round_data.dart';
import '../theme/toss_theme.dart';

class StockChart extends StatefulWidget {
  final List<RoundData> rounds;
  final double initialAsset;

  const StockChart({
    super.key,
    required this.rounds,
    this.initialAsset = 10000000,
  });

  @override
  State<StockChart> createState() => _StockChartState();
}

class _StockChartState extends State<StockChart> {
  int? _touchedIndex;

  double? get _spxBase {
    for (final r in widget.rounds) {
      final p = r.getPrice('^SPX');
      if (p != null && p.close > 0) return p.close;
    }
    return null;
  }

  List<FlSpot> get _spxSpots {
    final base = _spxBase;
    if (base == null) return [];
    final spots = <FlSpot>[];
    for (int i = 0; i < widget.rounds.length; i++) {
      final p = widget.rounds[i].getPrice('^SPX');
      if (p != null) {
        spots.add(FlSpot(i.toDouble(), (p.close - base) / base * 100));
      }
    }
    return spots;
  }

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

  double get _minY {
    double min = 0;
    for (final s in [..._spxSpots, ..._assetSpots]) {
      if (s.y < min) min = s.y;
    }
    return ((min * 1.15) - 2).floorToDouble();
  }

  double get _maxY {
    double max = 0;
    for (final s in [..._spxSpots, ..._assetSpots]) {
      if (s.y > max) max = s.y;
    }
    return ((max * 1.15) + 2).ceilToDouble();
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
    final hasAsset   = assetSpots.isNotEmpty;
    // 내 자산 선: 지금 수익이면 빨강, 손실이면 파랑 (토스증권 방식)
    final assetColor = hasAsset ? TossColors.rate(assetSpots.last.y) : TossColors.red500;
    final minY       = _minY;
    final maxY       = _maxY;
    final range      = (maxY - minY).abs();
    final interval   = range > 0 ? (range / 4) : 2.0;

    return Column(
      children: [
        // 범례
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (hasAsset) ...[
                _legendItem(assetColor, '내 자산'),
                const SizedBox(width: 12),
              ],
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
                touchCallback: (event, response) {
                  setState(() {
                    if (response?.lineBarSpots != null &&
                        response!.lineBarSpots!.isNotEmpty) {
                      _touchedIndex =
                          response.lineBarSpots!.first.spotIndex;
                    } else {
                      _touchedIndex = null;
                    }
                  });
                },
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => TossColors.grey800,
                  getTooltipItems: (spots) {
                    return spots.map((spot) {
                      final label = spot.barIndex == 0
                          ? 'S&P500'
                          : '내 자산';
                      final val = spot.y;
                      return LineTooltipItem(
                        '$label\n${val >= 0 ? '+' : ''}${val.toStringAsFixed(2)}%',
                        TextStyle(
                          color: spot.barIndex == 0
                              ? TossColors.grey300
                              : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
              lineBarsData: [
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
              gridData: FlGridData(show: false),
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

  // 점선 범례 (S&P500용)
  Widget _legendItemDash(Color color, String label) {
    return Row(
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