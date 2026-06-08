import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/round_data.dart';

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
            style: TextStyle(color: Color(0xFF6B7684))),
      );
    }

    final spxSpots   = _spxSpots;
    final assetSpots = _assetSpots;
    final hasAsset   = assetSpots.isNotEmpty;
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
              _legendItemDash(const Color(0xFF74B0FF), 'S&P 500'),
              const SizedBox(width: 12),
              if (hasAsset)
                _legendItem(const Color(0xFF3C3489), '내 자산'),
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
                  getTooltipColor: (_) => const Color(0xFF1A1A2E),
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
                              ? const Color(0xFF74B0FF)
                              : Colors.white,
                          fontSize: 11,
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
                    color: const Color(0xFF74B0FF),
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
                          color: const Color(0xFF74B0FF),
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
                    color: const Color(0xFF3C3489),
                    barWidth: 2.5,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, _, __, idx) {
                        final last = idx == assetSpots.length - 1;
                        return FlDotCirclePainter(
                          radius: last ? 4 : 0,
                          color: const Color(0xFF3C3489),
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
                          const Color(0xFF3C3489).withValues(alpha: 0.18),
                          const Color(0xFF3C3489).withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                  ),
              ],
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: value.abs() < 0.01
                      ? const Color(0xFFCCCCCC)
                      : const Color(0xFFEEEEEE),
                  strokeWidth: value.abs() < 0.01 ? 1.0 : 0.5,
                ),
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: 0,
                    color: const Color(0xFFBBBBBB),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ],
              ),
              borderData: FlBorderData(
                show: true,
                border: const Border(
                  bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1),
                  left:   BorderSide(color: Color(0xFFEEEEEE), width: 1),
                ),
              ),
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
                            fontSize: 8, color: Color(0xFF6B7684)),
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
                                fontSize: 8, color: Color(0xFF6B7684))),
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
          width: 12,
          height: 2.5,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(1)),
        ),
        const SizedBox(width: 3),
        Text(label,
            style: const TextStyle(
                fontSize: 9, color: Color(0xFF6B7684))),
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
        const SizedBox(width: 3),
        Text(label,
            style: const TextStyle(
                fontSize: 9, color: Color(0xFF6B7684))),
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