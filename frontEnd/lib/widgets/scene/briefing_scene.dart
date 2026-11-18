import 'package:flutter/material.dart';
import '../../models/briefing.dart';
import '../../theme/toss_theme.dart';
import '../toss/toss_widgets.dart';
import 'scene_widgets.dart';

// =============================================
// 시작 전 브리핑 — 넘겨 보는 3장면
//  ① 그날의 시장 날씨 (큰 그림)  ② 무슨 일이 있었나요 (배경을 말풍선으로)  ③ 시장 지도 (종목 타일)
//  기존에는 글 한 덩어리와 칩 목록이 카드 선택지 위에 붙어 있었다.
//  게임 시작 전 정보만 쓴다 (서버 briefing: 직전 20거래일 등락 + 시나리오 배경).
// =============================================
class BriefingScene extends StatefulWidget {
  final Briefing briefing;
  final String scenarioTitle;
  final String startDate;      // 게임 첫날 '2008-09-02'
  final VoidCallback onDone;   // 마지막 장면의 버튼 → 첫 카드 고르기

  const BriefingScene({
    super.key,
    required this.briefing,
    required this.scenarioTitle,
    required this.startDate,
    required this.onDone,
  });

  /// '2008-09-02' → '2008년 9월 2일'
  static String longDate(String date) {
    final p = date.split('-');
    if (p.length < 3) return date;
    final m = int.tryParse(p[1]);
    final d = int.tryParse(p[2]);
    return (m == null || d == null) ? date : '${p[0]}년 $m월 $d일';
  }

  @override
  State<BriefingScene> createState() => _BriefingSceneState();
}

class _BriefingSceneState extends State<BriefingScene> {
  final PageController _pager = PageController();
  int _page = 0;

  Briefing get b => widget.briefing;
  bool get _hasMarket => b.days > 0 && b.assets.isNotEmpty;

  // 시작 전 S&P500 등락 (자산 목록 → 없으면 흐름선 처음·끝)
  double? get _spxChange {
    for (final a in b.assets) {
      if (a.ticker == '^SPX') return a.changeRate;
    }
    final s = b.spxSeries;
    if (s.length >= 2 && s.first > 0) return (s.last - s.first) / s.first * 100;
    return null;
  }

  List<String> get _sentences => b.intro
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _next(int total) {
    if (_page >= total - 1) {
      widget.onDone();
      return;
    }
    _pager.nextPage(duration: TossMotion.slow, curve: TossMotion.enter);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _cover(),
      if (_sentences.isNotEmpty) _story(),
      if (_hasMarket) _marketMap(),
    ];
    final last = _page >= pages.length - 1;

    return RevealScope(
      child: SceneSheet(
      fullScreen: true,
      tag: SceneTag('📅 ${BriefingScene.longDate(widget.startDate)}'),
      trailing: last
          ? null
          : Pressable(
              onTap: widget.onDone,
              haptic: false,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text('건너뛰기',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: TossColors.grey500)),
              ),
            ),
      // 장면마다 스크롤은 각 페이지가 가진다 (PageView는 시트의 스크롤 안에 넣지 않는다)
      scrollBody: false,
      body: PageView(
        controller: _pager,
        onPageChanged: (i) => setState(() => _page = i),
        children: [
          // 장면마다 따로 착착 나타난다 (넘길 때마다 새로)
          for (final p in pages)
            RevealScope(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: p,
              ),
            ),
        ],
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dots(pages.length),
          const SizedBox(height: 14),
          Reveal(
            order: 5,
            child: TossButton(
              label: last ? '첫 전략 고르기' : '다음',
              onTap: () => _next(pages.length),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _dots(int n) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < n; i++)
          AnimatedContainer(
            duration: TossMotion.base,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == _page ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == _page ? TossColors.blue500 : TossColors.grey200,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }

  // ① 그날의 시장 날씨
  Widget _cover() {
    final spx = _spxChange;
    final mood = spx == null
        ? const MarketMood('🗞️', '알 수 없음', '시작 전 시장 기록이 없어요',
            [Color(0xFFF2F4F6), Color(0xFFE5E8EB)])
        : MarketMood.period(spx);

    return Column(
      children: [
        const SizedBox(height: 24),
        MoodHero(mood: mood, size: 168),
        const SizedBox(height: 28),
        Reveal(
          order: 2,
          child: Text(widget.scenarioTitle,
              textAlign: TextAlign.center, style: TossText.title1),
        ),
        const SizedBox(height: 10),
        Reveal(
          order: 3,
          child: Column(
            children: [
              Text('오늘의 시장 날씨는 ‘${mood.label}’',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: TossColors.grey800)),
              const SizedBox(height: 6),
              Text(mood.line,
                  textAlign: TextAlign.center,
                  style: TossText.sub.copyWith(color: TossColors.grey600)),
            ],
          ),
        ),
        if (spx != null) ...[
          const SizedBox(height: 20),
          Reveal(
            order: 4,
            child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: TossColors.grey50,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    b.days > 0
                        ? '지난 ${b.days}거래일 S&P500  '
                        : 'S&P500  ',
                    style: TossText.caption),
                Text(formatSigned(spx),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: TossColors.rate(spx),
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  // ② 무슨 일이 있었나요 — 배경을 문장 단위 말풍선으로
  Widget _story() {
    final lines = _sentences;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Reveal(order: 0, child: Text('📰', style: TextStyle(fontSize: 44))),
        const SizedBox(height: 10),
        const Reveal(
            order: 1, child: Text('무슨 일이\n있었나요?', style: TossText.title1)),
        const SizedBox(height: 20),
        // 말풍선은 한 줄씩 조금 더 천천히 (읽는 속도)
        for (int i = 0; i < lines.length; i++)
          Reveal(
            order: 3 + i * 2,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
              decoration: BoxDecoration(
                color: i == lines.length - 1
                    ? TossColors.blue50
                    : TossColors.grey50,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: Text(lines[i],
                  style: TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      fontWeight: i == lines.length - 1
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: TossColors.grey900)),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ③ 시장 지도 — 직전 20거래일 흐름선 + 종목 타일
  Widget _marketMap() {
    final spx = _spxChange;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Reveal(order: 0, child: Text('🗺️', style: TextStyle(fontSize: 44))),
        const SizedBox(height: 10),
        Reveal(
          order: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('시작 전 시장 지도', style: TossText.title1),
              const SizedBox(height: 6),
              Text('게임 시작 직전 ${b.days}거래일 동안 이렇게 움직였어요',
                  style: TossText.sub.copyWith(color: TossColors.grey600)),
            ],
          ),
        ),
        if (b.spxSeries.length >= 2) ...[
          const SizedBox(height: 18),
          Reveal(
            order: 2,
            child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: TossColors.grey50,
              borderRadius: BorderRadius.circular(TossRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('📈 S&P500 흐름', style: TossText.body2),
                    const Spacer(),
                    if (spx != null)
                      Text(formatSigned(spx),
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: TossColors.rate(spx))),
                  ],
                ),
                const SizedBox(height: 10),
                Sparkline(values: b.spxSeries, height: 72),
              ],
            ),
          ),
          ),
        ],
        const SizedBox(height: 10),
        LayoutBuilder(builder: (_, c) {
          final w = (c.maxWidth - 8) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < b.assets.length; i++)
                SizedBox(
                  width: w,
                  child: Reveal(
                    order: 3 + i,
                    child: AssetMoveTile(
                      ticker: b.assets[i].ticker,
                      name: b.assets[i].name,
                      change: b.assets[i].changeRate,
                    ),
                  ),
                ),
            ],
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }
}
