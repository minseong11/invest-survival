import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/round_data.dart';
import '../models/price_data.dart';

class StockChart extends StatelessWidget {
  final List<RoundData> rounds;
  final String ticker;

  const StockChart({
    super.key,
    required this.rounds,
    required this.ticker,
  });

  // ticker에 해당하는 종가(close) 리스트 추출
  List<PriceData> get _prices {
    return rounds
        .map((r) => r.getPrice(ticker))
        .whereType<PriceData>()
        .toList();
  }

  // fl_chart용 FlSpot 리스트 변환 (x: 인덱스, y: 종가)
  List<FlSpot> get _spots {
    return List.generate(_prices.length, (i) {
      return FlSpot(i.toDouble(), _prices[i].close);
    });
  }

  double get _minY {
    if (_prices.isEmpty) return 0;
    final min = _prices.map((p) => p.close).reduce((a, b) => a < b ? a : b);
    return min * 0.98; // 아래 여백 2%
  }

  double get _maxY {
    if (_prices.isEmpty) return 100;
    final max = _prices.map((p) => p.close).reduce((a, b) => a > b ? a : b);
    return max * 1.02; // 위 여백 2%
  }

  // 상승/하락 색상 (첫날 대비 현재)
  Color get _lineColor {
    if (_prices.length < 2) return const Color(0xFF6B7684);
    return _prices.last.close >= _prices.first.close
        ? const Color(0xFFE03131) // 상승 빨강
        : const Color(0xFF1971C2); // 하락 파랑
  }

  @override
  Widget build(BuildContext context) {
    if (_prices.isEmpty) {
      return const Center(
        child: Text(
          '데이터 없음',
          style: TextStyle(color: Color(0xFF6B7684)),
        ),
      );
    }

    return LineChart(
      LineChartData(
        minY: _minY,
        maxY: _maxY,
        minX: 0,
        maxX: (_prices.length - 1).toDouble(),

        // 선 데이터
        lineBarsData: [
          LineChartBarData(
            spots: _spots,
            color: _lineColor,
            barWidth: 2,
            isCurved: true, // 부드러운 곡선
            curveSmoothness: 0.3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) {
                // 마지막 점만 강조
                final isLast = index == _spots.length - 1;
                return FlDotCirclePainter(
                  radius: isLast ? 5 : 3,
                  color: _lineColor,
                  strokeWidth: isLast ? 2 : 0,
                  strokeColor: Colors.white,
                );
              },
            ),
            // 선 아래 그라데이션
            belowBarData: BarAreaData(
              show: true,
              color: _lineColor.withValues(alpha: 0.08),
            ),
          ),
        ],

        // 격자선
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (_maxY - _minY) / 4,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: Color(0xFFEEEEEE),
            strokeWidth: 1,
          ),
        ),

        // 테두리
        borderData: FlBorderData(
          show: true,
          border: const Border(
            bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1),
            left: BorderSide(color: Color(0xFFEEEEEE), width: 1),
          ),
        ),

        // 축 레이블
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= rounds.length) {
                  return const SizedBox.shrink();
                }
                final date = rounds[index].date;
                final parts = date.split('-');
                final label =
                    parts.length >= 3 ? '${parts[1]}/${parts[2]}' : date;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF6B7684),
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(0),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF6B7684),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),

        // 터치 툴팁 (점 누르면 값 표시)
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final index = spot.x.toInt();
                final date = index < rounds.length ? rounds[index].date : '';
                return LineTooltipItem(
                  '$date\n${spot.y.toStringAsFixed(2)}',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}
