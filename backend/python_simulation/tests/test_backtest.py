"""
사후 분석(backtest.run_backtest) 테스트 (#125) — 가상의 주가 CSV 사용
"""
import pytest

import backtest
import game_logic as g

START = '2008-09-01'
PLAYER = {1: 1, 25: 4, 50: 5, 75: 9}
OFFERED = {1: [1, 3, 10], 25: [4, 7, 8], 50: [5, 2, 11], 75: [9, 6, 3]}
DECISIONS = {11: 'SELL_HALF', 21: 'HOLD', 61: 'BUY_MORE'}


@pytest.fixture(scope='module')
def result():
    return backtest.run_backtest(START, PLAYER, top_n=3, offered_cards=OFFERED, decisions=DECISIONS)


@pytest.fixture(scope='module')
def player_game():
    return g.run_game(START, PLAYER, price_data=backtest.get_price_data(START), decisions=DECISIONS)


@pytest.mark.parametrize('start, pool, total', [
    ('2008-09-01', 11, 7920), ('2000-03-01', 9, 3024), ('2020-02-19', 11, 7920),
])
def test_all_combinations_are_counted(start, pool, total):
    allc = backtest.all_combo_results(start, {}, '^SPX')
    assert len(allc['card_pool']) == pool
    assert len(allc['results']) == total
    assets = [a for _, a, _ in allc['results']]
    assert assets == sorted(assets, reverse=True)
    assert allc['ranks'][0] == 1 and max(allc['ranks']) <= total


def test_player_result_is_the_actual_game(result, player_game):
    p = result['playerResult']
    assert p['finalAsset'] == player_game['final_asset']
    assert p['finalReturnRate'] == player_game['final_return_rate']
    assert 1 <= p['rank'] <= result['totalCombinations'] == 7920
    assert p['topPercent'] == round(p['rank'] / 7920 * 100, 1)
    assert result['grade'] == backtest.grade_of(p['topPercent'])
    assert result['topCombos'][0]['rank'] == 1
    assert result['topCombos'][0]['finalAsset'] >= p['finalAsset']


def test_combinations_use_the_players_decisions():
    # 위기 대응이 다르면 같은 카드 조합이어도 결과가 달라진다 → 순위는 "같은 위기 대응" 안에서 매긴다
    with_decisions = backtest.all_combo_results(START, DECISIONS, '^SPX')
    without = backtest.all_combo_results(START, {}, '^SPX')
    combo = tuple(PLAYER[r] for r in g.CARD_SELECT_ROUNDS)
    a = with_decisions['results'][with_decisions['index'][combo]][1]
    b = without['results'][without['index'][combo]][1]
    assert a != b
    assert a == g.run_game(START, PLAYER, price_data=backtest.get_price_data(START),
                           decisions=DECISIONS)['final_asset']


@pytest.mark.parametrize('top_percent, grade', [
    (0.1, 'S'), (5.0, 'S'), (5.1, 'A'), (20.0, 'A'), (20.1, 'B'), (50.0, 'B'), (50.1, 'C'), (80.0, 'C'),
    (80.1, 'D'), (100.0, 'D'),
])
def test_grade_bounds(top_percent, grade):
    assert backtest.grade_of(top_percent) == grade


def test_results_are_cached():
    decisions = {30: 'BUY_MORE'}
    assert not backtest.is_cached(START, decisions)
    first = backtest.all_combo_results(START, decisions, '^SPX')
    assert backtest.is_cached(START, decisions)
    assert backtest.all_combo_results(START, decisions, '^SPX') is first      # 다시 계산하지 않음
    assert backtest.prewarm(START, decisions) == 'ready'
    assert not backtest.is_cached(START, decisions, '^NDX')                   # 기준 종목이 다르면 다른 결과


def test_prewarm_computes_in_background():
    decisions = {40: 'SELL_HALF'}
    assert backtest.prewarm(START, decisions) == 'started'
    # 미리 계산이 진행 중이어도 같은 키를 요청하면 그 계산이 끝나기를 기다려 같은 결과를 받는다
    allc = backtest.all_combo_results(START, decisions, '^SPX')
    assert len(allc['results']) == 7920
    assert backtest.prewarm(START, decisions) == 'ready'


def test_offered_analysis(result):
    oa = result['offeredAnalysis']
    assert oa['playerResult']['finalAsset'] == result['playerResult']['finalAsset']
    assert oa['bestCombo']['finalAsset'] >= oa['playerResult']['finalAsset']
    assert 1 <= oa['totalCombinations'] <= 81
    assert [ra['round'] for ra in oa['roundAlternatives']] == g.CARD_SELECT_ROUNDS
    for ra in oa['roundAlternatives']:
        for alt in ra['alternatives']:
            assert alt['diffReturnRate'] == round(alt['finalReturnRate'] - oa['playerResult']['finalReturnRate'], 2)


