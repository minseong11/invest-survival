"""
사후 분석 AI 코치 한마디(result_coach) 테스트 (#125)
"""
import pytest

import result_coach as rc


def analysis(card_effects, decision=None, mine=-10.0, market=-30.0):
    """card_effects: [(카드ID, 이름, 종류, 효과 %p)], decision: (선택 목록, 전체 효과 %p)"""
    out = {
        'playerResult': {'finalReturnRate': mine, 'topPercent': 40.0},
        'risk': {'marketReturnRate': market, 'marketMdd': -35.0, 'playerMdd': -15.0},
        'cardReport': [
            {'round': r, 'cardId': cid, 'cardName': name, 'cardType': ctype,
             'triggerCount': 3, 'effectReturnRate': effect}
            for r, (cid, name, ctype, effect) in zip([1, 25, 50, 75], card_effects)
        ],
        'decisionReview': None,
    }
    if decision:
        choices, effect = decision
        out['decisionReview'] = {
            'rounds': [{'round': 10 + i, 'choice': c} for i, c in enumerate(choices)],
            'effectReturnRate': effect,
        }
    return out


CARDS4 = [(1, '거인의 어깨', 'BUY_ONCE', -8.7), (4, '금 피난처', 'BUY_ON_CONDITION', 14.5),
          (5, '기술의 파도', 'BUY_ON_CONDITION', -0.4), (9, '애플 줍줍', 'BUY_ON_CONDITION', 0.0)]


def heads(lines):
    return [line.split(':')[0] for line in lines]


def test_fact_lines_use_analysis_numbers():
    lines = rc.fact_lines(analysis(CARDS4, decision=(['SELL_HALF', 'HOLD', 'BUY_MORE'], 6.3)))
    assert heads(lines) == ['요약', '잘한 점', '아쉬운 점', '위기 대응']
    assert lines[0] == '요약: 같은 기간 S&P500은 30.0% 떨어졌고, 내 자산은 10.0% 줄었어요.'
    assert '금 피난처' in lines[1] and '14.5%p 낮았을' in lines[1]
    assert '거인의 어깨' in lines[2] and '8.7%p 높았을' in lines[2]
    assert '3번의 대응으로 수익률이 6.3%p 올랐어요' in lines[3]


@pytest.mark.parametrize('mine, market, expected', [
    (12.3, -6.8, '같은 기간 S&P500은 6.8% 떨어졌고, 내 자산은 12.3% 늘었어요.'),
    (-2.0, 7.3, '같은 기간 S&P500은 7.3% 올랐고, 내 자산은 2.0% 줄었어요.'),
    (0.0, 0.01, '같은 기간 S&P500은 거의 그대로였고, 내 자산은 거의 그대로였어요.'),
    # 정확히 절반인 값은 앱의 숫자와 같은 쪽으로 (앱의 수익률 막대는 -13.3%, 21.3%)
    (-13.25, 21.25, '같은 기간 S&P500은 21.3% 올랐고, 내 자산은 13.3% 줄었어요.'),
])
def test_summary_directions(mine, market, expected):
    assert rc.fact_lines(analysis(CARDS4, mine=mine, market=market))[0] == f'요약: {expected}'


def test_small_effects_are_not_called_good_or_bad():
    flat = [(1, '거인의 어깨', 'BUY_ONCE', 0.05), (2, '황금 적립', 'BUY_SPLIT', -0.05),
            (3, '공포탐욕', 'BUY_ON_CONDITION', 0.0), (9, '애플 줍줍', 'BUY_ON_CONDITION', 0.0)]
    lines = rc.fact_lines(analysis(flat))
    assert heads(lines) == ['요약', '잘한 점']
    assert '카드를 바꿔도 결과가 거의 같았어요' in lines[1]


