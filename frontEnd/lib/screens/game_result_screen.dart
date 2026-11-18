import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/game_session.dart';
import '../models/card_info.dart';
import '../models/coach_comment.dart';
import '../models/decision.dart';
import '../models/result_analysis.dart';
import '../models/round_data.dart';
import '../services/game_service.dart';
import '../widgets/news_banner.dart';
import '../widgets/scene/scene_widgets.dart';
import '../theme/toss_theme.dart';
import '../widgets/toss/toss_widgets.dart';

class GameResultScreen extends StatefulWidget {
  final GameSession session;
  // 게임 중 받은 AI 예측 1순위 (라운드 → 카드 ID). 예측을 안 받은 라운드는 없음
  final Map<int, int> aiPicks;
  // 테스트에서 가짜 서버를 넣을 수 있게 (없으면 실제 서버)
  final GameService? service;

  const GameResultScreen({
    super.key,
    required this.session,
    this.aiPicks = const {},
    this.service,
  });

  @override
  State<GameResultScreen> createState() => _GameResultScreenState();
}

class _GameResultScreenState extends State<GameResultScreen> {
  late final GameService _gameService = widget.service ?? GameService();

  // 숫자 공개 연출: 처음엔 시작 자산·0%를 보여주고, 잠시 뒤 최종 값으로 굴러감
  bool _revealed = false;
  Timer? _revealTimer;

  // 사후 분석 (백테스팅, API v6.1)
  ResultAnalysis? _analysis;
  bool _analysisLoading = true;

  // (#125) AI 코치 한마디 — 분석이 온 뒤 따로 불러온다 (AI 문장을 기다리느라 분석 표시가 늦어지지 않게)
  CoachComment? _coach;
  bool _coachLoading = false;

  static const List<int> _selectRounds = [1, 25, 50, 75];

  // (장면 개편) 결과를 한 장씩 넘겨 본다. '한 번에 보기'를 누르면 기존처럼 한 페이지로
  final PageController _pager = PageController();
  int _page = 0;
  bool _listMode = false;

  double get _finalAsset {
    for (int i = widget.session.rounds.length - 1; i >= 0; i--) {
      if (widget.session.rounds[i].roundAsset != null) {
        return widget.session.rounds[i].roundAsset!;
      }
    }
    return widget.session.initialAsset.toDouble();
  }

  double get _finalReturnRate {
    for (int i = widget.session.rounds.length - 1; i >= 0; i--) {
      if (widget.session.rounds[i].returnRate != null) {
        return widget.session.rounds[i].returnRate!;
      }
    }
    return 0.0;
  }

  // 같은 기간 S&P500 수익률 (아무 카드 없이 시장만 들고 있었다면). 데이터 없으면 null
  double? get _spxReturn {
    double? first, last;
    for (final r in widget.session.rounds) {
      final p = r.getPrice('^SPX');
      if (p == null || p.close <= 0) continue;
      first ??= p.close;
      last = p.close;
    }
    if (first == null || last == null) return null;
    return (last - first) / first * 100;
  }

  // 한 줄 결론: 시장(S&P500)과 비교
  String get _headline {
    final mine = _finalReturnRate;
    final spx  = _spxReturn;
    if (spx == null) {
      return mine >= 0 ? '위기에서 살아남았어요' : '이번엔 손실을 봤어요';
    }
    // (#125) 표시하면 0.0%p인 차이 — "시장보다 0.0%p 덜 잃었어요" 대신
    if ((mine - spx).abs() < kMinVisibleGap) return '시장과 거의\n같은 결과예요';
    final gap = (mine - spx).abs().toStringAsFixed(1);
    if (mine >= spx) {
      if (mine >= 0 && spx < 0) return '시장은 떨어졌지만\n수익을 냈어요';
      return mine >= 0 ? '시장보다 $gap%p\n더 벌었어요' : '시장보다 $gap%p\n덜 잃었어요';
    }
    // (#125) 시장은 올랐는데 나는 손실 — "시장보다 n%p 더 잃었어요"는 시장도 잃은 것처럼 읽힌다
    if (mine < 0 && spx >= 0) return '시장은 올랐지만\n손실을 봤어요';
    return mine >= 0 ? '시장보다 $gap%p\n덜 벌었어요' : '시장보다 $gap%p\n더 잃었어요';
  }

  bool get _beatMarket {
    final spx = _spxReturn;
    return spx == null ? _finalReturnRate >= 0 : _finalReturnRate >= spx;
  }

