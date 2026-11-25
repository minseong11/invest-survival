import 'package:flutter/material.dart';
import '../models/decision.dart';
import '../models/news_item.dart';
import '../theme/toss_theme.dart';
import 'scene/scene_widgets.dart';
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
  final Widget? info;                // 큰 숫자와 질문 사이에 넣을 내용 (지금 내 상황)
  final double? dayMove;             // (게임 장면 개편) 그날 S&P500 하루 등락 — 크게 '쾅'

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
    this.dayMove,
  });

  // 어두운 배경에서 읽히는 상승·하락 색
  static Color darkRate(double v) =>
      v > 0 ? const Color(0xFFFF6B76) : (v < 0 ? const Color(0xFF6EA8FF) : TossColors.grey400);

  @override
  Widget build(BuildContext context) {
    final news = prompt?.news;

    // (게임 장면 개편) 어두운 장면: 속보 배지·헤드라인 → 그날 S&P500 등락을 크게 → 내 상황 → 질문 → 선택지 착착
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (news != null) ...[
          _NewsHeadline(news: news),
          const SizedBox(height: 14),
        ],
        if (dayMove != null) ...[
          Reveal(order: 1, child: _BigMove(change: dayMove!)),
          const SizedBox(height: 16),
        ],
        if (info != null) ...[
          Reveal(order: 2, child: info!),
          const SizedBox(height: 18),
        ],
        Reveal(
          order: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('어떻게 대응할까요?',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: TossColors.white)),
              for (final n in otherNews)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('· ${n.headline}',
                      style: const TextStyle(
                          fontSize: 13, height: 1.4, color: TossColors.grey400)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        for (int i = 0; i < DecisionChoice.all.length; i++)
          // 선택지가 하나씩 올라온다 (간격을 넓혀 하나씩 보이게)
          Reveal(
            order: 4 + i * 2,
            rise: 28,
            child: _buildChoice(DecisionChoice.all[i]),
          ),
        const SizedBox(height: 6),
        const Reveal(
          order: 9,
          child: Text(
            '오늘 종가로 바로 매매하고, 전략 카드는 계속 작동해요.',
            style: TextStyle(fontSize: 12.5, color: TossColors.grey500),
          ),
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
      child: AnimatedScale(
        scale: picked ? 1.02 : 1,
        duration: TossMotion.base,
        curve: TossMotion.spring,
        child: AnimatedContainer(
          duration: TossMotion.base,
          curve: TossMotion.enter,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          width: double.infinity,
          decoration: BoxDecoration(
            color: picked
                ? TossColors.blue500
                : TossColors.white.withValues(alpha: blocked == null ? 0.08 : 0.03),
            borderRadius: BorderRadius.circular(TossRadius.lg),
            border: Border.all(
              color: picked
                  ? TossColors.blue500
                  : TossColors.white.withValues(alpha: blocked == null ? 0.14 : 0.08),
              width: 1.5,
            ),
          ),
          child: Opacity(
            opacity: blocked == null ? 1 : 0.45,
            child: Row(
              children: [
                EmojiTile(
                  emoji: DecisionChoice.emoji(choice),
                  size: 44,
                  bg: TossColors.white.withValues(alpha: picked ? 0.2 : 0.1),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(DecisionChoice.label(choice),
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: TossColors.white)),
                      const SizedBox(height: 2),
                      Text(
                        blocked ??
                            DecisionChoice.description(choice,
                                target: buyMoreTarget),
                        style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: TossColors.white
                                .withValues(alpha: picked ? 0.9 : 0.65)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedOpacity(
                  opacity: picked ? 1 : 0,
                  duration: TossMotion.base,
                  child: const Icon(Icons.check_circle_rounded,
                      size: 24, color: TossColors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 속보 배지 + 헤드라인 (어두운 장면 위에 흰 글씨). 등장할 때 살짝 커지며 나타난다
class _NewsHeadline extends StatelessWidget {
  final NewsItem news;
  const _NewsHeadline({required this.news});

  @override
  Widget build(BuildContext context) {
    final (badge, badgeBg, badgeFg) = switch (news.level) {
      'danger'   => ('⚡ 속보', const Color(0xFFE5333F), TossColors.white),
      'positive' => ('📣 희소식', TossColors.green500, TossColors.white),
      _          => ('📰 뉴스', TossColors.grey600, TossColors.white),
    };
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: TossMotion.spring,
      builder: (_, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(
            scale: 0.94 + 0.06 * t, alignment: Alignment.centerLeft, child: child),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(badge,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: badgeFg)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  news.source.isEmpty ? news.date : '${news.date} · ${news.source}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: TossColors.grey400),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FitHeadline(
            text: news.headline,
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                height: 1.35,
                color: TossColors.white),
          ),
        ],
      ),
    );
  }
}

// 그날 S&P500 하루 등락을 크게 — 크게 시작해 제자리로 '쾅'
class _BigMove extends StatelessWidget {
  final double change;
  const _BigMove({required this.change});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 1.5, end: 1),
          duration: const Duration(milliseconds: 550),
          curve: Curves.easeOutBack,
          builder: (_, s, child) => Transform.scale(
              scale: s, alignment: Alignment.bottomLeft, child: child),
          child: Text(formatSigned(change),
              style: TextStyle(
                  fontSize: 56,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                  color: DecisionSelector.darkRate(change),
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ),
        const SizedBox(width: 10),
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text('S&P500\n하루 만에',
              style: TextStyle(
                  fontSize: 13, height: 1.35, color: TossColors.grey400)),
        ),
      ],
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
            FitHeadline(
              text: news.headline,
              style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                  color: TossColors.white),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================
// 속보 제목 — 한 글자만 다음 줄로 넘어가지 않게
//  기존: 21px 고정이라 넓은 화면에서도 "…서킷브레이커 발 / 동"처럼 마지막 글자만 다음 줄로 넘어갔다.
//  ① 한 줄에 들어가면 한 줄로: 글자 크기를 21px에서 최소 17px까지 1px씩 줄여 본다.
//  ② 그래도 안 들어가는 긴 제목(좁은 휴대폰)은 글자를 더 줄이지 않고,
//     쉼표 뒤·괄호 앞을 먼저 고려해 가운데에 가까운 띄어쓰기에서 두 줄로 고르게 나눈다.
//     ("사우디·러시아 유가 전쟁, / 미 증시 서킷브레이커 발동")
// =============================================
class FitHeadline extends StatelessWidget {
  final String text;
  final TextStyle style;        // fontSize = 가장 큰 크기
  final double minFontSize;

  const FitHeadline({
    super.key,
    required this.text,
    required this.style,
    this.minFontSize = 17,
  });

  static double _width(String s, TextStyle style, TextScaler scaler) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  // 두 줄로 나눌 띄어쓰기 고르기: 두 줄 다 폭 안에 들어가는 것 중 길이가 가장 비슷한 곳
  //  (쉼표 뒤나 괄호 앞이면 조금 더 낫게 친다). 없으면 null
  static String? balancedTwoLines(
      String text, TextStyle style, TextScaler scaler, double maxWidth) {
    String? best;
    double bestScore = double.infinity;
    for (int i = 0; i < text.length; i++) {
      if (text[i] != ' ') continue;
      final a = text.substring(0, i).trimRight();
      final b = text.substring(i + 1).trimLeft();
      if (a.isEmpty || b.isEmpty) continue;
      final wa = _width(a, style, scaler);
      final wb = _width(b, style, scaler);
      if (wa > maxWidth || wb > maxWidth) continue;
      final natural = a.endsWith(',') || b.startsWith('(');
      final score = (wa - wb).abs() - (natural ? maxWidth * 0.2 : 0);
      if (score < bestScore) {
        bestScore = score;
        best = '$a\n$b';
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth = constraints.maxWidth;
      final base = style.fontSize ?? 21;

      // ① 한 줄
      for (double size = base; size >= minFontSize; size -= 1) {
        final s = style.copyWith(fontSize: size);
        if (_width(text, s, scaler) <= maxWidth - 1) {
          return Text(text, style: s, maxLines: 1, softWrap: false);
        }
      }
      // ② 두 줄로 고르게 (가능하면 원래 크기로)
      for (final size in [base, minFontSize]) {
        final s = style.copyWith(fontSize: size);
        final split = balancedTwoLines(text, s, scaler, maxWidth);
        if (split != null) return Text(split, style: s);
      }
      // ③ 그래도 안 되면 보통 줄바꿈
      return Text(text, style: style.copyWith(fontSize: minFontSize));
    });
  }
}
