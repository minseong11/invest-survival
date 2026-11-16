"""
게임 엔진(game_logic.run_game) 테스트 (#125)

손으로 만든 가격으로 카드 규칙·위기 대응·건너뜀 사유를 하나씩 확인한다.
기대값은 규칙을 그대로 손계산한 값이다 (Java GameService와 같은 연산 순서·버림).
"""
import random
from itertools import permutations

import pytest

import game_logic as g
from conftest import make_price_data

R = g.CARD_SELECT_ROUNDS
INITIAL = g.INITIAL_ASSET


def flat(n=120, value=100.0):
    return [value] * n


def with_moves(moves, n=120, start=100.0):
    """moves: {라운드: 전일 대비 등락률(%)} — 그 라운드에만 가격이 움직이고 나머지는 그대로"""
    prices = [start]
    for i in range(1, n):
        change = moves.get(i + 1, 0.0)
        prices.append(prices[-1] * (1 + change / 100))
    return prices


# ── Java와 같은 반올림 ───────────────────────────────────────

@pytest.mark.parametrize('value, expected', [
    (2.5, 3), (-2.5, -2), (2.4999, 2), (-2.5001, -3), (0.5, 1), (-0.5, 0), (7.0, 7), (-299.5, -299),
])
def test_java_round_ties_go_up(value, expected):
    assert g._java_round(value) == expected


def test_change_rate_is_rounded_to_two_decimals_before_comparing():
    # -2.996%는 -3.00%로 반올림된 뒤 조건(-3% 이하)과 비교된다 (Java와 같은 규칙)
    assert g._calc_change_rate(100.0, 97.004) == -3.0
    assert g._calc_change_rate(100.0, 97.006) == -2.99
    assert g._calc_change_rate(None, 97.0) is None
    assert g._calc_change_rate(0.0, 97.0) is None


# ── 카드 종류별 규칙 ─────────────────────────────────────────

def test_no_cards_keeps_cash():
    game = g.run_game('x', {}, price_data=make_price_data(with_moves({10: -8, 20: 6})))
    assert game['final_asset'] == INITIAL
    assert len(game['rounds']) == 100
    assert all(r['roundAsset'] == INITIAL and not r['triggeredCards'] for r in game['rounds'])


def test_buy_once_buys_30_percent_at_selection_round():
    # 거인의 어깨(1번): 고른 라운드 종가로 현금의 30% 매수. 50라운드 뒤 가격이 2배
    spx = flat(50) + flat(70, 200.0)
    game = g.run_game('x', {1: 1}, price_data=make_price_data(spx))
    assert game['rounds'][0]['roundAsset'] == INITIAL             # 산 날은 평가액 그대로
    assert game['final_cash'] == 7_000_000
    assert game['final_shares']['^SPX'] == pytest.approx(30_000)
    assert game['final_asset'] == 7_000_000 + 6_000_000
    assert game['final_return_rate'] == 30.0
    assert game['card_stats'][1] == {'triggers': 1, 'amount': 3_000_000, 'skips': {}}


def test_buy_once_at_later_round_uses_that_rounds_price():
    spx = flat(24) + flat(96, 50.0)                               # 25라운드부터 50
    game = g.run_game('x', {25: 1}, price_data=make_price_data(spx))
    assert game['final_shares']['^SPX'] == pytest.approx(3_000_000 / 50.0)
    assert game['rounds'][23]['roundAsset'] == INITIAL
    assert game['final_asset'] == INITIAL


def test_buy_split_buys_every_round_until_cash_is_low():
    # 황금 적립(2번): 매 라운드 현금의 5%. 현금이 총자산의 5% 아래로 내려가면 쉰다
    game = g.run_game('x', {1: 2}, price_data=make_price_data(flat()))
    stats = game['card_stats'][2]
    assert stats['triggers'] + stats['skips'][g.SKIP_CASH_LOW] == 100
    assert stats['triggers'] == 59                                # 0.95^59 < 0.05 <= 0.95^58
    assert game['rounds'][0]['triggeredCards'] == [2]
    assert game['rounds'][99]['skippedCards'] == [{'cardId': 2, 'reason': g.SKIP_CASH_LOW}]
    # 현금은 원 단위 정수이고, 매수 금액의 소수점 아래는 버려진다
    assert isinstance(game['final_cash'], int)
    assert game['final_asset'] >= INITIAL                         # 버린 만큼은 현금에 남는다
    assert game['final_asset'] - INITIAL < stats['triggers']      # 매수 한 번에 1원 미만


