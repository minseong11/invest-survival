"""
result_coach.py — 사후 분석 "AI 코치 한마디" (#125)

게임 중 AI 설명(/ai/v2/feedback)과 같은 원칙으로 만든다.
  - 숫자가 들어가는 사실(요약·잘한 점·아쉬운 점·위기 대응)은 프로그램이 사후 분석 결과(run_backtest)로 직접 쓴다
    → LLM이 숫자를 틀릴 수 없음
  - LLM은 "다음엔" 한 문장만 쓴다. 숫자·단정 표현·없는 카드·틀린 카드 조건이 있으면
    규칙 기반 문장(rule_based_tip)으로 바꾼다

응답은 줄 머리말로 나뉜 글이고, 앱은 머리말로 나눠서 보여준다.
  요약: …   잘한 점: …   아쉬운 점: …   위기 대응: …   다음엔: …
"""
import re
from typing import List

from display_format import fixed
from verify_feedback import verify_feedback, CARD_FACTS

DECISION_LABELS = {'HOLD': '버틴다', 'SELL_HALF': '절반 판다', 'BUY_MORE': '더 산다'}

# 이 값(%p)보다 작은 효과는 "차이 없음"으로 본다 (반올림 수준의 차이를 장점·단점으로 말하지 않기 위해)
MIN_EFFECT = 0.1

# LLM 문장에 있으면 안 되는 단정 표현 (투자 결과를 보장하는 것처럼 읽힘)
ABSOLUTE_WORDS = ('반드시', '무조건', '확실', '보장', '절대')

MAX_TIP_LENGTH = 120


# 화면에 같은 값이 앱의 숫자(수익률 막대, 카드별 성적표 등)와 나란히 나오므로 앱과 같은 반올림을 쓴다
def _pct(v: float) -> str:
    return f'{fixed(abs(v))}%'


def _pp(v: float) -> str:
    return f'{fixed(abs(v))}%p'


def _summary(analysis: dict) -> str:
    mine = analysis['playerResult']['finalReturnRate']
    market = analysis['risk']['marketReturnRate']

    def index_move(v):
        if abs(v) < 0.05:
            return '거의 그대로였'
        return f'{_pct(v)} 올랐' if v > 0 else f'{_pct(v)} 떨어졌'

    def asset_move(v):
        if abs(v) < 0.05:
            return '거의 그대로였'
        return f'{_pct(v)} 늘었' if v > 0 else f'{_pct(v)} 줄었'

    return f'같은 기간 S&P500은 {index_move(market)}고, 내 자산은 {asset_move(mine)}어요.'


def best_and_worst(analysis: dict):
    """(가장 도움이 된 카드, 가장 아쉬운 카드) — 효과가 MIN_EFFECT보다 작으면 None"""
    report = analysis.get('cardReport') or []
    if not report:
        return None, None
    best = max(report, key=lambda c: c['effectReturnRate'])
    worst = min(report, key=lambda c: c['effectReturnRate'])
    return (best if best['effectReturnRate'] >= MIN_EFFECT else None,
            worst if worst['effectReturnRate'] <= -MIN_EFFECT else None)


def fact_lines(analysis: dict) -> List[str]:
    """프로그램이 쓰는 줄 (머리말: 내용). 숫자는 모두 사후 분석 결과에서 온다."""
    lines = [f'요약: {_summary(analysis)}']

    best, worst = best_and_worst(analysis)
    if best:
        lines.append(f'잘한 점: {best["cardName"]} — 이 카드가 없었다면 수익률이 '
                     f'{_pp(best["effectReturnRate"])} 낮았을 거예요.')
    if worst:
        lines.append(f'아쉬운 점: {worst["cardName"]} — 이 카드가 없었다면 수익률이 '
                     f'{_pp(worst["effectReturnRate"])} 높았을 거예요.')
    if not best and not worst:
        lines.append('잘한 점: 이번 판은 카드를 바꿔도 결과가 거의 같았어요.')

    review = analysis.get('decisionReview')
    if review and review.get('rounds'):
        n = len(review['rounds'])
        effect = review['effectReturnRate']
        if all(r['choice'] == 'HOLD' for r in review['rounds']):
            lines.append(f'위기 대응: 속보 {n}번 모두 전략 카드를 믿고 버텼어요.')
        elif abs(effect) < 0.05:
            lines.append(f'위기 대응: {n}번의 대응은 결과를 거의 바꾸지 않았어요.')
        elif effect > 0:
            lines.append(f'위기 대응: {n}번의 대응으로 수익률이 {_pp(effect)} 올랐어요. (전부 버텼을 때와 비교)')
        else:
            lines.append(f'위기 대응: {n}번의 대응으로 수익률이 {_pp(effect)} 내려갔어요. (전부 버텼을 때와 비교)')
    return lines