def test_risk(result, player_game):
    risk = result['risk']
    assets = [g.INITIAL_ASSET] + [r['roundAsset'] for r in player_game['rounds']]
    peak, worst = assets[0], 0.0
    for a in assets:
        peak = max(peak, a)
        worst = min(worst, (a - peak) / peak * 100)
    assert risk['playerMdd'] == round(worst, 2) <= 0
    assert risk['marketMdd'] < 0                                   # 가상의 2008년 구간은 하락장
    spx = backtest.get_price_data(START)['close']['^SPX']
    assert risk['marketReturnRate'] == round((spx[99] - spx[0]) / spx[0] * 100, 2)
    assert risk['playerMddDate'] in backtest.get_price_data(START)['dates'][:100]


def test_card_report_is_difference_from_game_without_the_card(result, player_game):
    report = result['cardReport']
    assert [c['round'] for c in report] == g.CARD_SELECT_ROUNDS
    assert [c['cardId'] for c in report] == [PLAYER[r] for r in g.CARD_SELECT_ROUNDS]
    data = backtest.get_price_data(START)
    for c in report:
        without = {r: card for r, card in PLAYER.items() if r != c['round']}
        game = g.run_game(START, without, price_data=data, decisions=DECISIONS)
        assert c['withoutFinalAsset'] == game['final_asset']
        assert c['effectAsset'] == player_game['final_asset'] - game['final_asset']
        assert c['effectReturnRate'] == round(player_game['final_return_rate'] - game['final_return_rate'], 2)
        stats = player_game['card_stats'][c['cardId']]
        assert (c['triggerCount'], c['tradeAmount'], c['skips']) == (stats['triggers'], stats['amount'], stats['skips'])
        assert c['cardName'] == g.CARDS[c['cardId']]['name']


def test_decision_review(result, player_game):
    review = result['decisionReview']
    assert [d['round'] for d in review['rounds']] == sorted(DECISIONS)
    data = backtest.get_price_data(START)
    for d in review['rounds']:
        assert d['choice'] == DECISIONS[d['round']]
        assert {a['choice'] for a in d['alternatives']} == set(g.DECISION_CHOICES) - {d['choice']}
        for alt in d['alternatives']:
            changed = dict(DECISIONS)
            changed[d['round']] = alt['choice']
            game = g.run_game(START, PLAYER, price_data=data, decisions=changed)
            assert alt['finalAsset'] == game['final_asset']
            assert alt['diffReturnRate'] == round(game['final_return_rate'] - player_game['final_return_rate'], 2)
    all_hold = g.run_game(START, PLAYER, price_data=data, decisions={r: 'HOLD' for r in DECISIONS})
    assert review['allHoldFinalAsset'] == all_hold['final_asset']
    assert review['effectReturnRate'] == round(player_game['final_return_rate'] - all_hold['final_return_rate'], 2)
    traded = {d['round']: d['tradeAmount'] for d in review['rounds']}
    assert traded[21] == 0 and traded[11] > 0 and traded[61] > 0


def test_no_decisions_means_no_review():
    res = backtest.run_backtest(START, PLAYER)
    assert res['decisionReview'] is None
    assert res['offeredAnalysis'] is None


def test_all_hold_has_zero_effect():
    res = backtest.run_backtest(START, PLAYER, decisions={11: 'HOLD', 61: 'HOLD'})
    assert res['decisionReview']['effectReturnRate'] == 0
    assert res['playerResult']['finalAsset'] == backtest.run_backtest(START, PLAYER)['playerResult']['finalAsset']


def test_epilogue_values_holdings_after_the_game(result, player_game):
    ep = result['epilogue']
    data = backtest.get_price_data(START)
    assert ep['endDate'] == data['dates'][99]
    assert [p['label'] for p in ep['points']] == ['6개월 뒤', '1년 뒤']
    for point in ep['points']:
        idx = 99 + point['tradingDays']
        assert point['date'] == data['dates'][idx]
        value = player_game['final_cash'] + int(sum(
            player_game['final_shares'][t] * data['close'][t][idx]
            for t in g.TICKERS if data['close'][t][idx] is not None))
        assert point['playerAsset'] == pytest.approx(value, abs=1)
        spx = data['close']['^SPX']
        assert point['spxChangeRate'] == round((spx[idx] - spx[99]) / spx[99] * 100, 2)
        assert point['bestAsset'] is not None


def test_epilogue_is_none_when_data_ends_with_the_game():
    data = backtest.get_price_data(START)
    short = {'dates': data['dates'][:150], 'close': {t: v[:150] for t, v in data['close'].items()}}
    game = g.run_game(START, PLAYER, price_data=short)
    assert backtest._epilogue(game, None, short, g.INITIAL_ASSET) is None


@pytest.mark.parametrize('selections, message', [
    ({1: 1, 25: 4, 50: 5}, '카드 선택 라운드'),
    ({1: 1, 25: 1, 50: 5, 75: 9}, '유효하지 않은 카드 조합'),
    ({1: 1, 25: 4, 50: 5, 75: 99}, '유효하지 않은 카드 조합'),
])
def test_invalid_selections_are_rejected(selections, message):
    with pytest.raises(ValueError, match=message):
        backtest.run_backtest(START, selections)


def test_unavailable_card_is_rejected_for_dotcom():
    with pytest.raises(ValueError, match='사용할 수 없는 카드'):
        backtest.run_backtest('2000-03-01', {1: 7, 25: 4, 50: 5, 75: 9})