def test_condition_card_triggers_only_on_matching_days():
    # 공포탐욕(3번): S&P500 -3% 이하인 날마다 현금의 20%로 매수
    spx = with_moves({10: -3.0, 20: -2.99, 30: -5.0, 40: 4.0})
    game = g.run_game('x', {1: 3}, price_data=make_price_data(spx))
    triggered = [r['round'] for r in game['rounds'] if 3 in r['triggeredCards']]
    assert triggered == [10, 30]
    assert game['card_stats'][3]['triggers'] == 2
    assert game['card_stats'][3]['amount'] == 2_000_000 + 1_600_000


def test_condition_cards_do_not_trigger_on_first_round():
    # 1라운드는 전일 가격이 없어 등락률을 알 수 없다 → 조건부 카드는 발동하지 않는다
    game = g.run_game('x', {1: 3}, price_data=make_price_data(flat()))
    assert game['card_stats'][3]['triggers'] == 0


def test_max_trigger_limits_card_and_reports_reason():
    # 낙폭과대 사냥(6번): 나스닥 -4% 이하, 최대 3회
    ndx = with_moves({10: -4, 20: -5, 30: -4.5, 40: -6, 50: -4})
    game = g.run_game('x', {1: 6}, price_data=make_price_data(flat(), ndx=ndx))
    triggered = [r['round'] for r in game['rounds'] if 6 in r['triggeredCards']]
    skipped = [r['round'] for r in game['rounds'] if r['skippedCards']]
    assert triggered == [10, 20, 30]
    assert skipped == [40, 50]
    assert game['card_stats'][6]['skips'] == {g.SKIP_MAX_REACHED: 2}


def test_sell_card_without_holdings_is_skipped_not_triggered():
    # 역발상 투자(8번): S&P500 +3% 이상인 날 보유 S&P500의 15% 매도. 가진 게 없으면 '보유 없음'
    spx = with_moves({10: 3.5, 20: 4.0})
    game = g.run_game('x', {1: 8}, price_data=make_price_data(spx))
    assert game['final_asset'] == INITIAL
    assert game['card_stats'][8] == {'triggers': 0, 'amount': 0, 'skips': {g.SKIP_NO_HOLDINGS: 2}}
    assert all(8 not in r['triggeredCards'] for r in game['rounds'])


def test_sell_card_sells_15_percent_of_holdings():
    spx = with_moves({30: 5.0})
    game = g.run_game('x', {1: 1, 25: 8}, price_data=make_price_data(spx))
    assert [r['round'] for r in game['rounds'] if 8 in r['triggeredCards']] == [30]
    assert game['final_shares']['^SPX'] == pytest.approx(30_000 * 0.85)
    assert game['final_cash'] == 7_000_000 + int(30_000 * 0.15 * 105.0)


def test_buy_every_n_buys_on_multiples_of_five_after_selection():
    # 분할매수 장인(11번): 5라운드마다. 25라운드에 고르면 25, 30, 35, ...
    game = g.run_game('x', {25: 11}, price_data=make_price_data(flat()))
    triggered = [r['round'] for r in game['rounds'] if 11 in r['triggeredCards']]
    assert triggered == list(range(25, 101, 5))


def test_cards_run_in_priority_order_within_a_round():
    # 같은 날 두 카드가 발동하면 priority가 낮은 카드가 먼저 현금을 쓴다 (황금 적립 2 → 공포탐욕 3)
    spx = with_moves({10: -4.0})
    game = g.run_game('x', {1: 3, 25: 2}, price_data=make_price_data(spx))
    assert game['rounds'][24]['triggeredCards'] == [2]
    both = g.run_game('x', {1: 2, 25: 3}, price_data=make_price_data(with_moves({30: -4.0})))
    assert both['rounds'][29]['triggeredCards'] == [2, 3]


