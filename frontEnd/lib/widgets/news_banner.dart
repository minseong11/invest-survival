import 'package:flutter/material.dart';
import '../models/news_item.dart';
import '../theme/toss_theme.dart';
import 'toss/toss_widgets.dart';

// =============================================
// 뉴스 표시 (11주차) — 토스 스타일
// 게임 화면 위쪽의 '최근 뉴스' 칸과 지금까지 나온 뉴스 목록.
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

// =============================================
// 최근 뉴스 칸 — 게임 화면 위쪽(라운드 표시 바로 아래)에 늘 있는 한 줄 칸
//  기존: 뉴스가 나오면 화면 맨 위(뒤로 가기·제목·라운드)를 5초 동안 덮는 배너가 내려왔다
//        (×4 배속에서 5초는 40라운드 — 그동안 라운드 표시를 볼 수 없었다)
//  지금: 칸이 처음부터 자리를 차지해 아무것도 가리지 않고, 다음 뉴스가 올 때까지 남아 있다.
//        새 뉴스가 오면 칸이 잠깐 그 뉴스 색으로 물들고 '새 소식'이 붙는다.
//        누르면 지금까지 나온 뉴스 목록 (기존 헤더의 신문 버튼 자리를 옮김)
// =============================================
class NewsStrip extends StatelessWidget {
  final NewsItem? news;        // 가장 최근 뉴스 (없으면 안내 문구)
  final int count;             // 지금까지 나온 뉴스 수
  final bool fresh;            // 방금 나온 뉴스 → 칸이 물들고 '새 소식'
  final VoidCallback? onTap;   // 뉴스 목록 열기

  static const double height = 56;

  const NewsStrip({
    super.key,
    required this.news,
    required this.count,
    this.fresh = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final n = news;
    final style = n == null ? null : NewsStyle.of(n.level);

    final Widget content = n == null
        ? const Row(
            children: [
              Text('📰', style: TextStyle(fontSize: 16)),
              SizedBox(width: 10),
              Expanded(
                child: Text('뉴스가 나오면 여기에 보여요',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: TossColors.grey500)),
              ),
            ],
          )
        : Row(
            children: [
              _LevelLabel(style!.label, style.accent, style.onAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: TossColors.grey900)),
                    const SizedBox(height: 1),
                    Text(
                      [n.date, if (n.source.isNotEmpty) n.source].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: TossColors.grey500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: TossMotion.fast,
                child: fresh
                    ? Container(
                        key: const ValueKey('fresh'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: style.softFg,
                          borderRadius: BorderRadius.circular(TossRadius.sm),
                        ),
                        child: const Text('새 소식',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: TossColors.white)),
                      )
                    : Row(
                        key: const ValueKey('count'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('전체 $count',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: TossColors.grey500)),
                          const Icon(Icons.chevron_right_rounded,
                              size: 18, color: TossColors.grey400),
                        ],
                      ),
              ),
            ],
          );

    return Semantics(
      container: true,
      button: n != null,
      label: n == null ? null : '최근 뉴스, 누르면 지금까지 나온 뉴스 $count개',
      child: Pressable(
        onTap: n == null ? null : onTap,
        haptic: false,
        scale: 0.99,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut,
          height: height,
          padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
          decoration: BoxDecoration(
            color: fresh && style != null ? style.softBg : TossColors.white,
            borderRadius: BorderRadius.circular(TossRadius.lg),
          ),
          child: content,
        ),
      ),
    );
  }
}

// 지금까지 나온 뉴스 목록 (최근 뉴스 칸을 누르면)
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