  @override
  void initState() {
    super.initState();

    // 화면 진입 후 0.5초 뒤 숫자 공개
    _revealTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _revealed = true);
    });

    // 사후 분석: 결과 화면 진입 시 1회 호출 (v6.1 합의 2번)
    _loadAnalysis();
  }

  Future<void> _loadAnalysis() async {
    final result = await _gameService.getResultAnalysis(
      sessionId: widget.session.sessionId,
    );
    if (!mounted) return;
    setState(() {
      _analysis        = result;
      _analysisLoading = false;
      _coachLoading    = result != null;
    });
    if (result != null) _loadCoach();
  }

  // (12주차 피드백 2번) AI 호출 실패 시 안내 + 다시 시도 (기존: 그 칸이 조용히 사라졌다)
  void _retryAnalysis() {
    setState(() {
      _analysisLoading = true;
      _coachLoading    = false;
    });
    _loadAnalysis();
  }

  void _retryCoach() {
    setState(() => _coachLoading = true);
    _loadCoach();
  }

  Widget _buildFailedCard({
    required String emoji,
    required String title,
    required String body,
    required VoidCallback onRetry,
  }) {
    return TossSection(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 40)),
          const SizedBox(height: 10),
          Text(title, style: TossText.title3),
          const SizedBox(height: 6),
          Text(body, style: TossText.sub),
          const SizedBox(height: 16),
          TossButton(
            label: '다시 시도',
            type: TossButtonType.secondary,
            onTap: onRetry,
          ),
        ],
      ),
    );
  }

  Future<void> _loadCoach() async {
    final coach = await _gameService.getResultCoach(
      sessionId: widget.session.sessionId,
    );
    if (!mounted) return;
    setState(() {
      _coach        = coach;
      _coachLoading = false;
    });
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _pager.dispose();
    super.dispose();
  }

  String _formatNumber(double value) => formatWon(value);

  // (#125) 전체 조합 중 위치: 절반보다 위면 "상위 n%", 아래면 "하위 n%" (기존: 하위권도 "상위 87.9%")
  String _formatTopPercent(double p) => formatRankPosition(p);

  String _cardEmoji(int cardId) => CardInfo.fromId(cardId)?.emoji ?? '🃏';

  String _cardName(AnalysisCard c) => c.cardName.isNotEmpty
      ? c.cardName
      : (CardInfo.fromId(c.cardId)?.name ?? '카드 ${c.cardId}');

  // =============================================
  // (장면 개편) 결과 패널 — 한 장씩 넘기는 결과창
  //  ① 결과 → ② 시장과 비교 → ③ 내 순위 → ④ 라운드별로 → ⑤ 카드별 성적표 → ⑥ 위기 대응
  //  → ⑦ AI 코치 → ⑧ 그 후 이야기 (마지막 장면)
  //  사후 분석은 ①·②를 보는 동안 계산되고, 아직이면 ③ 자리에 계산 중 장면이 보인다.
  //  '참고: 이 시장에서 가장 잘 통한 전략'(11장 전체 1위)은 게임 중 고를 수 없던 카드라 뺐다.
  // =============================================
  List<Widget> _panels() {
    final a = _analysis;
    final o = a?.offered;
    return [
      _buildHero(),
      _buildCompareBars(),
      if (_analysisLoading)
        _buildAnalysisLoading()
      else if (a == null)
        _buildFailedCard(
          emoji: '😥',
          title: '사후 분석을 불러오지 못했어요',
          body: '게임 결과와 시장 비교는 위에 그대로 있어요. '
              'AI 서버가 잠시 응답하지 않았을 수 있어요.',
          onRetry: _retryAnalysis,
        )
      else ...[
        o != null ? _buildOfferedRankCard(a, o) : _buildRankCard(a),
        _buildRoundReviewCard(o),
        if (a.cardReport.isNotEmpty) _buildCardReportCard(a.cardReport),
        if (a.decisionReview != null && a.decisionReview!.rounds.isNotEmpty)
          _buildDecisionReviewCard(a.decisionReview!),
        if (_coach != null || _coachLoading)
          _buildCoachCard()
        else
          _buildFailedCard(
            emoji: '🤖',
            title: 'AI 코치 한마디를 받지 못했어요',
            body: '사후 분석 결과는 그대로 볼 수 있어요. AI 서버 연결을 확인한 뒤 다시 시도해 주세요.',
            onRetry: _retryCoach,
          ),
        if (a.epilogue != null && a.epilogue!.points.isNotEmpty)
          _buildEpilogueCard(a.epilogue!),
      ],
    ];
  }

  void _goHome() => Navigator.of(context).popUntil((route) => route.isFirst);

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final panels = _panels();
    final page = _page.clamp(0, panels.length - 1);
    final last = page >= panels.length - 1;

    return Scaffold(
      // 한 장씩: 흰 바탕 위에 패널 하나 / 한 번에: 회색 바탕 위에 흰 패널을 쌓음
      backgroundColor: _listMode ? TossColors.background : TossColors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 위: 진행 표시 + 보기 방식
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
              child: Row(
                children: [
                  Text(
                    _listMode ? '결과 한 번에 보기' : '${page + 1} / ${panels.length}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: TossColors.grey500,
                        fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                  const Spacer(),
                  Pressable(
                    onTap: () => setState(() => _listMode = !_listMode),
                    haptic: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Text(_listMode ? '한 장씩 보기' : '한 번에 보기',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: TossColors.blue500)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _listMode
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final p in panels) ...[
                            p,
                            const SizedBox(height: 8),
                          ],
                          _afterGameNote(),
                        ],
                      ),
                    )
                  : PageView(
                      controller: _pager,
                      onPageChanged: (i) {
                        HapticFeedback.selectionClick();
                        setState(() => _page = i);
                      },
                      children: [
                        // 장면마다 안의 내용이 착착 나타난다 (누르면 바로 전부)
                        for (int i = 0; i < panels.length; i++)
                          RevealScope(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Reveal(order: 0, child: panels[i]),
                                  if (i >= 2) _afterGameNote(),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),

            // 아래: 페이지 점 + 다음 / 처음으로
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_listMode) ...[
                    _dots(panels.length, page),
                    const SizedBox(height: 14),
                  ],
                  // 장면 내용이 나온 뒤 버튼이 보인다 (장면이 바뀔 때마다 다시)
                  RevealScope(
                    key: ValueKey('next-$page-$_listMode'),
                    child: Reveal(
                      order: _listMode ? 0 : 5,
                      child: TossButton(
                        label: (_listMode || last) ? '처음으로 돌아가기' : '다음',
                        onTap: (_listMode || last)
                            ? _goHome
                            : () => _pager.nextPage(
                                duration: TossMotion.slow,
                                curve: TossMotion.enter),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dots(int n, int page) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < n; i++)
          AnimatedContainer(
            duration: TossMotion.base,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == page ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == page ? TossColors.blue500 : TossColors.grey200,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }

  Widget _afterGameNote() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 4, 24, 0),
      child: Text(
        '게임이 끝난 뒤 100라운드 시장 데이터를 모두 써서 계산한 결과예요. '
        '게임 중에는 알 수 없는 정보예요.',
        style: TossText.small,
      ),
    );
  }

  // =============================================
  // 결과 요약: 한 줄 결론 + 최종 자산 (숫자 굴러감)
  // =============================================
  Widget _buildHero() {
    // 시장보다 잘했으면 축하. (#125) 단, 가능한 조합 중 하위권(C·D등급)이면 축하 표시는 하지 않는다
    final lowGrade = _analysis != null &&
        (_analysis!.grade == 'C' || _analysis!.grade == 'D');
    final profit  = _beatMarket && !lowGrade;
    final initial = widget.session.initialAsset.toDouble();
    final asset   = _revealed ? _finalAsset : initial;
    final rate    = _revealed ? _finalReturnRate : 0.0;
    final diff    = asset - initial;

    return TossSection(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // (장면 개편) 결과를 그림 하나로 먼저: 🏆 시장보다 잘함 / 🛡️ 시장보다 덜 잃음 / 🌱 수익 / 🌧️ 손실
          AnimatedSwitcher(
            duration: TossMotion.slow,
            child: _revealed
                ? MoodHero(key: const ValueKey('hero-on'), mood: _heroMood(profit), size: 112)
                : const SizedBox(key: ValueKey('hero-off'), width: 112, height: 112),
          ),
          const SizedBox(height: 22),
          Reveal(
            order: 1,
            child: Text(
              '${widget.session.scenarioTitle} · ${widget.session.totalRounds}라운드 완료',
              style: TossText.sub,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Flexible(
                child: Text(_headline, style: TossText.title1),
              ),
              const SizedBox(width: 6),
              if (profit)
                AnimatedScale(
                  scale: _revealed ? 1 : 0,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutBack,
                  child: const Text('🎉', style: TextStyle(fontSize: 26)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('최종 자산', style: TossText.caption),
          const SizedBox(height: 2),
          RollingText(
            '${_formatNumber(asset)}원',
            value: asset,
            duration: const Duration(milliseconds: 700),
            style: TossText.display.copyWith(fontSize: 32),
          ),
          const SizedBox(height: 4),
          // (#125) 퍼센트에도 부호를 붙인다 (기존: 손실일 때 "(20.95%)"로 표시)
          RollingText(
            '${diff >= 0 ? '+' : '-'}${_formatNumber(diff.abs())}원 '
            '(${formatSigned(rate, digits: 2)})',
            value: asset,
            duration: const Duration(milliseconds: 700),
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: _revealed
                    ? TossColors.rate(_finalReturnRate)
                    : TossColors.grey500,
                fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          // (#125) 등급 — 사후 분석이 오면 나타난다
          AnimatedSize(
            duration: TossMotion.slow,
            curve: TossMotion.enter,
            alignment: Alignment.topLeft,
            child: (_analysis == null || _analysis!.grade.isEmpty)
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: _buildGrade(_analysis!),
                  ),
          ),
        ],
      ),
    );
  }

  MarketMood _heroMood(bool celebrate) {
    final mine = _finalReturnRate;
    if (celebrate && mine >= 0) {
      return const MarketMood('🏆', '', '', [Color(0xFFFFF6E5), Color(0xFFFFE6BA)]);
    }
    if (_beatMarket) {
      return const MarketMood('🛡️', '', '', [Color(0xFFE8F3FF), Color(0xFFCFE2FA)]);
    }
    if (mine >= 0) {
      return const MarketMood('🌱', '', '', [Color(0xFFE5F8EF), Color(0xFFC9EEDC)]);
    }
    return const MarketMood('🌧️', '', '', [Color(0xFFF2F4F6), Color(0xFFDDE2E8)]);
  }

  // 등급 배지 + 전체 조합 중 위치
  Widget _buildGrade(ResultAnalysis a) {
    final (bg, fg) = switch (a.grade) {
      'S' => (TossColors.blue500, TossColors.white),
      'A' => (TossColors.blue50, TossColors.blue600),
      'B' => (TossColors.green50, const Color(0xFF02874F)),
      _   => (TossColors.grey100, TossColors.grey700),
    };
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(a.grade,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: fg)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${a.grade}등급', style: TossText.body2),
              Text(
                '가능한 카드 조합 ${_formatNumber(a.totalCombinations.toDouble())}개 중 '
                '${_formatTopPercent(a.playerResult.topPercent)}',
                style: TossText.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =============================================
  // 수익률 비교 막대 (토스 실적 화면처럼)
  //  S&P500 그대로 / 내 결과 / 받은 카드 중 최선(분석이 끝나면 나타남)
  // =============================================
  Widget _buildCompareBars() {
    final mine = _finalReturnRate;
    final spx  = _spxReturn;
    final best = _analysis?.offered?.bestCombo.finalReturnRate;

    final bars = <_Bar>[
      if (spx != null) _Bar('S&P500\n그대로', spx, false),
      _Bar('내 결과', mine, true),
      if (best != null) _Bar('받은 카드 중\n최선', best, false),
    ];

    return TossSection(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('수익률 비교', style: TossText.title3),
          const SizedBox(height: 10),
          if (spx != null) _diffLine('S&P500 그대로 뒀을 때보다', mine - spx),
          if (best != null) _diffLine('받은 카드 중 최선보다', mine - best),
          const SizedBox(height: 14),
          _BarChart(bars: bars, revealed: _revealed),
          if (_analysis?.risk != null) ...[
            const SizedBox(height: 16),
            _buildRisk(_analysis!.risk!),
          ],
        ],
      ),
    );
  }

  // (#125) 최대 낙폭 비교 — 게임 중 가장 크게 빠졌을 때 (고점 대비)
  Widget _buildRisk(RiskInfo risk) {
    Widget tile(String label, double mdd, String? date, bool mine) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: mine ? TossColors.blue50 : TossColors.grey50,
            borderRadius: BorderRadius.circular(TossRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TossText.small),
              const SizedBox(height: 2),
              Text(
                mdd.abs() < 0.005 ? '빠진 적 없음' : formatSigned(mdd),
                style: TossText.number.copyWith(
                    fontSize: 17,
                    color: mine ? TossColors.blue600 : TossColors.grey800),
              ),
              if (date != null) Text(date, style: TossText.small),
            ],
          ),
        ),
      );
    }

    // 낙폭은 0 이하의 값 — 0에 가까울수록 덜 빠진 것
    final calmer = risk.playerMdd >= risk.marketMdd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          calmer ? '가장 크게 빠졌을 때도 시장보다 덜 흔들렸어요' : '가장 크게 빠졌을 때는 시장보다 더 흔들렸어요',
          style: TossText.sub.copyWith(fontSize: 15, color: TossColors.grey700),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            tile('내 자산 최대 낙폭', risk.playerMdd, risk.playerMddDate, true),
            const SizedBox(width: 8),
            tile('S&P500 최대 낙폭', risk.marketMdd, risk.marketMddDate, false),
          ],
        ),
      ],
    );
  }

  // "· S&P500 그대로 뒀을 때보다 +23.6%p"
  Widget _diffLine(String label, double diff) {
    final zero = diff.abs() < 0.05;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Text('·  ', style: TossText.sub),
          Flexible(
            child: Text(label,
                style: TossText.sub.copyWith(
                    fontSize: 15, color: TossColors.grey700)),
          ),
          const SizedBox(width: 6),
          Text(
            zero
                ? '같아요'
                : '${diff > 0 ? '+' : ''}${diff.toStringAsFixed(1)}%p',
            style: TossText.number.copyWith(
                color: zero ? TossColors.grey700 : TossColors.rate(diff)),
          ),
        ],
      ),
    );
  }

  // 로딩 (서버가 게임 중에 미리 계산해 두면 바로 오고, 처음 계산이면 1~2초)
  Widget _buildAnalysisLoading() {
    return const TossSection(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Text('가능한 카드 조합을 모두 계산하고 있어요',
                style: TossText.sub),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(child: Text(title, style: TossText.title3)),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  // ① 받은 카드 안에서 내 순위
  Widget _buildOfferedRankCard(ResultAnalysis a, OfferedAnalysis o) {
    final p      = o.playerResult;
    final isBest = p.rank == 1;
    final gap    = o.bestCombo.finalReturnRate - p.finalReturnRate;

    return TossSection(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            '받은 카드 안에서 내 순위',
            trailing: const TossBadge(
                label: '라운드마다 3장 기준',
                bg: TossColors.grey100,
                fg: TossColors.grey600),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${p.rank}위',
                  style: TossText.display.copyWith(color: TossColors.blue500)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('/ ${o.totalCombinations}개 조합',
                    style: TossText.caption),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (isBest)
            const Text('받은 카드로 만들 수 있는 최고의 조합이었어요 🎉',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: TossColors.blue500))
          else
            Text(
              // (#125) 표시하면 0.0%p인 차이는 "0.0%p 낮았어요" 대신 거의 같다고 말한다
              gap < kMinVisibleGap
                  ? '같은 카드를 받았을 때 가장 좋은 조합과 거의 같은 결과였어요'
                  : '같은 카드를 받았을 때 가장 좋은 조합보다 '
                      '${gap.toStringAsFixed(1)}%p 낮았어요',
              style: TossText.sub.copyWith(color: TossColors.grey700),
            ),
          const SizedBox(height: 12),
          Text(
            '${a.cardPoolSize}장 전체로 보면 '
            '${_formatNumber(a.totalCombinations.toDouble())}개 조합 중 '
            '${_formatNumber(a.playerResult.rank.toDouble())}위 '
            '(${_formatTopPercent(a.playerResult.topPercent)})',
            style: TossText.small,
          ),
        ],
      ),
    );
  }

  // ① (대체) 후보 안 분석이 없을 때: 전체 조합 기준 순위
  Widget _buildRankCard(ResultAnalysis a) {
    final p      = a.playerResult;
    final isBest = p.rank == 1;

    return TossSection(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            '내 조합 순위',
            trailing: TossBadge(
                label: '${a.cardPoolSize}장 전체 조합 기준',
                bg: TossColors.grey100,
                fg: TossColors.grey600),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${_formatNumber(p.rank.toDouble())}위',
                  style: TossText.display.copyWith(color: TossColors.blue500)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  '/ ${_formatNumber(a.totalCombinations.toDouble())}개 조합',
                  style: TossText.caption,
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: TossBadge(label: _formatTopPercent(p.topPercent)),
              ),
            ],
          ),
          if (isBest) ...[
            const SizedBox(height: 8),
            const Text('가능한 조합 중 가장 좋은 선택이었어요 🎉',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: TossColors.blue500)),
          ],
        ],
      ),
    );
  }

  // ② 라운드별로 돌아보기
  //  "이 라운드 최선" = 다른 라운드 선택은 그대로 두고, 이 라운드 카드만 바꿨을 때
  //  AI 예측이 맞았는지도 이 기준으로 판단 (받은 3장 안에서 비교하므로 '후보 밖'이 없음)
  Widget _buildRoundReviewCard(OfferedAnalysis? o) {
    final mine = _analysis!.playerResult;
    int bestRounds = 0;
    int tieRounds = 0;   // (#125) 어떤 카드를 골라도 같았던 라운드는 "최선"으로 세지 않는다
    if (o != null) {
      bestRounds = _selectRounds
          .where((r) => o.roundAt(r) != null && o.roundAt(r)!.better == null && !o.roundAt(r)!.noDifference)
          .length;
      tieRounds = _selectRounds
          .where((r) => o.roundAt(r) != null && o.roundAt(r)!.noDifference)
          .length;
    }

    return TossSection(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            '라운드별로 돌아보기',
            trailing: o == null
                ? null
                : Text(
                    tieRounds > 0
                        ? '4번 중 $bestRounds번 최선 · $tieRounds번 차이 없음'
                        : '4번 중 $bestRounds번 최선',
                    style: TossText.caption),
          ),
          for (int i = 0; i < _selectRounds.length; i++) ...[
            if (i > 0) Container(height: 1, color: TossColors.grey100),
            Reveal(
              order: 2 + i,
              child: _buildRoundBlock(_selectRounds[i],
                  mine.cardAt(_selectRounds[i]), o?.roundAt(_selectRounds[i])),
            ),
          ],
          if (o != null) ...[
            const SizedBox(height: 4),
            const Text(
              '다른 라운드 선택은 그대로 두고, 그 라운드 카드만 바꿨을 때 결과예요.',
              style: TossText.small,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildRoundBlock(
      int round, AnalysisCard? myCard, RoundAlternatives? ra) {
    final aiId    = widget.aiPicks[round];
    final better  = ra?.better;
    final bestId  = ra == null ? null : (better?.cardId ?? ra.playerCardId);
    final tie     = ra?.noDifference ?? false;
    final aiHit   = aiId != null && bestId != null && aiId == bestId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$round라운드',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: TossColors.grey500)),
              const Spacer(),
              if (ra != null)
                tie
                    ? const TossBadge(
                        label: '차이 없음',
                        bg: TossColors.grey100,
                        fg: TossColors.grey600)
                    : better == null
                    ? const TossBadge(
                        label: '✓ 최선',
                        bg: TossColors.green50,
                        fg: Color(0xFF02874F))
                    : TossBadge(
                        label: '+${better.diffReturnRate.toStringAsFixed(1)}%p 놓침',
                        bg: TossColors.grey100,
                        fg: TossColors.grey700),
            ],
          ),
          const SizedBox(height: 8),
          _labeledChip('내 선택', myCard, highlight: better == null && ra != null && !tie),
          if (aiId != null) ...[
            const SizedBox(height: 6),
            _labeledChip(
              'AI 예측',
              AnalysisCard(
                  round: round,
                  cardId: aiId,
                  cardName: CardInfo.fromId(aiId)?.name ?? ''),
              highlight: aiHit && !tie,
              trailing: ra == null
                  ? null
                  : Text(tie ? '차이 없음' : (aiHit ? '맞음' : '빗나감'),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: aiHit && !tie
                              ? TossColors.green500
                              : TossColors.grey500)),
            ),
          ],
          if (better != null) ...[
            const SizedBox(height: 6),
            _labeledChip(
              '더 좋았던 카드',
              AnalysisCard(
                  round: round,
                  cardId: better.cardId,
                  cardName: better.cardName),
              highlight: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _labeledChip(String label, AnalysisCard? card,
      {bool highlight = false, Widget? trailing}) {
    return Row(
      children: [
        SizedBox(width: 84, child: Text(label, style: TossText.caption)),
        Expanded(child: _buildCardChip(card, highlight: highlight)),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          SizedBox(width: 44, child: trailing),
        ],
      ],
    );
  }

  // =============================================
  // (#125) AI 코치 한마디
  //  요약·잘한 점·아쉬운 점·위기 대응은 계산 결과로 만든 문장, "다음엔" 한 줄만 AI가 쓴다
  // =============================================
  Widget _buildCoachCard() {
    final coach = _coach;
    if (coach == null) {
      return const TossSection(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text('AI 코치가 결과를 살펴보고 있어요', style: TossText.sub),
            ),
          ],
        ),
      );
    }

    String emojiOf(String head) => switch (head) {
          '요약'      => '📌',
          '잘한 점'   => '👍',
          '아쉬운 점' => '🤔',
          '위기 대응' => '🚨',
          '다음엔'    => '💡',
          _          => '💬',
        };

    return TossSection(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('AI 코치 한마디'),
          for (final (i, line) in coach.lines.indexed)
            Reveal(
              order: 2 + i,
              child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EmojiTile(
                    emoji: emojiOf(line.head),
                    size: 36,
                    bg: line.head == '다음엔'
                        ? TossColors.blue50
                        : TossColors.grey100,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (line.head.isNotEmpty)
                          Text(line.head,
                              style: TossText.small.copyWith(
                                  color: line.head == '다음엔'
                                      ? TossColors.blue600
                                      : TossColors.grey500)),
                        Text(line.body,
                            style: TextStyle(
                                fontSize: 15,
                                height: 1.45,
                                fontWeight: line.head == '다음엔'
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: TossColors.grey900)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ),
          const SizedBox(height: 8),
          Text(
            coach.byAi
                ? '숫자가 들어간 줄은 계산 결과로 만들고, "다음엔" 한 줄만 AI가 썼어요.'
                : '계산 결과와 미리 정해 둔 문장으로 만들었어요.',
            style: TossText.small,
          ),
        ],
      ),
    );
  }

  // =============================================
  // (#125) 카드별 성적표 — "이 카드를 고르지 않았다면"과 비교한 효과
  // =============================================
  Widget _buildCardReportCard(List<CardReportItem> report) {
    return TossSection(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('카드별 성적표'),
          for (int i = 0; i < report.length; i++) ...[
            if (i > 0) Container(height: 1, color: TossColors.grey100),
            Reveal(order: 2 + i, child: _buildCardReportRow(report[i])),
          ],
          const SizedBox(height: 6),
          const Text(
            '이 카드만 고르지 않았을 때와 최종 수익률을 비교한 값이에요. '
            '카드끼리 현금을 나눠 쓰기 때문에 네 값을 더해도 전체 수익률과 같지는 않아요.',
            style: TossText.small,
          ),
        ],
      ),
    );
  }

  Widget _buildCardReportRow(CardReportItem c) {
    final name = c.cardName.isNotEmpty
        ? c.cardName
        : (CardInfo.fromId(c.cardId)?.name ?? '카드 ${c.cardId}');
    final verb = c.isSell ? '매도' : '매수';
    final parts = <String>[
      if (c.cardType == 'BUY_ONCE')
        c.triggerCount > 0 ? '고른 날 바로 매수' : '매수하지 못함'
      else
        '발동 ${c.triggerCount}회',
      if (c.tradeAmount > 0) '${formatShortWon(c.tradeAmount)} $verb',
      if (c.mainSkipReason != null)
        '${SkippedCard.label(c.mainSkipReason!)} ${c.skipTotal}번',
    ];
    final flat = c.effectReturnRate.abs() < 0.05;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          EmojiTile(emoji: _cardEmoji(c.cardId), size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TossText.body2),
                    ),
                    const SizedBox(width: 6),
                    Text('${c.round}R', style: TossText.small),
                  ],
                ),
                const SizedBox(height: 1),
                Text(parts.join(' · '), style: TossText.caption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            flat ? '영향 없음' : formatSigned(c.effectReturnRate, unit: '%p'),
            style: TossText.number.copyWith(
                fontSize: flat ? 13 : 15,
                color: flat
                    ? TossColors.grey500
                    : TossColors.rate(c.effectReturnRate)),
          ),
        ],
      ),
    );
  }

  // =============================================
  // (#125) 위기 대응 돌아보기 — 그때 다른 대응을 했다면 (나머지 선택은 그대로)
  // =============================================
  Widget _buildDecisionReviewCard(DecisionReview review) {
    final effect = review.effectReturnRate;
    final n = review.rounds.length;
    final String summary;
    if (review.allHold) {
      summary = '속보 $n번 모두 전략 카드를 믿고 버텼어요.';
    } else if (effect.abs() < 0.05) {
      summary = '$n번의 대응은 결과를 거의 바꾸지 않았어요.';
    } else {
      summary = '$n번의 대응으로 최종 수익률이 '
          '${effect.abs().toStringAsFixed(1)}%p ${effect > 0 ? '올랐어요' : '내려갔어요'}. '
          '(전부 버텼다면 ${formatSigned(review.allHoldFinalReturnRate)})';
    }

    return TossSection(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            '위기 대응 돌아보기',
            trailing: (review.allHold || effect.abs() < 0.05)
                ? null
                : Text(formatSigned(effect, unit: '%p'),
                    style:
                        TossText.number.copyWith(color: TossColors.rate(effect))),
          ),
          Text(summary,
              style: TossText.sub.copyWith(
                  fontSize: 15, color: TossColors.grey700)),
          const SizedBox(height: 6),
          for (int i = 0; i < review.rounds.length; i++) ...[
            Container(height: 1, color: TossColors.grey100),
            Reveal(order: 2 + i, child: _buildDecisionBlock(review.rounds[i])),
          ],
          const Text(
            '다른 선택은 그대로 두고, 그 속보에서의 대응만 바꿨을 때 결과예요.',
            style: TossText.small,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildDecisionBlock(DecisionRoundReview r) {
    final better = r.better;
    final st = NewsStyle.of(r.level);

    Widget choiceChip(String label, String choice,
        {bool highlight = false, String? extra}) {
      return Row(
        children: [
          SizedBox(width: 84, child: Text(label, style: TossText.caption)),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: highlight ? TossColors.blue50 : TossColors.grey50,
                borderRadius: BorderRadius.circular(TossRadius.sm + 2),
              ),
              child: Row(
                children: [
                  Text(DecisionChoice.emoji(choice),
                      style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      DecisionChoice.label(choice),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              highlight ? FontWeight.w700 : FontWeight.w500,
                          color: highlight
                              ? TossColors.blue600
                              : TossColors.grey800),
                    ),
                  ),
                  if (extra != null) Text(extra, style: TossText.small),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${r.round}라운드 · ${r.date}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: TossColors.grey500)),
              ),
              const SizedBox(width: 8),
              r.noDifference
                  ? const TossBadge(
                      label: '차이 없음',
                      bg: TossColors.grey100,
                      fg: TossColors.grey600)
                  : better == null
                  ? const TossBadge(
                      label: '✓ 가장 좋은 대응',
                      bg: TossColors.green50,
                      fg: Color(0xFF02874F))
                  : TossBadge(
                      label:
                          '+${better.diffReturnRate.toStringAsFixed(1)}%p 놓침',
                      bg: TossColors.grey100,
                      fg: TossColors.grey700),
            ],
          ),
          if (r.headline.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 1),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: st.softBg,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(st.label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: st.softFg)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(r.headline,
                      style: const TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: TossColors.grey900)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          choiceChip('내 대응', r.choice,
              highlight: better == null && !r.noDifference,
              extra: r.tradeAmount > 0 ? formatShortWon(r.tradeAmount) : null),
          if (better != null) ...[
            const SizedBox(height: 6),
            choiceChip('더 좋았던 대응', better.choice, highlight: true),
          ],
        ],
      ),
    );
  }

  // =============================================
  // (#125) 그 후 이야기 — 게임이 끝난 뒤 실제 시장
  //  리먼처럼 반등 전에 끝나는 구간은 "안 사는 것이 정답"으로만 남는다.
  //  게임이 끝난 뒤 시장이 어떻게 됐는지, 내 자산을 그대로 뒀다면 어땠는지를 함께 보여준다.
  // =============================================
  Widget _buildEpilogueCard(Epilogue ep) {
    // (장면 개편) 시간이 흐르는 이야기처럼: 게임 마지막 날 → 6개월 뒤 → 1년 뒤
    //   '게임 1위 조합을 그대로 뒀다면'은 게임 중 고를 수 없던 조합이라 뺐다
    Widget stat(String label, double value, {bool mine = false}) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: mine ? TossColors.blue50 : TossColors.white,
            borderRadius: BorderRadius.circular(TossRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TossText.small.copyWith(
                      color: mine ? TossColors.blue600 : TossColors.grey500)),
              const SizedBox(height: 2),
              Text(formatSigned(value),
                  style: TossText.number.copyWith(
                      fontSize: 20, color: TossColors.rate(value))),
            ],
          ),
        ),
      );
    }

    Widget step(String emoji, String title, String date, Widget child,
        {bool lastStep = false}) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 타임라인 점과 선
            SizedBox(
              width: 40,
              child: Column(
                children: [
                  EmojiTile(emoji: emoji, size: 40),
                  if (!lastStep)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: TossColors.grey200,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: lastStep ? 0 : 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title, style: TossText.body2),
                        const SizedBox(width: 6),
                        Text(date, style: TossText.small),
                      ],
                    ),
                    const SizedBox(height: 8),
                    child,
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return TossSection(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⏳', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 10),
          _sectionTitle('그 후 이야기'),
          Text('게임이 끝난 뒤, 실제 시장은 어떻게 됐을까요?',
              style: TossText.sub.copyWith(
                  fontSize: 15, color: TossColors.grey700)),
          const SizedBox(height: 18),
          step(
            '🏁',
            '게임 마지막 날',
            ep.endDate,
            Row(children: [
              stat('내 수익률', _finalReturnRate, mine: true),
            ]),
          ),
          for (int i = 0; i < ep.points.length; i++)
            FadeInUp(
              delay: Duration(milliseconds: 200 + 200 * i),
              child: step(
                i == ep.points.length - 1 ? '📅' : '🗓️',
                ep.points[i].label,
                ep.points[i].date,
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: TossColors.grey50,
                    borderRadius: BorderRadius.circular(TossRadius.lg),
                  ),
                  child: Row(
                    children: [
                      stat('S&P500 (마지막 날 대비)', ep.points[i].spxChangeRate),
                      const SizedBox(width: 6),
                      stat('내 자산 그대로 (원금 대비)',
                          ep.points[i].playerReturnRate,
                          mine: true),
                    ],
                  ),
                ),
                lastStep: i == ep.points.length - 1,
              ),
            ),
          const SizedBox(height: 18),
          const InfoBox(
            child: Text(
              '게임이 끝났을 때 가진 자산을 더 사고팔지 않고 그대로 들고 있었다고 가정했어요. '
              '게임 중에는 알 수 없던 뒷이야기예요.',
              style: TossText.caption,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardChip(AnalysisCard? card, {bool highlight = false}) {
    if (card == null) {
      return const Text('-', style: TossText.caption);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlight ? TossColors.blue50 : TossColors.grey50,
        borderRadius: BorderRadius.circular(TossRadius.sm + 2),
      ),
      child: Row(
        children: [
          Text(_cardEmoji(card.cardId), style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _cardName(card),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                  color: highlight ? TossColors.blue600 : TossColors.grey800),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 막대 차트 (0% 기준선 위아래로 뻗는 세로 막대) ──
class _Bar {
  final String label;
  final double value; // 수익률(%)
  final bool mine;
  const _Bar(this.label, this.value, this.mine);
}

class _BarChart extends StatelessWidget {
  final List<_Bar> bars;
  final bool revealed;
  const _BarChart({required this.bars, required this.revealed});

  static const double _area = 120; // 막대가 쓸 수 있는 전체 높이

  @override
  Widget build(BuildContext context) {
    double maxPos = 0, maxNeg = 0;
    for (final b in bars) {
      if (b.value > maxPos) maxPos = b.value;
      if (-b.value > maxNeg) maxNeg = -b.value;
    }
    final total = (maxPos + maxNeg) <= 0 ? 1.0 : maxPos + maxNeg;
    final posH  = _area * maxPos / total; // 기준선 위쪽 높이
    final negH  = _area * maxNeg / total; // 기준선 아래쪽 높이

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in bars)
          Expanded(child: _column(b, posH, negH, total)),
      ],
    );
  }

  Widget _column(_Bar b, double posH, double negH, double total) {
    final double h = revealed
        ? (_area * b.value.abs() / total).clamp(3.0, _area).toDouble()
        : 3.0;
    final up    = b.value >= 0;
    final color = b.mine ? TossColors.blue500 : TossColors.grey300;
    final valueText = Text(
      '${b.value >= 0 ? '+' : ''}${b.value.toStringAsFixed(1)}%',
      style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: b.mine ? TossColors.grey900 : TossColors.grey600,
          fontFeatures: const [FontFeature.tabularFigures()]),
    );
    final bar = AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      width: 56,
      height: h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(up ? 8 : 2),
          bottom: Radius.circular(up ? 2 : 8),
        ),
      ),
    );

    return Column(
      children: [
        // 기준선 위 (수익)
        SizedBox(
          height: posH + 24,
          child: up
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [valueText, const SizedBox(height: 4), bar],
                )
              : null,
        ),
        Container(height: 1, color: TossColors.grey200),
        // 기준선 아래 (손실)
        SizedBox(
          height: negH + 24,
          child: up
              ? null
              : Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [bar, const SizedBox(height: 4), valueText],
                ),
        ),
        const SizedBox(height: 6),
        Text(b.label,
            textAlign: TextAlign.center,
            style: TossText.small.copyWith(
                color: b.mine ? TossColors.grey900 : TossColors.grey500,
                fontWeight: b.mine ? FontWeight.w700 : FontWeight.w500)),
      ],
    );
  }
}