def test_unlisted_ticker_card_is_rejected():
    # 상장 전 종목(가격 없음)의 카드는 고를 수 없다
    data = make_price_data(flat(), listed=['^SPX', '^NDX', 'GLD', 'AAPL'])
    assert g.available_card_ids(data) == [1, 2, 3, 4, 5, 6, 8, 9, 11]
    with pytest.raises(ValueError, match='상장 전'):
        g.run_game('x', {1: 7}, price_data=data)
    with pytest.raises(ValueError, match='상장 전'):
        g.run_game('x', {1: 10}, price_data=data)


def test_not_enough_rounds_is_rejected():
    with pytest.raises(ValueError, match='데이터 부족'):
        g.run_game('x', {1: 1}, price_data=make_price_data(flat(99)))


# ── 위기 대응 ────────────────────────────────────────────────

def test_hold_changes_nothing():
    data = make_price_data(with_moves({10: -8, 40: 5}))
    base = g.run_game('x', {1: 1, 25: 2}, price_data=data)
    held = g.run_game('x', {1: 1, 25: 2}, price_data=data, decisions={10: 'HOLD', 60: 'HOLD'})
    assert held['final_asset'] == base['final_asset']
    assert [r['roundAsset'] for r in held['rounds']] == [r['roundAsset'] for r in base['rounds']]
    assert held['decision_log'] == [{'round': 10, 'choice': 'HOLD', 'amount': 0},
                                    {'round': 60, 'choice': 'HOLD', 'amount': 0}]


def test_sell_half_sells_half_of_every_holding_at_that_rounds_close():
    spx = flat(9) + flat(111, 80.0)                               # 10라운드에 80으로 하락
    game = g.run_game('x', {1: 1}, price_data=make_price_data(spx), decisions={10: 'SELL_HALF'})
    assert game['final_shares']['^SPX'] == pytest.approx(15_000)
    assert game['final_cash'] == 7_000_000 + 15_000 * 80
    assert game['decision_log'] == [{'round': 10, 'choice': 'SELL_HALF', 'amount': 1_200_000}]


def test_sell_half_with_no_holdings_does_nothing():
    game = g.run_game('x', {25: 1}, price_data=make_price_data(flat()), decisions={10: 'SELL_HALF'})
    assert game['decision_log'][0]['amount'] == 0
    assert game['final_asset'] == INITIAL


def test_buy_more_buys_30_percent_of_cash_of_base_index():
    ndx = flat(9) + flat(111, 50.0)
    data = make_price_data(flat(), ndx=ndx)
    spx_game = g.run_game('x', {}, price_data=data, decisions={10: 'BUY_MORE'})
    assert spx_game['final_shares']['^SPX'] == pytest.approx(30_000)
    assert spx_game['final_cash'] == 7_000_000
    ndx_game = g.run_game('x', {}, price_data=data, decisions={10: 'BUY_MORE'}, base_ticker='^NDX')
    assert ndx_game['final_shares']['^NDX'] == pytest.approx(3_000_000 / 50.0)
    assert ndx_game['final_shares']['^SPX'] == 0


def test_decision_happens_before_cards_on_the_same_round():
    # 같은 라운드에 위기 대응(절반 판다)이 먼저, 그다음 카드(공포탐욕)가 늘어난 현금으로 매수
    spx = with_moves({10: -5.0})
    data = make_price_data(spx)
    game = g.run_game('x', {1: 1, 25: 3}, price_data=data, decisions={10: 'SELL_HALF'})
    assert game['decision_log'][0]['amount'] == int(15_000 * 95.0)
    after = g.run_game('x', {1: 3}, price_data=data, decisions={10: 'BUY_MORE'})
    # 더 산다(현금 30%) → 남은 현금 700만원의 20%를 카드가 매수
    assert after['card_stats'][3]['amount'] == 1_400_000


