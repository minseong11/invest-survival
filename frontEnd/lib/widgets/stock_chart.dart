import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/round_data.dart';
import '../models/price_data.dart';

// 종목별 고정 색상
const Map<String, Color> tickerColors = {
  '^SPX':  Color(0xFF1971C2),  // 파랑
  '^NDX':  Color(0xFF7048E8),  // 보라
  'GLD':   Color(0xFFE67700),  // 주황
  'USO':   Color(0xFF2F9E44),  // 초록
  'AAPL':  Color(0xFF868E96),  // 회색
  'TLT':   Color(0xFFE64980),  // 분홍
};

// 10배 배율이 필요한 종목 목록
// ^SPX, ^NDX는 1200~1700 범위라 배율 불필요
// 나머지는 100 이하라 10배 적용
const Set<String> _scaledTickers = {'GLD', 'USO', 'AAPL', 'TLT'};

Color tickerColor(String ticker) =>
    tickerColors[ticker] ?? const Color(0xFF6B7684);

double _applyScale(String ticker, double value) =>
    _scaledTickers.contains(ticker) ? value * 10 : value;

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

  // 특정 ticker의 FlSpot 리스트 (배율 적용)
  List<FlSpot> _spots(String ticker) {
    final List<FlSpot> spots = [];
    for (int i = 0; i < rounds.length; i++) {
      final price = rounds[i].getPrice(ticker);
      if (price != null) {
        spots.add(FlSpot(i.toDouble(), _applyScale(ticker, price.close)));
      }
    }
    return spots;
  }

  // roundAsset 기반 내 자산 FlSpot 리스트
  List<FlSpot> get _assetSpots {
    final List<FlSpot> spots = [];
    for (int i = 0; i < rounds.length; i++) {
      final asset = rounds[i].roundAsset;
      if (asset != null) {
        // 자산을 종목 스케일(~1200)에 맞게 축소: 10,000,000 → 1000 수준
        spots.add(FlSpot(i.toDouble(), asset / 10000));
      }
    }
    return spots;
  }

  // Y축 범위 (배율 적용된 종목 가격 + 자산 스팟 모두 포함)
  double get _minY {
    double min = double.infinity;
    for (final ticker in _tickers) {
      for (final r in rounds) {
        final price = r.getPrice(ticker);
        if (price != null) {
          final v = _applyScale(ticker, price.close);
          if (v < min) min = v;
        }
      }
    }
    for (final r in rounds) {
      final asset = r.roundAsset;
      if (asset != null) {
        final v = asset / 10000;
        if (v < min) min = v;
      }
    }
    return min == double.infinity ? 0 : min * 0.97;
  }

  double get _maxY {
    double max = double.negativeInfinity;
    for (final ticker in _tickers) {
      for (final r in rounds) {
        final price = r.getPrice(ticker);
        if (price != null) {
          final v = _applyScale(ticker, price.close);
          if (v > max) max = v;
        }
      }
    }
    for (final r in rounds) {
      final asset = r.roundAsset;
      if (asset != null) {
        final v = asset / 10000;
        if (v > max) max = v;
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
    final assetSpots = _assetSpots;
    final hasAsset = assetSpots.isNotEmpty;

    // 종목 선 + 자산 선 합치기
    final List<LineChartBarData> lineBars = [
      // 종목별 선
      ...tickers.map((ticker) {
        final spots = _spots(ticker);
        final color = tickerColor(ticker);
        return LineChartBarData(
          spots: spots,
          color: color,
          barWidth: 1.5,
          isCurved: true,
          curveSmoothness: 0.3,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, _, __, index) {
              final isLastDot = index == spots.length - 1;
              return FlDotCirclePainter(
                radius: isLastDot ? 3 : 0,
                color: color,
                strokeWidth: isLastDot ? 2 : 0,
                strokeColor: Colors.white,
              );
            },
          ),
          belowBarData: BarAreaData(show: false),
        );
      }),

      // 내 자산 선 (흰색 굵은 선)
      if (hasAsset)
        LineChartBarData(
          spots: assetSpots,
          color: const Color(0xFF111111),
          barWidth: 2.5,
          isCurved: true,
          curveSmoothness: 0.3,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, _, __, index) {
              final isLastDot = index == assetSpots.length - 1;
              return FlDotCirclePainter(
                radius: isLastDot ? 4 : 0,
                color: const Color(0xFF111111),
                strokeWidth: isLastDot ? 2 : 0,
                strokeColor: Colors.white,
              );
            },
          ),
          belowBarData: BarAreaData(
            show: true,
            color: const Color(0xFF111111).withValues(alpha: 0.05),
          ),
        ),
    ];

    return Column(
      children: [
        // 범례
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // 종목 범례
              ...tickers.map((t) => Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Row(
                  children: [
                    Container(width: 10, height: 2.5, color: tickerColor(t)),
                    const SizedBox(width: 3),
                    Text(
                      _scaledTickers.contains(t) ? '$t×10' : t,
                      style: const TextStyle(fontSize: 9, color: Color(0xFF6B7684)),
                    ),
                  ],
                ),
              )),
              // 자산 범례
              if (hasAsset) ...[
                const SizedBox(width: 10),
                Container(width: 10, height: 2.5, color: const Color(0xFF111111)),
                const SizedBox(width: 3),
                const Text('내 자산', style: TextStyle(fontSize: 9, color: Color(0xFF6B7684))),
              ],
            ],
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

              lineBarsData: lineBars,

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

              // Y축 숫자 제거
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
                leftTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),

              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots.map((spot) {
                    final index = spot.x.toInt();
                    final date = index < rounds.length ? rounds[index].date : '';
                    return LineTooltipItem(
                      '$date\n${spot.y.toStringAsFixed(0)}',
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