import 'package:flutter/material.dart';
import '../models/card_info.dart';
import '../models/holding.dart';
import '../models/round_data.dart';
import '../theme/toss_theme.dart';
import 'toss/toss_widgets.dart';

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
// 내 포트폴리오 섹션 (게임 진행 중)
//  - 보유 자산: 종목별 비중 막대 + 수익률, 현금
//    서버가 holdings를 보내지 않으면 이 칸은 생략 (예전 서버와도 호환)
//  - 내 카드: 2열 칩. 이번 라운드에 발동하면 톡 튀며 주황 테두리
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

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    final showAssets = holdings.isNotEmpty;

    return TossSection(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showAssets) ...[
            const Text('내 포트폴리오',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: TossColors.grey900)),
            const SizedBox(height: 10),
            ...holdings.map((h) => _AssetRow(
                  name:       h.name,
                  returnRate: h.returnRate,
                  weight:     h.weight,
                )),
            if (cashWeight != null)
              _AssetRow(name: '현금', returnRate: null, weight: cashWeight!),
            const SizedBox(height: 12),
          ],
          Text('내 카드 ${cards.length}장',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: TossColors.grey600)),
          const SizedBox(height: 8),
          _buildGrid(),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    // 최대 4개, 2열 고정
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
// 보유 자산 한 줄: 이름 | 비중 막대 | 비중% | 수익률
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
    final w = weight.clamp(0, 100).toDouble();
    final barColor = r == null ? TossColors.grey300 : TossColors.blue500;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: TossColors.grey800)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 8,
                color: TossColors.grey100,
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: w / 100),
                  duration: TossMotion.slow,
                  curve: TossMotion.enter,
                  builder: (_, v, __) => FractionallySizedBox(
                    widthFactor: v.clamp(0.0, 1.0),
                    heightFactor: 1,
                    child: Container(color: barColor),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text('${w.toStringAsFixed(0)}%',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 12, color: TossColors.grey500)),
          ),
          SizedBox(
            width: 60,
            child: Text(
              r == null ? '' : '${r >= 0 ? '+' : ''}${r.toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: r == null ? TossColors.grey500 : TossColors.rate(r)),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================
// 내 카드 칩 (발동 애니메이션 포함)
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
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    // 스케일: 1.0 → 1.06 → 1.0 (톡 튀는 느낌)
    _scaleAnim = TweenSequence([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.06)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 30),
      TweenSequenceItem(
          tween: Tween(begin: 1.06, end: 1.0)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 70),
    ]).animate(_controller);

    // 강조: 0 → 1 → 0
    _glowAnim = TweenSequence([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 25),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 75),
    ]).animate(_controller);

    if (widget.isTriggered) _controller.forward();
  }

  @override
  void didUpdateWidget(_HoldingCardSlot old) {
    super.didUpdateWidget(old);
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
    final label = widget.card.isOnce
        ? '즉시 매수'
        : '발동 ${widget.card.triggerCount}회';

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final g = _glowAnim.value;
        return Transform.scale(
          scale: _scaleAnim.value,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: Color.lerp(
                  TossColors.grey50, const Color(0xFFFFF4E0), g),
              borderRadius: BorderRadius.circular(TossRadius.md),
              border: Border.all(
                color: TossColors.orange500.withValues(alpha: g),
                width: 1.5,
              ),
            ),
            child: child,
          ),
        );
      },
      child: Row(
        children: [
          Text(widget.card.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.card.cardName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: TossColors.grey800,
              ),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: TossColors.grey500,
            ),
          ),
        ],
      ),
    );
  }
}
