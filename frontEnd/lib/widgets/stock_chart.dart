import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/round_data.dart';
import '../models/price_data.dart';

// 종목별 고정 색상
const Map<String, Color> tickerColors = {
  '^SPX': Color(0xFF1971C2),  // 파랑
  '^NDX': Color(0xFF7048E8),  // 보라
  'GLD':  Color(0xFFE67700),  // 노랑
};

Color tickerColor(String ticker) =>
    tickerColors[ticker] ?? const Color(0xFF6B7684);

class StockChart extends StatelessWidget {
  final List<RoundData> rounds;

  const StockChart({
    super.key,
    required this.rounds,
  });

  // rounds에 존재하는 ticker 목록 추출
  List<String> get _tickers {
    if (rounds.isEmpty) return [];
    final Set<String> seen = {};
    final List<String> result = [];
    for (final r in rounds) {
      for (final p in r.priceData) {
        if (seen.add(p.ticker)) result.add(p.ticker);
      }
    }
    return result;
  }

  // 특정 ticker의 FlSpot 리스트
  List<FlSpot> _spots(String ticker) {
    final List<FlSpot> spots = [];
    for (int i = 0; i < rounds.length; i++) {
      final price = rounds[i].getPrice(ticker);
      if (price != null) {
        spots.add(FlSpot(i.toDouble(), price.close));
      }
    }
    return spots;
  }

  // Y축 범위
  double get _minY {
    double min = double.infinity;
    for (final r in rounds) {
      for (final p in r.priceData) {
        if (p.close < min) min = p.close;
      }
    }
    return min == double.infinity ? 0 : min * 0.97;
  }

  double get _maxY {
    double max = double.negativeInfinity;
    for (final r in rounds) {
      for (final p in r.priceData) {
        if (p.close > max) max = p.close;
      }
    }
    return max == double.negativeInfinity ? 100 : max * 1.03;
  }

  @override
  Widget build(BuildContext context) {
    if (rounds.isEmpty) {
      return const Center(
        child: Text('데이터 없음', style: TextStyle(color: Color(0xFF6B7684))),
      );
    }

    final tickers = _tickers;

    return Column(
      children: [
        // 종목 범례 (여러 종목일 때만 표시)
        if (tickers.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: tickers.map((t) => Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    Container(
                      width: 12, height: 3,
                      color: tickerColor(t),
                    ),
                    const SizedBox(width: 4),
                    Text(t, style: const TextStyle(
                      fontSize: 10, color: Color(0xFF6B7684),
                    )),
                  ],
                ),
              )).toList(),
            ),
          ),

        // 차트
        Expanded(
          child: LineChart(
            LineChartData(
              minY: _minY,
              maxY: _maxY,
              minX: 0,
              maxX: (rounds.length - 1).toDouble(),

              lineBarsData: tickers.map((ticker) {
                final spots = _spots(ticker);
                final color = tickerColor(ticker);
                final isLast = ticker == tickers.last;
                return LineChartBarData(
                  spots: spots,
                  color: color,
                  barWidth: 2,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, _, __, index) {
                      final isLastDot = index == spots.length - 1;
                      return FlDotCirclePainter(
                        radius: isLastDot ? 4 : 0,
                        color: color,
                        strokeWidth: isLastDot ? 2 : 0,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: isLast,
                    color: color.withValues(alpha: 0.06),
                  ),
                );
              }).toList(),

              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (_maxY - _minY) / 4,
                getDrawingHorizontalLine: (_) => const FlLine(
                  color: Color(0xFFEEEEEE), strokeWidth: 1,
                ),
              ),

              borderData: FlBorderData(
                show: true,
                border: const Border(
                  bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1),
                  left:   BorderSide(color: Color(0xFFEEEEEE), width: 1),
                ),
              ),

              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: (rounds.length / 5).ceilToDouble(),
                    getTitlesWidget: (value, _) {
                      final index = value.toInt();
                      if (index < 0 || index >= rounds.length) {
                        return const SizedBox.shrink();
                      }
                      final date = rounds[index].date;
                      final parts = date.split('-');
                      final label = parts.length >= 3
                          ? '${parts[1]}/${parts[2]}'
                          : date;
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(label, style: const TextStyle(
                          fontSize: 9, color: Color(0xFF6B7684),
                        )),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 52,
                    getTitlesWidget: (value, _) => Text(
                      value.toStringAsFixed(0),
                      style: const TextStyle(
                        fontSize: 9, color: Color(0xFF6B7684),
                      ),
                    ),
                  ),
                ),
                topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),

              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots.map((spot) {
                    final index = spot.x.toInt();
                    final date = index < rounds.length ? rounds[index].date : '';
                    return LineTooltipItem(
                      '$date\n${spot.y.toStringAsFixed(2)}',
                     const TextStyle(
                        color: Colors.white, fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}