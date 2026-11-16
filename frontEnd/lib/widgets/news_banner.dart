import 'package:flutter/material.dart';
import '../models/news_item.dart';
import '../theme/toss_theme.dart';
import 'toss/toss_widgets.dart';

// =============================================
// 뉴스 배너 (11주차) — 토스 스타일
// 게임 화면 위에서 내려오는 진한 알림 카드. 기존 레이아웃을 밀어내지 않는다.
// 이 앱에서 빨강은 '수익' 색이라, 위험 뉴스는 빨강 대신 주황으로 표시한다.
// =============================================

class NewsStyle {
  final Color accent;     // 라벨 바탕 (진한 배너 위)
  final Color onAccent;   // 라벨 글자
  final Color softBg;     // 흰 바탕 위 라벨 바탕 (목록 시트)
  final Color softFg;     // 흰 바탕 위 라벨 글자
  final String label;
  const NewsStyle(
      this.accent, this.onAccent, this.softBg, this.softFg, this.label);

  static NewsStyle of(String level) {
    switch (level) {
      case 'danger':
        return const NewsStyle(TossColors.orange500, TossColors.grey900,
            Color(0xFFFFF3E0), Color(0xFFC25E00), '위험');
      case 'positive':
        return const NewsStyle(TossColors.green500, TossColors.white,
            TossColors.green50, Color(0xFF02874F), '긍정');
      default:
        return const NewsStyle(TossColors.grey500, TossColors.white,
            TossColors.grey100, TossColors.grey700, '주의');
    }
  }
}

class _LevelLabel extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const _LevelLabel(this.text, this.bg, this.fg);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

class NewsBanner extends StatelessWidget {
  final NewsItem news;
  final VoidCallback onClose;
  final bool sticky; // 카드 선택 라운드: 고를 때까지 유지

  const NewsBanner({
    super.key,
    required this.news,
    required this.onClose,
    this.sticky = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = NewsStyle.of(news.level);
    final sub = [
      news.date,
      if (news.source.isNotEmpty) news.source,
      if (sticky) '카드를 고를 때 참고하세요',
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: Pressable(
        onTap: onClose,
        haptic: false,
        scale: 0.98,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            color: TossColors.grey900,
            borderRadius: BorderRadius.circular(TossRadius.lg + 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: _LevelLabel(style.label, style.accent, style.onAccent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      news.headline,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: TossColors.white,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sub,
                      style: const TextStyle(
                          fontSize: 12, color: TossColors.grey400),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.close_rounded,
                  size: 18, color: TossColors.grey500),
            ],
          ),
        ),
      ),
    );
  }
}

// 지금까지 나온 뉴스 목록 (헤더 신문 버튼)
void showNewsLogSheet(BuildContext context, List<NewsItem> log) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: TossColors.white,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(TossRadius.sheet)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('지금까지 나온 뉴스 ${log.length}개', style: TossText.title2),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: log.length,
                  itemBuilder: (_, i) {
                    final n = log[log.length - 1 - i]; // 최신 순
                    final s = NewsStyle.of(n.level);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: _LevelLabel(s.label, s.softBg, s.softFg),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(n.headline,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        height: 1.4,
                                        color: TossColors.grey900)),
                                const SizedBox(height: 2),
                                Text(
                                  [n.date, if (n.source.isNotEmpty) n.source]
                                      .join(' · '),
                                  style: TossText.small,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              TossButton(
                label: '닫기',
                type: TossButtonType.secondary,
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
