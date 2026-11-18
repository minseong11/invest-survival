"""
e2e_game_flow.py — 실제 게임 흐름을 API로 끝까지 진행하며 확인 (#125)

Spring Boot(8080)와 FastAPI(8000)가 켜진 상태에서, 시나리오마다 게임을 시작해
카드 선택·위기 대응을 무작위로 고르며 100라운드까지 진행하고 아래를 확인한다.
  1) 이벤트 순서: 카드 선택(1·25·50·75) + 위기 대응 라운드에서만 멈추고, 1~100라운드가 빠짐없이 온다
  2) 라운드 응답: 자산·수익률, 보유 자산 비중 + 현금 비중 = 100%, 발동·건너뜀 정보,
     종목 가격(priceData)은 보유 여부와 관계없이 그날 가격이 있는 모든 종목 (1라운드 포함),
     다음 이벤트 라운드의 그날 시장(nextEventMarket)이 그 라운드 날짜·가격과 같은지
  3) 잘못된 요청은 400 (같은 라운드 재선택, 제시되지 않은 카드, 위기 대응 라운드에 카드 선택, 빈 요청 등)
  4) 실제 게임의 라운드별 자산 = Python run_game(같은 카드·같은 위기 대응)의 라운드별 자산 (원 단위까지)
  5) 사후 분석: 내 결과가 실제 게임 결과와 같고, 등급·최대 낙폭·카드별 성적표·위기 대응 돌아보기가 온다
  6) AI 코치 한마디가 온다 (LLM이 실패해도 규칙 기반 문장)
  7) AI 예측: 25·50라운드는 응답(모델 파일이 없으면 503), 그 외 라운드는 400
  8) (12주차 피드백 1번) 25·50라운드 즉시 매수 카드 대조: 고르기 전 현금 × 적용 비율 = 실제 매수 금액,
     매수 시점 = 고른 라운드 종가, 설명(FastAPI CARD_FACTS·서버 DB·앱 카드 설명)의 비율·시점이 같은지.
     25·50라운드에 즉시 매수 카드가 나오면 그 카드를 고르고, 한 번도 확인하지 못했으면 판을 더 진행한다

compare_java_python.py가 검증용 엔드포인트(/game/validate)를 비교한다면,
이 스크립트는 앱이 실제로 쓰는 엔드포인트(/game/start, /game/round/action, /game/round/decision, ...)를 지나간다.

사용법:
    cd backend/python_simulation
    python3 e2e_game_flow.py              # 시나리오마다 2판
    python3 e2e_game_flow.py --games 5 --seed 7
종료 코드: 실패가 하나라도 있으면 1
"""
import argparse
import os
import random
import sys

import re

import requests

from game_logic import run_game, load_price_data, CARD_SELECT_ROUNDS, DECISION_CHOICES
from verify_feedback import CARD_FACTS

JAVA = os.environ.get('JAVA_URL', 'http://localhost:8080')
GRADES = {'S', 'A', 'B', 'C', 'D'}
SKIP_REASONS = {'CASH_LOW', 'MAX_REACHED', 'NO_HOLDINGS', 'NO_PRICE'}
TICKERS = ['^SPX', '^NDX', 'XAUUSD', 'USO', 'AAPL', 'TLT']     # 서버 GameService.TICKERS와 같은 순서
PY_TICKER = {'XAUUSD': 'GLD'}                                   # Python game_logic은 금을 GLD로 부른다

failures = []
immediate_buys = []     # 즉시 매수 대조 기록 (8번)

HERE = os.path.dirname(os.path.abspath(__file__))
# 즉시 매수 카드: 카드 ID → (종목, 비율). 서버 data.sql·game_logic.CARDS와 같은 값이어야 한다 (아래에서 대조)
BUY_ONCE = {1: ('^SPX', 0.30), 7: ('USO', 0.20)}
CARD_TICKER = {1: '^SPX', 2: 'XAUUSD', 3: '^SPX', 4: 'XAUUSD', 5: '^NDX', 6: '^NDX',
               7: 'USO', 8: '^SPX', 9: 'AAPL', 10: 'TLT', 11: '^NDX'}


def _description_in(path, card_id, pattern):
    """data.sql / card_info.dart에서 그 카드의 설명 문장을 찾는다"""
    try:
        text = open(path, encoding='utf-8').read()
    except OSError:
        return None
    m = re.search(pattern.format(id=card_id), text, re.S)
    return m.group(1) if m else None


