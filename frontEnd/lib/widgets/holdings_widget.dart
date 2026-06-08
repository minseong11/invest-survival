import 'package:flutter/material.dart';
import '../models/card_info.dart';
import '../models/round_data.dart';

// =============================================
// 보유 종목 데이터
// =============================================
class HoldingInfo {
  final String ticker;
  final String cardName;
  final String emoji;
  final double currentChangeRate;
  final List<double> recentChanges; // 스파크라인용 등락률 히스토리
  final bool isNew;                 // 이번 라운드 새로 추가됐는지

  HoldingInfo({
    required this.ticker,
    required this.cardName,
    required this.emoji,
    required this.currentChangeRate,
    required this.recentChanges,
    this.isNew = false,
  });
}

// =============================================
// 선택된 카드 목록에서 보유 종목 추출
// =============================================
List<HoldingInfo> extractHoldings({
  required List<int> selectedCardIds,
  required List<RoundData> rounds,
  required int currentRoundIndex,
  int? newCardId, // 이번 라운드 새로 선택한 카드
}) {
  final holdings  = <HoldingInfo>[];
  final seenTickers = <String>{};

  // SPX는 기준 지수 → 보유 종목에서 제외
  const exclude = {'^SPX'};

  for (final cardId in selectedCardIds) {
    final card = CardInfo.fromId(cardId);
    if (card == null) continue;
    if (exclude.contains(card.ticker)) continue;
    if (seenTickers.contains(card.ticker)) continue;
    seenTickers.add(card.ticker);

    // 현재 등락률
    final currentRound = currentRoundIndex < rounds.length
        ? rounds[currentRoundIndex]
        : null;
    final changeRate = currentRound?.getPrice(card.ticker)?.changeRate ?? 0.0;

    // 최근 20라운드 등락률 히스토리
    final history = <double>[];
    final start = (currentRoundIndex - 19).clamp(0, rounds.length - 1);
    for (int i = start; i <= currentRoundIndex && i < rounds.length; i++) {
      final p = rounds[i].getPrice(card.ticker);
      if (p != null) history.add(p.changeRate);
    }

    holdings.add(HoldingInfo(
      ticker:            card.ticker,
      cardName:          card.name,
      emoji:             card.emoji,
      currentChangeRate: changeRate,
      recentChanges:     history,
      isNew:             cardId == newCardId,
    ));
  }

  return holdings;
}

// =============================================
// 스파크라인 페인터
// =============================================
class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparklinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final range = (max - min).abs();

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final normalized = range < 0.001 ? 0.5 : (values[i] - min) / range;
      // 위아래 10% 여백
      final y = size.height - normalized * size.height * 0.8 - size.height * 0.1;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color;
}

// =============================================
// 게임 진행 중 보유종목 위젯 (스파크라인)
// 1~3개: 기본 크기, 4개: 이름 숨기고 축소
// =============================================
class HoldingsGameWidget extends StatelessWidget {
  final List<HoldingInfo> holdings;

  const HoldingsGameWidget({super.key, required this.holdings});

  @override
  Widget build(BuildContext context) {
    if (holdings.isEmpty) return const SizedBox.shrink();

    final compact = holdings.length == 4;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '보유 종목 (${holdings.length})',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7684),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: holdings.asMap().entries.map((entry) {
              final i    = entry.key;
              final h    = entry.value;
              final last = i == holdings.length - 1;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: last ? 0 : 6),
                  child: _SparkCard(holding: h, compact: compact),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _SparkCard extends StatelessWidget {
  final HoldingInfo holding;
  final bool compact;

  const _SparkCard({required this.holding, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final isPos  = holding.currentChangeRate >= 0;
    final color  = isPos ? const Color(0xFFE03131) : const Color(0xFF1971C2);

    return Container(
      padding: EdgeInsets.all(compact ? 5 : 7),
      decoration: BoxDecoration(
        color: holding.isNew
            ? const Color(0xFFF8F7FF)
            : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: holding.isNew
              ? const Color(0xFF534AB7)
              : const Color(0xFFEEEEEE),
          width: holding.isNew ? 1.0 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 티커
          Text(
            holding.ticker.replaceAll('^', ''),
            style: TextStyle(
              fontSize: compact ? 9 : 10,
              fontWeight: FontWeight.w600,
              color: holding.isNew
                  ? const Color(0xFF534AB7)
                  : const Color(0xFF111111),
            ),
            overflow: TextOverflow.ellipsis,
          ),

          // 이름: 1~3개일 때만
          if (!compact) ...[
            const SizedBox(height: 1),
            Text(
              holding.cardName,
              style: const TextStyle(fontSize: 8, color: Color(0xFF6B7684)),
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // 스파크라인
          const SizedBox(height: 4),
          SizedBox(
            height: compact ? 14 : 18,
            child: holding.recentChanges.length >= 2
                ? CustomPaint(
                    painter: _SparklinePainter(
                      values: holding.recentChanges,
                      color: color,
                    ),
                    size: Size.infinite,
                  )
                : const SizedBox.shrink(),
          ),

          // 등락률
          const SizedBox(height: 2),
          Text(
            '${isPos ? '+' : ''}${holding.currentChangeRate.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: compact ? 7 : 8,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================
// 카드 선택 라운드 보유종목 위젯 (2×2 그리드)
// 차트 없음, 빈 슬롯 표시, 4칸 고정
// =============================================
class HoldingsMiniGrid extends StatelessWidget {
  final List<HoldingInfo> holdings;

  const HoldingsMiniGrid({super.key, required this.holdings});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '보유 종목 (${holdings.length})',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7684),
            ),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            childAspectRatio: 3.8,
            children: [
              ...holdings.map((h) => _MiniCard(holding: h)),
              // 빈 슬롯 채우기 (총 4칸)
              ...List.generate(
                (4 - holdings.length).clamp(0, 4),
                (_) => const _EmptySlot(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final HoldingInfo holding;

  const _MiniCard({required this.holding});

  @override
  Widget build(BuildContext context) {
    final isPos = holding.currentChangeRate >= 0;
    final color = isPos ? const Color(0xFFE03131) : const Color(0xFF1971C2);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: holding.isNew
            ? const Color(0xFFF8F7FF)
            : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: holding.isNew
              ? const Color(0xFF534AB7)
              : const Color(0xFFEEEEEE),
          width: holding.isNew ? 1.0 : 0.5,
        ),
      ),
      child: Row(
        children: [
          Text(holding.emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              holding.ticker.replaceAll('^', ''),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: holding.isNew
                    ? const Color(0xFF534AB7)
                    : const Color(0xFF111111),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${isPos ? '+' : ''}${holding.currentChangeRate.toStringAsFixed(1)}%',
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFEEEEEE),
          width: 0.5,
        ),
      ),
    );
  }
}