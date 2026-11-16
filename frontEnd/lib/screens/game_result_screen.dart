import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/game_session.dart';
import '../models/card_info.dart';
import '../models/result_analysis.dart';
import '../services/game_service.dart';
import '../theme/toss_theme.dart';
import '../widgets/toss/toss_widgets.dart';

class GameResultScreen extends StatefulWidget {
  final GameSession session;
  // 게임 중 받은 AI 예측 1순위 (라운드 → 카드 ID). 예측을 안 받은 라운드는 없음
  final Map<int, int> aiPicks;
  // 그 라운드에 받은 후보 카드 3장 (1위 조합 카드가 후보에 있었는지 확인용)
  final Map<int, List<int>> aiCandidates;

  const GameResultScreen({
    super.key,
    required this.session,
    this.aiPicks = const {},
    this.aiCandidates = const {},
  });

  @override
  State<GameResultScreen> createState() => _GameResultScreenState();
}

class _GameResultScreenState extends State<GameResultScreen> {
  final GameService _gameService = GameService();

  // 숫자 공개 연출: 처음엔 시작 자산·0%를 보여주고, 잠시 뒤 최종 값으로 굴러감
  bool _revealed = false;
  Timer? _revealTimer;

  // 사후 분석 (백테스팅, API v6.1)
  ResultAnalysis? _analysis;
  bool _analysisLoading = true;