def check_immediate_buy(title, rnd, card, before, after, price_data):
    """고르기 전 현금 × 비율 = 고른 라운드 종가로 산 금액, 그리고 세 곳의 설명이 같은 비율·시점을 말하는지"""
    ticker, ratio = BUY_ONCE[card]
    name = CARD_FACTS[card].name
    others = [c for c in after['triggeredCards'] if c != card and CARD_TICKER.get(c) == ticker]
    if others:      # 같은 날 같은 종목을 사고판 다른 카드가 있으면 이 카드 몫만 떼어 볼 수 없다
        print(f'    [즉시 매수 대조 건너뜀] {rnd}R {name}: 같은 날 {ticker} 카드 {others}도 발동')
        return

    def shares(r):
        return next((h['shares'] for h in r['holdings'] if h['ticker'] == ticker), 0.0)

    close = price_data['close'][PY_TICKER.get(ticker, ticker)][rnd - 1]
    cash_before = before['cash']
    expected = cash_before * ratio
    bought = (shares(after) - shares(before)) * close
    ok_amount = check(abs(bought - expected) <= max(2.0, expected * 0.0005),
                      f'{title} {rnd}R {name}: 고르기 전 현금 {cash_before:,.0f}원 × {ratio:.0%} = {expected:,.0f}원인데 '
                      f'실제 매수 {bought:,.0f}원')
    ok_when = check(before['round'] == rnd - 1 and after['round'] == rnd
                    and after['date'] == str(price_data['dates'][rnd - 1])[:10],
                    f'{title} {rnd}R {name}: 매수 시점이 고른 라운드({rnd}R) 종가가 아님 ({after["date"]})')

    # 설명 세 곳 — 비율과 "고른 라운드에 즉시"가 실제 계산과 같은지
    fact = CARD_FACTS[card]
    pct = f'{round(ratio * 100)}%'
    sql = _description_in(os.path.join(HERE, '..', 'src', 'main', 'resources', 'data.sql'), card,
                          r"\(\s*{id},\s*'[^']*',\s*'[^']*',\s*[0-9.]+,\s*'([^']*)'")
    app = _description_in(os.path.join(HERE, '..', '..', 'frontEnd', 'lib', 'models', 'card_info.dart'), card,
                          r"id:\s*{id},.*?description:\s*'([^']*)'")
    ok_text = check(fact.buy_ratio_pct == round(ratio * 100) and '고른 라운드에 즉시' in fact.condition_desc,
                    f'{name}: AI 설명(CARD_FACTS) {fact.condition_desc} / {fact.buy_ratio_pct}%')
    for where, desc in (('서버 DB', sql), ('앱', app)):
        if desc is not None:
            ok_text &= check(f'현금의 {pct}' in desc and '고르는 즉시' in desc, f'{name}: {where} 설명 "{desc}"')

    line = (f'{title} {rnd}R({after["date"]}) {name}: 고르기 전 현금 {cash_before:,.0f}원 × {pct} = {expected:,.0f}원 '
            f'→ 그날 종가 {close:,.2f}에 {bought:,.0f}원 매수 / 설명 "{fact.condition_desc}"')
    print(f'    [즉시 매수 대조] {line}')
    if ok_amount and ok_when and ok_text:
        immediate_buys.append(line)


def check(cond, message):
    if not cond:
        failures.append(message)
        print(f'    [FAIL] {message}')
    return cond


def post(path, body, timeout=60):
    return requests.post(JAVA + path, json=body, timeout=timeout)


def expect_400(path, body, what):
    r = post(path, body)
    ok = r.status_code == 400 and r.json().get('success') is False and r.json().get('message')
    check(ok, f'{what}: 400 + 메시지여야 하는데 {r.status_code} {r.text[:120]}')


def listed_at(price_data, index):
    """그 라운드(0부터)에 가격이 있는 종목 — 상장 전 종목은 Python 쪽에서도 None"""
    return {t for t in TICKERS if price_data['close'][PY_TICKER.get(t, t)][index] is not None}


def check_prices(r, listed):
    """그날 가격이 있는 모든 종목이 TICKERS 순서로 온다 — 갖고 있지 않은 종목도 흐름을 보고 고를 수 있게 (#125)"""
    tickers = [p['ticker'] for p in r['priceData']]
    check(tickers == [t for t in TICKERS if t in listed],
          f'{r["round"]}R 종목 가격 {tickers} (그날 가격이 있는 종목 {sorted(listed)})')
    held = {h['ticker'] for h in r.get('holdings', [])}
    check(held <= set(tickers), f'{r["round"]}R 보유 종목 {held} 중 가격이 없는 종목')


