import 'package:flutter/material.dart';
import '../models/card_info.dart';
import '../models/holding.dart';
import '../models/round_data.dart';

// 고른 라운드에 한 번 사는 카드 (거인의 어깨, 원유 베팅) — 발동 횟수 대신 "즉시 매수"로 표시
const Set<int> kOnceCardIds = {1, 7};

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
  final int triggerCount; // 지금 라운드까지 발동한 횟수 (11주차)

  HoldingCardInfo({
    required this.cardId,
    required this.ticker,
    required this.cardName,
    required this.emoji,
    required this.currentChangeRate,
    this.isNew = false,
    this.triggerCount = 0,
  });

  bool get isOnce => kOnceCardIds.contains(cardId);
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

  // 지금 라운드까지 카드별 발동 횟수 (rounds[].triggeredCards 누적)
  final counts = <int, int>{};
  for (int i = 0; i <= currentRoundIndex && i < rounds.length; i++) {
    for (final id in rounds[i].triggeredCards) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
  }

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
      triggerCount:      counts[cardId] ?? 0,
    ));
  }

  return holdings;
}

// =============================================
// 보유 자산 + 내 카드 위젯 (게임 진행 중 / 카드 선택 모두 동일)
//  - 보유 자산 (11주차): 종목별 평균 매수가 대비 수익률·비중, 현금
//    서버가 holdings를 보내지 않으면 이 칸은 생략 (예전 서버와도 호환)
//  - 내 카드: 카드 이름 + 지금까지 발동 횟수, 이번 라운드 발동 시 애니메이션
// =============================================
class HoldingCardsWidget extends StatelessWidget {
  final List<HoldingCardInfo> cards;
  final List<int> triggeredCardIds; // 이번 라운드 발동한 카드
  final List<Holding> holdings;     // 이번 라운드 보유 자산 (서버)
  final double? cashWeight;         // 현금 비중(%)

  const HoldingCardsWidget({
    super.key,
    required this.cards,
    this.triggeredCardIds = const [],
    this.holdings = const [],
    this.cashWeight,
  });

  static const _labelStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: Color(0xFF6B7684),
  );

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    final showAssets = holdings.isNotEmpty;

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
          if (showAssets) ...[
            const Text('보유 자산', style: _labelStyle),
            const SizedBox(height: 6),
            ...holdings.map((h) => _AssetRow(
                  name:       h.name,
                  returnRate: h.returnRate,
                  weight:     h.weight,
                )),
            if (cashWeight != null)
              _AssetRow(name: '현금', returnRate: null, weight: cashWeight!),
            const SizedBox(height: 10),
          ],
          const Text('내 카드', style: _labelStyle),
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
// 보유 자산 한 줄: 이름 | 수익률 | 비중 막대 | 비중%
// =============================================
class _AssetRow extends StatelessWidget {
  final String name;
  final double? returnRate; // 현금은 null
  final double weight;

  const _AssetRow({
    required this.name,
    required this.returnRate,
    required this.weight,
  });

  @override
  Widget build(BuildContext context) {
    final r = returnRate;
    final rateColor = r == null
        ? const Color(0xFF6B7684)
        : (r >= 0 ? const Color(0xFFE03131) : const Color(0xFF1971C2));
    final w = weight.clamp(0, 100).toDouble();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111111))),
          ),
          SizedBox(
            width: 54,
            child: Text(
              r == null ? '' : '${r >= 0 ? '+' : ''}${r.toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: rateColor),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: w / 100,
                minHeight: 6,
                backgroundColor: const Color(0xFFF1F3F5),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF3D348B)),
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text('${w.toStringAsFixed(0)}%',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 10, color: Color(0xFF6B7684))),
          ),
        ],
      ),
    );
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
    // 11주차: 종목 코드·오늘 등락률 대신 카드 이름과 발동 횟수 표시
    final label = widget.card.isOnce
        ? '즉시 매수'
        : '발동 ${widget.card.triggerCount}회';

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
                  widget.card.cardName,
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
            label,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6B7684),
            ),
          ),
        ],
      ),
    );
  }
}