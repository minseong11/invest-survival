import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/round_data.dart';

class StockChart extends StatelessWidget {
  final List<RoundData> rounds;
  final double initialAsset;

  const StockChart({
    super.key,
    required this.rounds,
    this.initialAsset = 10000000,
  });

  // SPX 첫날 종가 (정규화 기준점)
  double? get _spxBase {
    for (final r in rounds) {
      final p = r.getPrice('^SPX');
      if (p != null && p.close > 0) return p.close;
    }
    return null;
  }

  // S&P500 수익률(%) FlSpot 리스트
  List<FlSpot> get _spxSpots {
    final base = _spxBase;
    if (base == null) return [];
    final spots = <FlSpot>[];
    for (int i = 0; i < rounds.length; i++) {
      final p = rounds[i].getPrice('^SPX');
      if (p != null) {
        final pct = (p.close - base) / base * 100;
        spots.add(FlSpot(i.toDouble(), pct));
      }
    }
    return spots;
  }

  // 내 자산 수익률(%) FlSpot 리스트
  List<FlSpot> get _assetSpots {
    final spots = <FlSpot>[];
    for (int i = 0; i < rounds.length; i++) {
      final asset = rounds[i].roundAsset;
      if (asset != null) {
        final pct = (asset - initialAsset) / initialAsset * 100;
        spots.add(FlSpot(i.toDouble(), pct));
      }
    }
    return spots;
  }

  double get _minY {
    double min = 0;
    for (final s in [..._spxSpots, ..._assetSpots]) {
      if (s.y < min) min = s.y;
    }
    // 여유분 10% + 최소 -2%
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
    if (rounds.isEmpty) {
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

    final lineBars = <LineChartBarData>[
      // S&P 500 (파랑)
      if (spxSpots.isNotEmpty)
        LineChartBarData(
          spots: spxSpots,
          color: const Color(0xFF1971C2),
          barWidth: 1.5,
          isCurved: true,
          curveSmoothness: 0.3,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, _, __, idx) {
              final last = idx == spxSpots.length - 1;
              return FlDotCirclePainter(
                radius: last ? 3 : 0,
                color: const Color(0xFF1971C2),
                strokeWidth: last ? 2 : 0,
                strokeColor: Colors.white,
              );
            },
          ),
          belowBarData: BarAreaData(show: false),
        ),

      // 내 자산 (검정)
      if (hasAsset)
        LineChartBarData(
          spots: assetSpots,
          color: const Color(0xFF111111),
          barWidth: 2.5,
          isCurved: true,
          curveSmoothness: 0.3,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, _, __, idx) {
              final last = idx == assetSpots.length - 1;
              return FlDotCirclePainter(
                radius: last ? 4 : 0,
                color: const Color(0xFF111111),
                strokeWidth: last ? 2 : 0,
                strokeColor: Colors.white,
              );
            },
          ),
          belowBarData: BarAreaData(
            show: true,
            color: const Color(0xFF111111).withValues(alpha: 0.04),
          ),
        ),
    ];

    return Column(
      children: [
        // 범례
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _legendDot(const Color(0xFF1971C2), 'S&P 500'),
              const SizedBox(width: 12),
              if (hasAsset) _legendDot(const Color(0xFF111111), '내 자산'),
            ],
          ),
        ),

        // 차트
        Expanded(
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              minX: 0,
              maxX: (rounds.length - 1).toDouble(),
              lineBarsData: lineBars,
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
              borderData: FlBorderData(
                show: true,
                border: const Border(
                  bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1),
                  left:   BorderSide(color: Color(0xFFEEEEEE), width: 1),
                ),
              ),
              // 0% 기준 점선
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
              titlesData: FlTitlesData(
                // Y축: 수익률 %
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
                          fontSize: 8,
                          color: Color(0xFF6B7684),
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ),
                ),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                // X축: 날짜
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: (rounds.length / 4).ceilToDouble(),
                    getTitlesWidget: (value, _) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= rounds.length) {
                        return const SizedBox.shrink();
                      }
                      final parts = rounds[idx].date.split('-');
                      final label = parts.length >= 3
                          ? '${parts[1]}/${parts[2]}'
                          : rounds[idx].date;
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

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 2.5,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 3),
        Text(label,
            style: const TextStyle(fontSize: 9, color: Color(0xFF6B7684))),
      ],
    );
  }
}