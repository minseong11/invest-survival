"""
e2e_game_flow.py — 실제 게임 흐름을 API로 끝까지 진행하며 확인 (#125)

Spring Boot(8080)와 FastAPI(8000)가 켜진 상태에서, 시나리오마다 게임을 시작해
카드 선택·위기 대응을 무작위로 고르며 100라운드까지 진행하고 아래를 확인한다.
  1) 이벤트 순서: 카드 선택(1·25·50·75) + 위기 대응 라운드에서만 멈추고, 1~100라운드가 빠짐없이 온다
  2) 라운드 응답: 자산·수익률, 보유 자산 비중 + 현금 비중 = 100%, 발동·건너뜀 정보
  3) 잘못된 요청은 400 (같은 라운드 재선택, 제시되지 않은 카드, 위기 대응 라운드에 카드 선택, 빈 요청 등)
  4) 실제 게임의 라운드별 자산 = Python run_game(같은 카드·같은 위기 대응)의 라운드별 자산 (원 단위까지)
  5) 사후 분석: 내 결과가 실제 게임 결과와 같고, 등급·최대 낙폭·카드별 성적표·위기 대응 돌아보기가 온다
  6) AI 코치 한마디가 온다 (LLM이 실패해도 규칙 기반 문장)
  7) AI 예측: 25·50라운드는 응답(모델 파일이 없으면 503), 그 외 라운드는 400

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

import requests

from game_logic import run_game, load_price_data, CARD_SELECT_ROUNDS, DECISION_CHOICES

JAVA = os.environ.get('JAVA_URL', 'http://localhost:8080')
GRADES = {'S', 'A', 'B', 'C', 'D'}
SKIP_REASONS = {'CASH_LOW', 'MAX_REACHED', 'NO_HOLDINGS', 'NO_PRICE'}

failures = []


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


def check_rounds(rounds, expected_from, expected_to):
    numbers = [r['round'] for r in rounds]
    check(numbers == list(range(expected_from, expected_to + 1)),
          f'라운드 범위 {expected_from}~{expected_to}여야 하는데 {numbers[:3]}…{numbers[-3:]}')
    for r in rounds:
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
    print(f'  {title}: 세션 {sid}, 위기 대응 라운드 {decision_rounds}, 시작일 {start_date}')

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

            card = rng.choice(options)
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
        check_rounds(data['rounds'], event_round, end)
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
    py = run_game(start_date, selections, price_data=load_price_data(start_date),
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

    print('=' * 60)
    if failures:
        print(f'실패 {len(failures)}건')
        for f in failures[:20]:
            print(f'  - {f}')
        sys.exit(1)
    print(f'통과: 시나리오 {len(scenarios)}개 × {args.games}판')


if __name__ == '__main__':
    main()
