import 'package:flutter/material.dart';
import '../models/news_item.dart';

// =============================================
// 뉴스 배너 (11주차)
// 게임 화면 위에 겹쳐 띄우는 카드 — 기존 레이아웃을 밀어내지 않는다.
// =============================================

class NewsStyle {
  final Color accent;
  final Color background;
  final IconData icon;
  final String label;
  const NewsStyle(this.accent, this.background, this.icon, this.label);

  static NewsStyle of(String level) {
    switch (level) {
      case 'danger':
        return const NewsStyle(Color(0xFFE03131), Color(0xFFFFF5F5),
            Icons.warning_amber_rounded, '위험');
      case 'positive':
        return const NewsStyle(Color(0xFF2F9E44), Color(0xFFF4FCF5),
            Icons.trending_up_rounded, '긍정');
      default:
        return const NewsStyle(Color(0xFFE8A200), Color(0xFFFFFBEB),
            Icons.info_outline_rounded, '주의');
    }
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
      if (news.source.isNotEmpty) '출처: ${news.source}',
      if (sticky) '카드를 고를 때 참고하세요',
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: onClose,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: style.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: style.accent.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(style.icon, size: 18, color: style.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      news.headline,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111111),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF6B7684)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.close_rounded,
                  size: 16, color: Color(0xFF9AA0A6)),
            ],
          ),
        ),
      ),
    );
  }
}

// 지금까지 나온 뉴스 목록 (헤더 📰 버튼)
void showNewsLogSheet(BuildContext context, List<NewsItem> log) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('지금까지의 뉴스',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111111))),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: log.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (_, i) {
                  final n = log[log.length - 1 - i]; // 최신 순
                  final s = NewsStyle.of(n.level);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(s.icon, size: 16, color: s.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n.headline,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF111111))),
                            const SizedBox(height: 2),
                            Text(
                              [n.date, if (n.source.isNotEmpty) '출처: ${n.source}']
                                  .join(' · '),
                              style: const TextStyle(
                                  fontSize: 10, color: Color(0xFF6B7684)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