  static const List<int> _selectRounds = [1, 25, 50, 75];

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
    });
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  String _formatNumber(double value) => formatWon(value);

  // 상위 % 표기 (0.1 미만이면 "상위 0.1% 이내")
  String _formatTopPercent(double p) =>
      p < 0.1 ? '상위 0.1% 이내' : '상위 ${p.toStringAsFixed(1)}%';

  String _cardEmoji(int cardId) => CardInfo.fromId(cardId)?.emoji ?? '🃏';

  String _cardName(AnalysisCard c) => c.cardName.isNotEmpty
      ? c.cardName
      : (CardInfo.fromId(c.cardId)?.name ?? '카드 ${c.cardId}');

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: TossColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FadeInUp(child: _buildHero()),
                    const SizedBox(height: 8),
                    FadeInUp(
                      delay: const Duration(milliseconds: 120),
                      child: _buildAssetRows(),
                    ),
                    const SizedBox(height: 8),
                    _buildAnalysisSection(),
                  ],
                ),
              ),
            ),

            // 처음으로 (하단 고정)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottomInset),
              child: TossButton(
                label: '처음으로 돌아가기',
                onTap: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =============================================
  // 결과 요약: 한 줄 결론 + 최종 자산 (숫자 굴러감)
  // =============================================
  Widget _buildHero() {
    final profit  = _finalReturnRate >= 0;
    final initial = widget.session.initialAsset.toDouble();
    final asset   = _revealed ? _finalAsset : initial;
    final rate    = _revealed ? _finalReturnRate : 0.0;
    final diff    = asset - initial;

    return TossSection(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.session.scenarioTitle} · ${widget.session.totalRounds}라운드 완료',
            style: TossText.sub,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Flexible(
                child: Text(profit ? '위기에서 살아남았어요' : '이번엔 손실을 봤어요',
                    style: TossText.title1),
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
          RollingText(
            '${diff >= 0 ? '+' : '-'}${_formatNumber(diff.abs())}원 '
            '(${rate.abs().toStringAsFixed(2)}%)',
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
        ],
      ),
    );
  }

  Widget _buildAssetRows() {
    return TossSection(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        children: [
          _kvRow('시작 자산',
              '${_formatNumber(widget.session.initialAsset.toDouble())}원'),
          _kvRow('최종 자산', '${_formatNumber(_finalAsset)}원'),
          _kvRow('최종 수익률', formatRate(_finalReturnRate),
              valueColor: TossColors.rate(_finalReturnRate)),
        ],
      ),
    );
  }

  Widget _kvRow(String k, String v, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(k, style: TossText.sub.copyWith(fontSize: 15)),
          const Spacer(),
          Text(v,
              style: TossText.number.copyWith(
                  color: valueColor ?? TossColors.grey900)),
        ],
      ),
    );
  }

  // =============================================
  // 사후 분석 섹션 (백테스팅, API v6.1)
  // =============================================
  Widget _buildAnalysisSection() {
    if (_analysisLoading) return _buildAnalysisLoading();

    // 실패·데이터 없음 → 섹션 자체를 표시하지 않음 (명세서 4장)
    final a = _analysis;
    if (a == null) return const SizedBox.shrink();

    final sections = <Widget>[
      _buildRankCard(a),
      if (a.best != null) _buildCompareCard(a, a.best!),
      if (widget.aiPicks.isNotEmpty) _buildAiPickCard(a),
      if (a.topCombos.isNotEmpty) _buildTopCombosCard(a),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < sections.length; i++) ...[
          FadeInUp(
            delay: Duration(milliseconds: 80 * i),
            child: sections[i],
          ),
          const SizedBox(height: 8),
        ],
        // 계산 근거 (명세서 6장)
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Text(
            '게임 종료 후 100라운드 시장 데이터를 모두 사용해 계산한 결과로, '
            '게임 중에는 알 수 없는 정보예요. 라운드마다 카드가 3장씩만 '
            '제시되므로, 최적 조합에는 이번 게임에서 보지 못한 카드가 포함될 수 있어요.',
            style: TossText.small,
          ),
        ),
      ],
    );
  }

  // 로딩 (서버 계산 약 3.7초)
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

  // ① 내 조합 순위
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

  // ② 내 조합 vs 1위 조합 (라운드별 비교)
  Widget _buildCompareCard(ResultAnalysis a, ComboResult best) {
    final p = a.playerResult;
    final matchCount = _selectRounds.where((r) {
      final mine = p.cardAt(r);
      final top  = best.cardAt(r);
      return mine != null && top != null && mine.cardId == top.cardId;
    }).length;
    final diff = best.finalReturnRate - p.finalReturnRate;

    return TossSection(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            '1위 조합과 비교해 봤어요',
            trailing: Text('4장 중 $matchCount장 같음', style: TossText.caption),
          ),
          _tableHeader(const ['내 선택', '1위 조합']),
          ..._selectRounds.map((r) {
            final mine = p.cardAt(r);
            final top  = best.cardAt(r);
            final same = mine != null && top != null && mine.cardId == top.cardId;
            return _tableRow(
              r,
              [
                _buildCardChip(mine, highlight: same),
                _buildCardChip(top, highlight: same),
              ],
            );
          }),
          const SizedBox(height: 12),
          Container(height: 1, color: TossColors.grey100),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildRateColumn('내 수익률', p.finalReturnRate)),
              Expanded(
                  child: _buildRateColumn('1위 수익률', best.finalReturnRate)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('차이', style: TossText.small),
                  const SizedBox(height: 2),
                  Text('${diff.toStringAsFixed(2)}%p',
                      style: TossText.number),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ③ AI 예측 vs 내 선택 (게임 중 AI 예측을 받은 25·50라운드만)
  //  "1위 조합과 같은 카드인지"로 예측이 맞았는지 확인하게 함 (중간보고서 4.4 계획)
  Widget _buildAiPickCard(ResultAnalysis a) {
    final best   = a.best;
    final rounds = widget.aiPicks.keys.toList()..sort();

    return TossSection(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('AI 예측은 맞았을까요?'),
          _tableHeader(const ['AI 예측 1위', '내 선택'], trailing: '1위 조합과'),
          ...rounds.map((r) {
            final aiId   = widget.aiPicks[r]!;
            final mine   = a.playerResult.cardAt(r);
            final top    = best?.cardAt(r);
            final aiHit  = top != null && top.cardId == aiId;
            // 1위 조합 카드가 그때 후보 3장에 없었으면 애초에 맞힐 수 없음
            final inPool = top != null &&
                (widget.aiCandidates[r]?.contains(top.cardId) ?? true);
            final verdict = top == null
                ? '-'
                : aiHit ? '같음' : (inPool ? '다름' : '후보 밖');
            final aiCard = AnalysisCard(
              round: r,
              cardId: aiId,
              cardName: CardInfo.fromId(aiId)?.name ?? '',
            );
            return _tableRow(
              r,
              [
                _buildCardChip(aiCard, highlight: aiHit),
                _buildCardChip(mine),
              ],
              trailing: Text(
                verdict,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: aiHit ? TossColors.green500 : TossColors.grey500),
              ),
            );
          }),
          const SizedBox(height: 10),
          const Text(
            'AI 예측은 그때까지의 시장만 보고 한 것이고, 1위 조합은 게임이 끝난 뒤 '
            '전체 시장으로 계산한 결과예요. 미래를 모르면 예측이 틀릴 수 있어요. '
            '"후보 밖"은 1위 조합의 카드가 그 라운드 후보 3장에 없었다는 뜻이에요.',
            style: TossText.small,
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(List<String> cols, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const SizedBox(width: 40, child: Text('라운드', style: TossText.small)),
          for (int i = 0; i < cols.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: Text(cols[i], style: TossText.small)),
          ],
          if (trailing != null)
            SizedBox(
                width: 60,
                child: Text(trailing,
                    textAlign: TextAlign.right, style: TossText.small)),
        ],
      ),
    );
  }

  Widget _tableRow(int round, List<Widget> cells, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text('${round}R',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: TossColors.grey500)),
          ),
          for (int i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: cells[i]),
          ],
          if (trailing != null) SizedBox(width: 60, child: trailing),
        ],
      ),
    );
  }

  Widget _buildRateColumn(String label, double rate) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TossText.small),
        const SizedBox(height: 2),
        Text(formatRate(rate),
            style: TossText.number.copyWith(color: TossColors.rate(rate))),
      ],
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

  // ④ 이 시나리오의 최적 조합 Top N
  Widget _buildTopCombosCard(ResultAnalysis a) {
    // 서버가 최종 자산이 같은 조합을 하나로 묶어 보내므로(tiedCount, PR #78)
    // 순위가 1위 → 7위처럼 건너뛸 수 있음 → 그때만 이유를 안내
    final rankSkipped = a.hasSkippedRank;

    return TossSection(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('이 시나리오 최고의 조합 ${a.topCombos.length}개'),
          ...a.topCombos.map((c) => _buildComboRow(c)),
          if (rankSkipped) ...[
            const SizedBox(height: 4),
            const Text(
              '최종 자산이 같은 조합은 하나로 묶어 보여줘요. 그래서 순위가 '
              '건너뛸 수 있어요. (한 번도 발동하지 않은 카드만 다르면 결과가 같아요)',
              style: TossText.small,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildComboRow(ComboResult c) {
    final first = c.rank == 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TossBadge(
                label: '${c.rank}위',
                bg: first ? TossColors.blue500 : TossColors.grey100,
                fg: first ? TossColors.white : TossColors.grey700,
              ),
              const Spacer(),
              Text(formatRate(c.finalReturnRate),
                  style: TossText.number
                      .copyWith(color: TossColors.rate(c.finalReturnRate))),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: c.cards.map((card) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: TossColors.grey50,
                  borderRadius: BorderRadius.circular(TossRadius.sm),
                ),
                child: Text(
                  '${card.round}R ${_cardEmoji(card.cardId)} ${_cardName(card)}',
                  style: const TextStyle(
                      fontSize: 13, color: TossColors.grey700),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