@pytest.mark.parametrize('decisions, message', [
    ({25: 'HOLD'}, '카드 선택 라운드가 아닌'),
    ({1: 'HOLD'}, '카드 선택 라운드가 아닌'),
    ({100: 'SELL_HALF'}, '2~99라운드'),
    ({10: 'PANIC'}, '알 수 없는 위기 대응'),
])
def test_invalid_decisions_are_rejected(decisions, message):
    with pytest.raises(ValueError, match=message):
        g.run_game('x', {1: 1}, price_data=make_price_data(flat()), decisions=decisions)


def test_decision_keys_may_be_strings():
    data = make_price_data(flat())
    a = g.run_game('x', {'1': 1}, price_data=data, decisions={'10': 'SELL_HALF'})
    b = g.run_game('x', {1: 1}, price_data=data, decisions={10: 'SELL_HALF'})
    assert a['final_asset'] == b['final_asset'] and a['decisions'] == {'10': 'SELL_HALF'}


# ── 빠른 경로 = 전체 경로 (가상의 주가 CSV로 무작위 조합) ──────

@pytest.mark.parametrize('start_date, base', [('2008-09-01', '^SPX'), ('2000-03-01', '^NDX'), ('2020-02-19', '^SPX')])
def test_fast_path_matches_full_path(start_date, base):
    data = g.load_price_data(start_date)
    pool = g.available_card_ids(data)
    rng = random.Random(7)
    combos = rng.sample(list(permutations(pool, 4)), 120)
    keys = ['final_asset', 'final_return_rate', 'final_cash', 'final_shares', 'card_stats', 'decision_log']
    for k, combo in enumerate(combos):
        selection = dict(zip(R, combo))
        decisions = {}
        if k % 2:
            rounds = rng.sample([r for r in range(2, 100) if r not in R], 3)
            decisions = {r: rng.choice(g.DECISION_CHOICES) for r in rounds}
        full = g.run_game(start_date, selection, price_data=data, decisions=decisions, base_ticker=base)
        fast = g.run_game(start_date, selection, price_data=data, decisions=decisions, base_ticker=base,
                          collect_rounds=False)
        assert {k_: full[k_] for k_ in keys} == {k_: fast[k_] for k_ in keys}, (combo, decisions)
        assert len(full['rounds']) == 100 and len(fast['rounds']) == 1
        assert fast['rounds'][0] == full['rounds'][-1]


def test_round_assets_are_integers_and_consistent():
    data = g.load_price_data('2008-09-01')
    game = g.run_game('2008-09-01', {1: 3, 25: 2, 50: 6, 75: 9}, price_data=data, decisions={30: 'SELL_HALF'})
    for r in game['rounds']:
        assert isinstance(r['roundAsset'], int)
        assert r['returnRate'] == g._round2((r['roundAsset'] - INITIAL) / INITIAL * 100)
        assert not set(r['triggeredCards']) & {s['cardId'] for s in r['skippedCards']}
    assert game['final_asset'] == game['rounds'][-1]['roundAsset']


# ── 가격 정렬 (S&P500 거래일 기준) ───────────────────────────

def test_price_alignment_uses_previous_close_and_none_before_listing():
    import data_loader
    data = g.load_price_data('2000-03-01')
    assert data['dates'][0] == '2000-03-01'
    # 닷컴 시작일에는 원유·채권이 상장 전 → 가격 없음(None, 0이 아님)
    assert data['close']['USO'][0] is None and data['close']['TLT'][0] is None
    assert all(len(data['close'][t]) == len(data['dates']) for t in g.TICKERS)
    # 금은 빠진 날이 있다 → 그날은 직전 거래일 종가
    gold = data_loader.load_all()['GLD']
    gold_dates = set(gold['Date'].dt.strftime('%Y-%m-%d'))
    missing = [i for i, d in enumerate(data['dates'][:200]) if d not in gold_dates]
    assert missing, '가상의 금 데이터에는 빠진 날이 있어야 한다'
    for i in missing:
        assert data['close']['GLD'][i] == data['close']['GLD'][i - 1]