@pytest.mark.parametrize('decision, expected', [
    ((['HOLD', 'HOLD', 'HOLD'], 0.0), '속보 3번 모두 전략 카드를 믿고 버텼어요.'),
    ((['HOLD', 'SELL_HALF'], 0.01), '2번의 대응은 결과를 거의 바꾸지 않았어요.'),
    ((['SELL_HALF', 'BUY_MORE'], -4.2), '2번의 대응으로 수익률이 4.2%p 내려갔어요. (전부 버텼을 때와 비교)'),
])
def test_decision_line(decision, expected):
    assert rc.fact_lines(analysis(CARDS4, decision=decision))[-1] == f'위기 대응: {expected}'


@pytest.mark.parametrize('cards, decision, mine, expected', [
    ([(1, '거인의 어깨', 'BUY_ONCE', -8.7)] + CARDS4[1:], None, -10.0, '한 번에 크게 사는 카드'),
    ([(3, '공포탐욕', 'BUY_ON_CONDITION', -14.0)] + CARDS4[1:], None, -10.0, '조건이 맞을 때마다 사는 카드'),
    ([(2, '황금 적립', 'BUY_SPLIT', -3.0)] + CARDS4[1:], None, -10.0, '꾸준히 나눠 사는 카드'),
    ([(8, '역발상 투자', 'SELL_ON_CONDITION', -0.3)] + CARDS4[1:], (['SELL_HALF'], -2.0), -10.0, '속보에 바로 움직인 매매'),
    ([(8, '역발상 투자', 'SELL_ON_CONDITION', -0.3)] + CARDS4[1:], (['SELL_HALF'], 2.0), -10.0, '위기 때의 대응이 결과를 끌어올렸어요'),
    ([(8, '역발상 투자', 'SELL_ON_CONDITION', -0.3)] + CARDS4[1:], None, -10.0, '시장보다 잘 방어했어요'),
    ([(8, '역발상 투자', 'SELL_ON_CONDITION', -0.3)] + CARDS4[1:], None, -40.0, '성격이 다른 카드를 섞어 보세요'),
])
def test_rule_based_tip(cards, decision, mine, expected):
    tip = rc.rule_based_tip(analysis(cards, decision=decision, mine=mine))
    assert expected in tip
    assert rc.check_tip(tip, [c[0] for c in cards]) == []          # 규칙 기반 문장은 스스로 검사를 통과해야 한다


@pytest.mark.parametrize('text, issue', [
    ('하락장에서는 나눠 사는 카드를 먼저 골라 보세요.', None),
    ('금 피난처처럼 떨어질 때 버텨 주는 카드를 먼저 골라 보세요.', None),
    ('다음엔 현금을 30% 남겨 보세요.', '숫자 사용'),
    ('금 카드를 반드시 먼저 고르세요.', '단정 표현'),
    ('무조건 버티는 게 좋아요.', '단정 표현'),
    ('황금 적립을 먼저 골라 보세요.', '미포함 카드 언급'),
    ('금 피난처는 SPX가 -3% 이하일 때 사니까 먼저 골라 보세요.', '조건 불일치'),
    ('', '빈 문장'),
    ('가' * 130, '길이 초과'),
])
def test_check_tip(text, issue):
    issues = rc.check_tip(text, [1, 4, 5, 9])
    if issue is None:
        assert issues == []
    else:
        assert any(issue in i for i in issues), issues


def test_prompt_contains_facts_and_rules():
    prompt = rc.build_prompt(analysis(CARDS4, decision=(['SELL_HALF', 'HOLD'], 6.3)))
    assert '거인의 어깨' in prompt and '-8.7%p' in prompt
    assert '"절반 판다"' in prompt and '+6.3%p' in prompt
    assert '숫자는 쓰지 마' in prompt and '한 문장' in prompt
    assert '(없음)' in rc.build_prompt(analysis(CARDS4))


def test_compose_puts_tip_last():
    text = rc.compose(['요약: 가', '잘한 점: 나'], '다 해 보세요.')
    assert text.split('\n') == ['요약: 가', '잘한 점: 나', '다음엔: 다 해 보세요.']
