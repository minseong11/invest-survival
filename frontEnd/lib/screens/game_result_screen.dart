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
  // 그 라운드에 받은 후보 카드 3장 (지금은 서버 offeredAnalysis를 쓰므로 표시용으로 안 씀)
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
  // 사후 분석 섹션 (12주차 최종안)
  //  ① 받은 카드 안에서 내 순위  (공정 비교: 라운드마다 실제로 받은 3장 기준)
  //  ② 라운드별로 돌아보기      (내 선택 · AI 예측 · 이 라운드 더 좋았던 카드)
  //  ③ 참고: 전체 1위 전략      (11장 전체 기준, 게임 중엔 못 골랐을 수도 있음)
  // =============================================
  Widget _buildAnalysisSection() {
    if (_analysisLoading) return _buildAnalysisLoading();

    // 실패·데이터 없음 → 섹션 자체를 표시하지 않음 (명세서 4장)
    final a = _analysis;
    if (a == null) return const SizedBox.shrink();
    final o = a.offered; // 예전 세션 등으로 없으면 null → 전체 기준으로 대체

    final sections = <Widget>[
      o != null ? _buildOfferedRankCard(a, o) : _buildRankCard(a),
      _buildRoundReviewCard(o),
      if (a.best != null) _buildReferenceCard(a, a.best!),
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
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Text(
            '게임이 끝난 뒤 100라운드 시장 데이터를 모두 써서 계산한 결과예요. '
            '게임 중에는 알 수 없는 정보예요.',
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

  // ① 받은 카드 안에서 내 순위
  Widget _buildOfferedRankCard(ResultAnalysis a, OfferedAnalysis o) {
    final p      = o.playerResult;
    final best   = o.bestCombo;
    final isBest = p.rank == 1;
    final gap    = best.finalReturnRate - p.finalReturnRate;

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
              '같은 카드를 받았을 때 가장 좋은 조합보다 '
              '${gap.toStringAsFixed(1)}%p 낮았어요',
              style: TossText.sub.copyWith(color: TossColors.grey700),
            ),
          const SizedBox(height: 14),
          Container(height: 1, color: TossColors.grey100),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _buildRateColumn('내 수익률', p.finalReturnRate)),
              Expanded(
                  child: _buildRateColumn('받은 카드 중 최선', best.finalReturnRate)),
            ],
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
    if (o != null) {
      bestRounds = _selectRounds
          .where((r) => o.roundAt(r) != null && o.roundAt(r)!.better == null)
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
                : Text('4번 중 $bestRounds번 최선', style: TossText.caption),
          ),
          for (int i = 0; i < _selectRounds.length; i++) ...[
            if (i > 0) Container(height: 1, color: TossColors.grey100),
            _buildRoundBlock(_selectRounds[i], mine.cardAt(_selectRounds[i]),
                o?.roundAt(_selectRounds[i])),
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
                better == null
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
          _labeledChip('내 선택', myCard, highlight: better == null && ra != null),
          if (aiId != null) ...[
            const SizedBox(height: 6),
            _labeledChip(
              'AI 예측',
              AnalysisCard(
                  round: round,
                  cardId: aiId,
                  cardName: CardInfo.fromId(aiId)?.name ?? ''),
              highlight: aiHit,
              trailing: ra == null
                  ? null
                  : Text(aiHit ? '맞음' : '빗나감',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: aiHit
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

  // ③ 참고: 이 시장에서 가장 잘 통한 전략 (전체 카드 기준 1위)
  Widget _buildReferenceCard(ResultAnalysis a, ComboResult best) {
    return TossSection(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            '참고: 이 시장에서 가장 잘 통한 전략',
            trailing: Text(formatRate(best.finalReturnRate),
                style: TossText.number
                    .copyWith(color: TossColors.rate(best.finalReturnRate))),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: best.cards.map((card) {
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
          const SizedBox(height: 12),
          InfoBox(
            child: Text(
              '${a.cardPoolSize}장 전체 기준이에요. 라운드마다 3장씩만 나오기 때문에, '
              '이 조합은 게임 중에 고를 수 없었을 수도 있어요.',
              style: TossText.caption,
            ),
          ),
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
}
