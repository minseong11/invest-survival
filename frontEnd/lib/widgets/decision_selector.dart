import 'package:flutter/material.dart';
import '../models/decision.dart';
import '../models/news_item.dart';
import '../theme/toss_theme.dart';
import 'toss/toss_widgets.dart';

// =============================================
// (#125) 위기 대응 선택 — 뉴스 속보가 나온 라운드에서 게임이 멈추고 보인다
//  속보 카드 + 선택지 3개(버틴다 / 절반 판다 / 더 산다). 고른 뒤 아래 버튼으로 확정한다.
//  (장면 개편) 게임 화면 위로 올라오는 장면 시트 안에 놓인다 — 흰 섹션 대신 내용만 그린다
// =============================================
class DecisionSelector extends StatelessWidget {
  final DecisionPrompt? prompt;      // 이 라운드의 속보 (없으면 제목만)
  final List<NewsItem> otherNews;    // 같은 날 나온 다른 뉴스
  final String? selected;            // 지금 고른 선택 (확정 전)
  final bool hasHoldings;            // 팔 자산이 있는지 (없으면 '절반 판다'를 고를 수 없음)
  final bool hasCash;                // 살 현금이 있는지 (없으면 '더 산다'를 고를 수 없음)
  final String buyMoreTarget;        // '더 산다'에서 사는 지수 이름
  final bool enabled;
  final ValueChanged<String> onSelect;
  final Widget? info;                // 속보와 질문 사이에 넣을 내용 (지금 내 상황·오늘 시장)

  const DecisionSelector({
    super.key,
    required this.prompt,
    required this.selected,
    required this.onSelect,
    this.otherNews = const [],
    this.hasHoldings = true,
    this.hasCash = true,
    this.buyMoreTarget = 'S&P500',
    this.enabled = true,
    this.info,
  });

  @override
  Widget build(BuildContext context) {
    final news = prompt?.news;

    // (장면 개편) 속보 카드 → 질문 → 큰 선택지 3개. 게임 화면 위로 올라오는 장면 시트 안에 놓인다
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (news != null) ...[
          BreakingNewsCard(news: news),
          const SizedBox(height: 12),
        ],
        if (info != null) ...[
          info!,
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 10),
        const Text('어떻게 대응할까요?', style: TossText.title2),
        for (final n in otherNews)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('· ${n.headline}', style: TossText.caption),
          ),
        const SizedBox(height: 12),
        for (int i = 0; i < DecisionChoice.all.length; i++)
          FadeInUp(
            delay: Duration(milliseconds: 80 * i),
            child: _buildChoice(DecisionChoice.all[i]),
          ),
        const SizedBox(height: 6),
        const Text(
          '오늘 종가로 바로 매매하고, 전략 카드는 계속 작동해요.',
          style: TossText.small,
        ),
      ],
    );
  }

  Widget _buildChoice(String choice) {
    // 팔 자산·살 현금이 없으면 고를 수 없음 (골라도 아무 일도 일어나지 않는 선택을 막는다)
    final String? blocked = switch (choice) {
      DecisionChoice.sellHalf when !hasHoldings => '아직 가진 자산이 없어요',
      DecisionChoice.buyMore when !hasCash      => '남은 현금이 없어요',
      _ => null,
    };
    final usable = enabled && blocked == null;
    final picked = selected == choice;

    return Pressable(
      onTap: usable ? () => onSelect(choice) : null,
      scale: 0.97,
      child: AnimatedContainer(
        duration: TossMotion.base,
        curve: TossMotion.enter,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        width: double.infinity,
        decoration: BoxDecoration(
          color: picked ? TossColors.blue50 : TossColors.grey50,
          borderRadius: BorderRadius.circular(TossRadius.lg),
          border: Border.all(
            color: picked ? TossColors.blue500 : Colors.transparent,
            width: 2,
          ),
        ),
        child: Opacity(
          opacity: blocked == null ? 1 : 0.45,
          child: Row(
            children: [
              AnimatedScale(
                scale: picked ? 1.12 : 1,
                duration: TossMotion.base,
                curve: TossMotion.spring,
                child: EmojiTile(
                  emoji: DecisionChoice.emoji(choice),
                  size: 52,
                  bg: TossColors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(DecisionChoice.label(choice),
                        style: TossText.body1.copyWith(
                            color: picked
                                ? TossColors.blue600
                                : TossColors.grey900)),
                    const SizedBox(height: 2),
                    Text(
                      blocked ??
                          DecisionChoice.description(choice,
                              target: buyMoreTarget),
                      style: TossText.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                picked
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 24,
                color: picked ? TossColors.blue500 : TossColors.grey300,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================
// 속보 카드 — 위기 대응 장면의 첫 화면
//  진한 카드에 '⚡ 속보' / '📣 희소식' 배지와 헤드라인을 크게. 등장할 때 살짝 커지며 나타난다.
// =============================================
class BreakingNewsCard extends StatelessWidget {
  final NewsItem news;
  const BreakingNewsCard({super.key, required this.news});

  @override
  Widget build(BuildContext context) {
    final (badge, badgeBg, badgeFg, glow) = switch (news.level) {
      'danger'   => ('⚡ 속보', TossColors.orange500, TossColors.grey900,
          const Color(0xFF3A2A12)),
      'positive' => ('📣 희소식', TossColors.green500, TossColors.white,
          const Color(0xFF0E3326)),
      _          => ('📰 뉴스', TossColors.grey500, TossColors.white,
          TossColors.grey800),
    };

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: TossMotion.spring,
      builder: (_, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TossRadius.xl),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [TossColors.grey900, glow],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(badge,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: badgeFg)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    news.source.isEmpty
                        ? news.date
                        : '${news.date} · ${news.source}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: TossColors.grey400),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(news.headline,
                style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    height: 1.4,
                    color: TossColors.white)),
          ],
        ),
      ),
    );
  }
}
