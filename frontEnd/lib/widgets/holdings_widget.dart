import 'package:flutter/material.dart';
import '../models/card_info.dart';
import '../models/round_data.dart';

// =============================================
// 보유 카드 데이터
// =============================================
class HoldingCardInfo {
  final int cardId;
  final String ticker;
  final String cardName;
  final String emoji;
  final double currentChangeRate;
  final bool isNew;

  HoldingCardInfo({
    required this.cardId,
    required this.ticker,
    required this.cardName,
    required this.emoji,
    required this.currentChangeRate,
    this.isNew = false,
  });
}

// 선택된 카드 목록에서 보유 카드 추출
// ^SPX 포함, 선택한 카드 기준 (중복 티커도 각각 슬롯)
List<HoldingCardInfo> extractHoldingCards({
  required List<int> selectedCardIds,
  required List<RoundData> rounds,
  required int currentRoundIndex,
  int? newCardId,
}) {
  final holdings = <HoldingCardInfo>[];

  for (final cardId in selectedCardIds) {
    final card = CardInfo.fromId(cardId);
    if (card == null) continue;

    final currentRound = currentRoundIndex < rounds.length
        ? rounds[currentRoundIndex]
        : null;
    final changeRate =
        currentRound?.getPrice(card.ticker)?.changeRate ?? 0.0;

    holdings.add(HoldingCardInfo(
      cardId:            cardId,
      ticker:            card.ticker,
      cardName:          card.name,
      emoji:             card.emoji,
      currentChangeRate: changeRate,
      isNew:             cardId == newCardId,
    ));
  }

  return holdings;
}

// =============================================
// 보유 카드 위젯 (게임 진행 중 / 카드 선택 모두 동일)
// 2x2 공간 고정, 빈 슬롯 없음, 발동 애니메이션
// =============================================
class HoldingCardsWidget extends StatelessWidget {
  final List<HoldingCardInfo> cards;
  final List<int> triggeredCardIds; // 이번 라운드 발동한 카드

  const HoldingCardsWidget({
    super.key,
    required this.cards,
    this.triggeredCardIds = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();

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
          const Text(
            '보유 카드',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7684),
            ),
          ),
          const SizedBox(height: 8),
          // 2x2 공간 고정: GridView 대신 직접 레이아웃
          _buildGrid(),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    // 최대 4개, 2열 고정
    // 공간은 항상 2x2 기준으로 확보
    // 슬롯은 있는 것만 (빈 위젯 없음)
    final rows = <Widget>[];

    for (int i = 0; i < cards.length; i += 2) {
      final left  = cards[i];
      final right = i + 1 < cards.length ? cards[i + 1] : null;

      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 2 < cards.length ? 6 : 0),
          child: Row(
            children: [
              Expanded(
                child: _HoldingCardSlot(
                  card:        left,
                  isTriggered: triggeredCardIds.contains(left.cardId),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: right != null
                    ? _HoldingCardSlot(
                        card:        right,
                        isTriggered: triggeredCardIds.contains(right.cardId),
                      )
                    // 오른쪽 슬롯 없을 때: 공간만 차지 (투명)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }

    return Column(children: rows);
  }
}

// =============================================
// 개별 슬롯 (발동 애니메이션 포함)
// =============================================
class _HoldingCardSlot extends StatefulWidget {
  final HoldingCardInfo card;
  final bool isTriggered;

  const _HoldingCardSlot({
    required this.card,
    this.isTriggered = false,
  });

  @override
  State<_HoldingCardSlot> createState() => _HoldingCardSlotState();
}

class _HoldingCardSlotState extends State<_HoldingCardSlot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _borderAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // 스케일: 1.0 → 1.08 → 1.0
    _scaleAnim = TweenSequence([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.08)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 40),
      TweenSequenceItem(
          tween: Tween(begin: 1.08, end: 1.0)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 60),
    ]).animate(_controller);

    // 아웃라인 투명도: 0 → 1 → 0
    _borderAnim = TweenSequence([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 30),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 70),
    ]).animate(_controller);

    if (widget.isTriggered) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(_HoldingCardSlot old) {
    super.didUpdateWidget(old);
    // 새로 발동됐을 때 애니메이션 재실행
    if (widget.isTriggered && !old.isTriggered) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPos  = widget.card.currentChangeRate >= 0;
    final color  = isPos ? const Color(0xFFE03131) : const Color(0xFF1971C2);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnim.value,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.isTriggered
                    ? const Color(0xFFFFB800)
                        .withValues(alpha: _borderAnim.value)
                    : const Color(0xFFEEEEEE),
                width: widget.isTriggered ? 2 : 0.5,
              ),
            ),
            child: child,
          ),
        );
      },
      child: Row(
        children: [
          Text(widget.card.emoji,
              style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.card.ticker.replaceAll('^', ''),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111111),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            '${isPos ? '+' : ''}${widget.card.currentChangeRate.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}