import 'package:flutter/material.dart';
import '../models/decision.dart';
import '../models/news_item.dart';
import '../theme/toss_theme.dart';
import 'news_banner.dart';
import 'toss/toss_widgets.dart';

// =============================================
// (#125) 위기 대응 선택 — 뉴스 속보가 나온 라운드에서 게임이 멈추고 보인다
//  속보 한 줄 + 선택지 3개(버틴다 / 절반 판다 / 더 산다). 고른 뒤 하단 버튼으로 확정한다.
//  카드 선택과 같은 모양(목록에서 고르고 → 확정)이라 따로 익힐 것이 없다.
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
  });

  @override
  Widget build(BuildContext context) {
    final news = prompt?.news;
    final good = news?.level == 'positive';

    return TossSection(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(good ? '좋은 소식이 나왔어요\n어떻게 할까요?' : '속보가 나왔어요\n어떻게 대응할까요?',
              style: TossText.title3),
          if (news != null) ...[
            const SizedBox(height: 12),
            _buildNews(news),
          ],
          for (final n in otherNews)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('· ${n.headline}', style: TossText.caption),
            ),
          const SizedBox(height: 8),
          for (int i = 0; i < DecisionChoice.all.length; i++)
            FadeInUp(
              delay: Duration(milliseconds: 60 * i),
              child: _buildChoice(DecisionChoice.all[i]),
            ),
          const SizedBox(height: 4),
          const Text(
            '오늘 종가로 바로 매매하고, 전략 카드는 계속 작동해요.',
            style: TossText.small,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildNews(NewsItem news) {
    final st = NewsStyle.of(news.level);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: st.softBg,
        borderRadius: BorderRadius.circular(TossRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(st.label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: st.softFg)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  news.source.isEmpty
                      ? news.date
                      : '${news.date} · ${news.source}',
                  style: TossText.small,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(news.headline,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                  color: TossColors.grey900)),
        ],
      ),
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
      scale: 0.98,
      child: AnimatedContainer(
        duration: TossMotion.base,
        curve: TossMotion.enter,
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        width: double.infinity,
        decoration: BoxDecoration(
          color: picked ? TossColors.blue50 : Colors.transparent,
          borderRadius: BorderRadius.circular(TossRadius.lg),
        ),
        child: Opacity(
          opacity: blocked == null ? 1 : 0.45,
          child: Row(
            children: [
              EmojiTile(
                emoji: DecisionChoice.emoji(choice),
                bg: picked ? TossColors.white : TossColors.grey100,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(DecisionChoice.label(choice), style: TossText.body2),
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