def check_rounds(rounds, expected_from, expected_to, price_data=None):
    numbers = [r['round'] for r in rounds]
    check(numbers == list(range(expected_from, expected_to + 1)),
          f'라운드 범위 {expected_from}~{expected_to}여야 하는데 {numbers[:3]}…{numbers[-3:]}')
    for r in rounds:
        if price_data is not None:
            check_prices(r, listed_at(price_data, r['round'] - 1))
        weight = sum(h['weight'] for h in r['holdings']) + r['cashWeight']
        check(abs(weight - 100.0) < 0.011, f'{r["round"]}R 비중 합 {weight}')
        check(r['roundAsset'] > 0 and isinstance(r['returnRate'], (int, float)), f'{r["round"]}R 자산·수익률 형식')
        for s in r['skippedCards']:
            check(s['reason'] in SKIP_REASONS, f'{r["round"]}R 알 수 없는 건너뜀 사유 {s}')
        both = set(r['triggeredCards']) & {s['cardId'] for s in r['skippedCards']}
        check(not both, f'{r["round"]}R 같은 카드가 발동·건너뜀 양쪽에 있음 {both}')


def play_one(scenario, rng):
    title = scenario['title']
    start = post('/game/start', {'scenarioId': scenario['id']}).json()['data']
    sid = start['sessionId']
    decision_rounds = start['decisionRounds']
    start_date = start['rounds'][0]['date']
    base_ticker = '^NDX' if start['buyMoreTarget'].startswith('나스닥') else '^SPX'
    price_data = load_price_data(start_date)
    print(f'  {title}: 세션 {sid}, 위기 대응 라운드 {decision_rounds}, 시작일 {start_date}')
    check_prices(start['rounds'][0], listed_at(price_data, 0))     # 1라운드도 모든 종목 가격

    check(start['briefing']['intro'], '시작 전 브리핑 배경 설명이 비어 있음')
    check(len(start['briefing']['assets']) >= 2, '시작 전 브리핑 종목 등락이 없음')
    check(all(r not in CARD_SELECT_ROUNDS and 2 <= r <= 99 for r in decision_rounds),
          f'위기 대응 라운드가 카드 선택 라운드와 겹침 {decision_rounds}')

    events = sorted(set(CARD_SELECT_ROUNDS) | set(decision_rounds))
    selections, decisions, all_rounds = {}, {}, []
    options = start['firstCardOptions']
    next_round, next_type = 1, 'CARD'

    # 시작 직후 잘못된 요청
    expect_400('/game/round/action', {'sessionId': sid, 'round': 25, 'cardId': options[0]}, '차례가 아닌 라운드')
    not_offered = next(c for c in range(1, 12) if c not in options)
    expect_400('/game/round/action', {'sessionId': sid, 'round': 1, 'cardId': not_offered}, '제시되지 않은 카드')
    expect_400('/game/round/decision', {'sessionId': sid, 'round': 1, 'choice': 'HOLD'}, '카드 라운드에 위기 대응')
    expect_400('/game/recommend/v2', {'sessionId': sid, 'currentRound': 75}, 'AI 예측 지원하지 않는 라운드')

    for idx, event_round in enumerate(events):
        check(next_round == event_round, f'다음 이벤트 라운드 {event_round} 예상, 응답은 {next_round}')
        end = events[idx + 1] - 1 if idx + 1 < len(events) else 100

        if event_round in CARD_SELECT_ROUNDS:
            check(next_type == 'CARD', f'{event_round}R 이벤트 종류 CARD 예상, 응답은 {next_type}')
            check(len(options) == 3 and not set(options) & set(selections.values()),
                  f'{event_round}R 후보 {options} (보유 {list(selections.values())})')

            if event_round in (25, 50):     # AI 예측: 모델이 있으면 200, 없으면 503
                r = post('/game/recommend/v2', {'sessionId': sid, 'currentRound': event_round,
                                                'alreadyCards': list(selections.values()),
                                                'candidateCards': options})
                if r.status_code == 200:
                    d = r.json()['data']
                    check(d['recommendedCardId'] in options and len(d['rankings']) == 3,
                          f'{event_round}R AI 예측 형식 {d}')
                    check(d['feedback'].startswith('지금 시장:'), f'{event_round}R AI 설명 형식: {d["feedback"][:40]}')
                else:
                    check(r.status_code == 503, f'{event_round}R AI 예측 {r.status_code} {r.text[:100]}')

            # (8) 25·50라운드에 즉시 매수 카드가 나오면 그 카드를 골라 대조한다
            buy_once = [c for c in options if c in BUY_ONCE] if event_round in (25, 50) else []
            card = rng.choice(buy_once) if buy_once else rng.choice(options)
            before = all_rounds[-1] if all_rounds else None
            res = post('/game/round/action', {'sessionId': sid, 'round': event_round, 'cardId': card})
            if not check(res.status_code == 200, f'{event_round}R 카드 선택 실패 {res.status_code} {res.text[:150]}'):
                return
            selections[event_round] = card
            expect_400('/game/round/action', {'sessionId': sid, 'round': event_round, 'cardId': card},
                       '같은 라운드 재선택')
        else:
            check(next_type == 'DECISION', f'{event_round}R 이벤트 종류 DECISION 예상, 응답은 {next_type}')
            expect_400('/game/round/action', {'sessionId': sid, 'round': event_round, 'cardId': 1},
                       '위기 대응 라운드에 카드 선택')
            expect_400('/game/round/decision', {'sessionId': sid, 'round': event_round, 'choice': 'PANIC'},
                       '알 수 없는 위기 대응')
            choice = rng.choice(DECISION_CHOICES)
            res = post('/game/round/decision', {'sessionId': sid, 'round': event_round, 'choice': choice})
            if not check(res.status_code == 200, f'{event_round}R 위기 대응 실패 {res.status_code} {res.text[:150]}'):
                return
            decisions[event_round] = choice

        data = res.json()['data']
        check_rounds(data['rounds'], event_round, end, price_data)
        if event_round in CARD_SELECT_ROUNDS and card in BUY_ONCE and event_round in (25, 50) and before:
            check_immediate_buy(title, event_round, card, before, data['rounds'][0], price_data)
        # (#125) 다음 이벤트 라운드의 그날 시장 — 고르기 전에 보여 주는 날 (AI 예측도 그날 종가까지 본다)
        market, nxt = data.get('nextEventMarket'), data['nextEventRound']
        if nxt is None:
            check(market is None, f'{event_round}R 마지막 이벤트 뒤에는 다음 그날 시장이 없어야 함')
        elif check(market and market['round'] == nxt, f'{event_round}R 다음 이벤트({nxt}R)의 그날 시장이 없음'):
            idx = nxt - 1
            check(market['date'] == str(price_data['dates'][idx])[:10],
                  f'{nxt}R 그날 시장 날짜 {market["date"]} (가격 데이터 {price_data["dates"][idx]})')
            check('roundAsset' not in market, f'{nxt}R 그날 시장에 고르기 전 자산이 들어 있음')
            check_prices(market, listed_at(price_data, idx))
        all_rounds += data['rounds']
        next_round, next_type = data['nextEventRound'], data['nextEventType']
        options = data['nextCardOptions'] or []
        if next_type == 'DECISION':
            check(data['nextDecision'] and data['nextDecision']['news']['headline'],
                  f'{next_round}R 위기 대응 속보가 없음')

    check(next_round is None, f'마지막 이벤트 뒤에는 다음 이벤트가 없어야 함 ({next_round})')
    check(len(all_rounds) == 100, f'전체 라운드 수 {len(all_rounds)}')
    expect_400('/game/round/action', {'sessionId': sid, 'round': 100, 'cardId': 1}, '끝난 게임에 선택')

    # 4) Python과 라운드별 자산 비교
    py = run_game(start_date, selections, price_data=price_data,
                  decisions=decisions, base_ticker=base_ticker)
    java_assets = [r['roundAsset'] for r in all_rounds]
    py_assets = [r['roundAsset'] for r in py['rounds']]
    diff = next((i + 1 for i, (a, b) in enumerate(zip(java_assets, py_assets)) if a != b), None)
    check(diff is None, f'Java·Python 라운드별 자산이 {diff}R부터 다름 '
                        f'(Java {java_assets[diff - 1] if diff else ""}, Python {py_assets[diff - 1] if diff else ""})')
    java_trig = [sorted(r['triggeredCards']) for r in all_rounds]
    py_trig = [sorted(r['triggeredCards']) for r in py['rounds']]
    check(java_trig == py_trig, 'Java·Python 발동 카드 기록이 다름')
    java_skip = [sorted((s['cardId'], s['reason']) for s in r['skippedCards']) for r in all_rounds]
    py_skip = [sorted((s['cardId'], s['reason']) for s in r['skippedCards']) for r in py['rounds']]
    check(java_skip == py_skip, 'Java·Python 건너뜀 기록이 다름')

    # 5) 사후 분석
    res = post('/game/result/analysis', {'sessionId': sid})
    a = res.json().get('data')
    if check(res.status_code == 200 and a, f'사후 분석 실패 {res.status_code} {res.text[:150]}'):
        final = all_rounds[-1]
        p = a['playerResult']
        check(p['finalAsset'] == final['roundAsset'],
              f'사후 분석의 내 결과 {p["finalAsset"]} ≠ 실제 게임 결과 {final["roundAsset"]}')
        check(a['grade'] in GRADES, f'등급 {a["grade"]}')
        check(1 <= p['rank'] <= a['totalCombinations'], f'순위 {p["rank"]}/{a["totalCombinations"]}')
        check(a['offeredAnalysis'] and a['offeredAnalysis']['playerResult']['finalAsset'] == final['roundAsset'],
              '받은 후보 안 분석의 내 결과가 실제와 다름')
        check(len(a['cardReport']) == 4 and all(c['cardName'] for c in a['cardReport']), '카드별 성적표 4장')
        check(a['risk']['playerMdd'] <= 0 and a['risk']['marketMdd'] <= 0, f'최대 낙폭 {a["risk"]}')
        dr = a['decisionReview']
        if decisions:
            check(dr and [d['round'] for d in dr['rounds']] == sorted(decisions),
                  f'위기 대응 돌아보기 라운드 {dr and [d["round"] for d in dr["rounds"]]}')
            check(dr and all(d['headline'] and len(d['alternatives']) == 2 for d in dr['rounds']),
                  '위기 대응 돌아보기: 속보·다른 선택 2개')
        else:
            check(dr is None, '위기 대응이 없는데 돌아보기가 있음')
        print(f'    결과 {final["roundAsset"]:,}원 ({final["returnRate"]:+.2f}%), '
              f'{p["rank"]}위/{a["totalCombinations"]} 등급 {a["grade"]}, 위기 대응 {decisions}')

    # 6) AI 코치
    res = post('/game/result/coach', {'sessionId': sid})
    c = res.json().get('data')
    if check(res.status_code == 200 and c, f'AI 코치 실패 {res.status_code} {res.text[:150]}'):
        heads = [line.split(':')[0] for line in c['comment'].split('\n')]
        check(heads[0] == '요약' and heads[-1] == '다음엔', f'AI 코치 줄 머리말 {heads}')
        check(c['status'] in ('llm', 'fallback', 'failed'), f'AI 코치 상태 {c["status"]}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--games', type=int, default=2, help='시나리오당 판 수')
    ap.add_argument('--seed', type=int, default=1)
    args = ap.parse_args()
    rng = random.Random(args.seed)

    try:
        scenarios = requests.get(JAVA + '/game/scenarios', timeout=10).json()['data']
    except Exception as e:
        print(f'게임 서버 호출 실패: {e}\nSpring Boot(8080)가 켜져 있는지 확인하세요.')
        sys.exit(1)

    # 빈 요청·형식이 틀린 요청
    expect_400('/game/start', {}, '빈 게임 시작 요청')
    expect_400('/game/start', {'scenarioId': 999}, '없는 시나리오')
    expect_400('/game/start', {'scenarioId': 'abc'}, '숫자가 아닌 scenarioId')
    expect_400('/game/round/action', {'sessionId': 'no-such', 'round': 1, 'cardId': 1}, '없는 세션')
    expect_400('/game/result/analysis', {}, '세션 없는 분석 요청')

    for scenario in scenarios:
        for _ in range(args.games):
            play_one(scenario, rng)

    # (8) 25·50라운드 즉시 매수 대조를 한 번도 못 했으면 (후보에 안 나옴) 판을 더 진행
    extra = 0
    while not immediate_buys and extra < 12:
        play_one(scenarios[extra % len(scenarios)], rng)
        extra += 1
    check(immediate_buys, '25·50라운드 즉시 매수 카드 대조를 한 번도 하지 못함')

    print('=' * 60)
    if failures:
        print(f'실패 {len(failures)}건')
        for f in failures[:20]:
            print(f'  - {f}')
        sys.exit(1)
    print(f'통과: 시나리오 {len(scenarios)}개 × {args.games}판, 즉시 매수 대조 {len(immediate_buys)}건')
    for line in immediate_buys:
        print(f'  - {line}')


if __name__ == '__main__':
    main()