def rule_based_tip(analysis: dict) -> str:
    """LLM 문장을 못 쓸 때의 '다음엔' 한 줄 — 사후 분석 결과에 따라 미리 정해 둔 문장 중 하나"""
    best, worst = best_and_worst(analysis)
    review = analysis.get('decisionReview') or {}
    decision_effect = review.get('effectReturnRate', 0.0) if review.get('rounds') else 0.0

    if worst and worst['effectReturnRate'] <= -1.0:
        ctype = worst['cardType']
        if ctype == 'BUY_ONCE':
            return '한 번에 크게 사는 카드는 시장이 더 떨어질 수 있을 때 고르면 손실이 커질 수 있어요.'
        if ctype == 'BUY_ON_CONDITION':
            return '조건이 맞을 때마다 사는 카드는 하락이 길어지면 손실이 쌓일 수 있으니, 현금을 지키는 카드와 섞어 보세요.'
        if ctype in ('BUY_SPLIT', 'BUY_EVERY_N'):
            return '꾸준히 나눠 사는 카드는 그 자산이 계속 떨어지는 구간에서는 손실이 쌓일 수 있어요.'
    if decision_effect <= -1.0:
        return '속보에 바로 움직인 매매가 결과를 낮췄어요. 다음엔 전략 카드에 맡기고 버텨 보는 것도 방법이에요.'
    if decision_effect >= 1.0:
        return '위기 때의 대응이 결과를 끌어올렸어요. 어떤 뉴스에서 통했는지 위기 대응 돌아보기에서 확인해 보세요.'
    if analysis['playerResult']['finalReturnRate'] >= analysis['risk']['marketReturnRate']:
        return '시장보다 잘 방어했어요. 같은 전략이 다른 위기에서도 통하는지 확인해 보세요.'
    return '자산을 한 종류에 몰지 말고 성격이 다른 카드를 섞어 보세요.'


def build_prompt(analysis: dict) -> str:
    """LLM에는 사실을 주고 '다음엔' 한 문장만 받는다. 숫자·카드 규칙은 쓰지 않게 한다."""
    p = analysis['playerResult']
    risk = analysis['risk']
    card_lines = []
    for c in analysis.get('cardReport') or []:
        fact = CARD_FACTS.get(c['cardId'])
        rule = fact.condition_desc if fact else ''
        card_lines.append(
            f'- {c["round"]}라운드 {c["cardName"]} ({rule}): 발동 {c["triggerCount"]}회, '
            f'이 카드를 고르지 않았을 때와의 차이 {c["effectReturnRate"]:+.1f}%p')

    review = analysis.get('decisionReview')
    if review and review.get('rounds'):
        decision_lines = [
            f'- {r["round"]}라운드 속보에서 "{DECISION_LABELS.get(r["choice"], r["choice"])}" 선택'
            for r in review['rounds']
        ]
        decision_text = ('\n'.join(decision_lines)
                         + f'\n- 위기 대응 전체 효과(전부 버텼을 때와의 차이): {review["effectReturnRate"]:+.1f}%p')
    else:
        decision_text = '(없음)'

    return (
        f'투자 게임 한 판의 결과야. 아래는 프로그램이 계산한 사실이야.\n\n'
        f'시장(S&P500) 수익률: {risk["marketReturnRate"]:+.1f}%, 최대 낙폭 {risk["marketMdd"]:.1f}%\n'
        f'플레이어 수익률: {p["finalReturnRate"]:+.1f}%, 최대 낙폭 {risk["playerMdd"]:.1f}%, '
        f'전체 조합 중 상위 {p["topPercent"]:.1f}%\n\n'
        f'고른 카드(참고용 발동 조건):\n' + '\n'.join(card_lines) + '\n\n'
        f'위기 대응:\n{decision_text}\n\n'
        f'게임을 처음 한 사람에게, 이 결과를 바탕으로 다음 판에서 시도해 볼 점을 딱 한 문장으로 말해줘.\n'
        f'(요약·잘한 점·아쉬운 점은 화면에 따로 표시되니 반복하지 말고, 다음에 해 볼 것만.)\n'
        f'규칙:\n'
        f'- 한 문장, 50자 안팎. 해요체(~해 보세요, ~할 수 있어요)로 써.\n'
        f'- 숫자는 쓰지 마.\n'
        f'- 단정하지 마. "반드시", "무조건", "확실" 같은 말은 쓰지 마.\n'
        f'- 카드의 발동 조건, 매수·매도 비율, 최대 횟수는 쓰지 마.\n'
        f'- 위 목록에 없는 카드는 말하지 마.\n'
        f'- 특정 종목을 사라거나 팔라는 권유는 하지 마. 게임 속 전략 이야기만 해.\n'
        f'- 마크다운(#, **, 목록 기호)은 쓰지 마.'
    )


def check_tip(text: str, player_card_ids: List[int]) -> List[str]:
    """LLM '다음엔' 문장 검사 — 문제가 있으면 사유 목록 (비어 있으면 통과)"""
    issues = []
    if not text.strip():
        return ['[빈 문장]']
    if len(text) > MAX_TIP_LENGTH:
        issues.append(f'[길이 초과] {len(text)}자 (최대 {MAX_TIP_LENGTH}자)')
    digits = re.findall(r'\d+(?:\.\d+)?', text)
    if digits:
        issues.append(f'[숫자 사용] 숫자를 쓰지 않기로 한 문장에 숫자가 있음: {digits}')
    for w in ABSOLUTE_WORDS:
        if w in text:
            issues.append(f'[단정 표현] "{w}"')
    # 없는 카드 언급·카드 조건 오기재 — 게임 중 AI 설명과 같은 검증기
    issues += verify_feedback(text, already_cards=list(player_card_ids), ranking_card_ids=[]).issues
    return issues


def compose(lines: List[str], tip: str) -> str:
    return '\n'.join(lines + [f'다음엔: {tip}'])
