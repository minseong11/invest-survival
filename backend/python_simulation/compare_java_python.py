"""
compare_java_python.py — Python(run_game)과 Java(/game/validate) 최종 자산 차이 측정

같은 카드 조합을 Python game_logic.run_game()과 Java POST /game/validate로 각각 실행해
최종 자산과 라운드별 자산이 같은지 확인한다.
  - Python: 사후 분석 순위·학습 데이터의 기준 (backtest.py, monte_carlo_v2.py)
  - Java  : 실제 게임 결과의 기준
(#125) Python이 Java와 같은 연산 순서·버림으로 계산하므로 기대값은 "모든 조합에서 차이 0원"이다.
       조합의 절반에는 무작위 위기 대응(버틴다/절반 판다/더 산다)을 넣어 그 계산도 함께 비교한다.

추가로, 종목 가격이 SPX 거래일 기준으로 제대로 정렬되었는지도 점검한다.
(그날 거래가 없으면 직전 거래일 가격, 상장 전이면 가격 없음)

사용법:
    cd backend/python_simulation
    python3 compare_java_python.py              # 시나리오당 500개
    python3 compare_java_python.py --n 7920     # 전수 (오래 걸림)
    python3 compare_java_python.py --strict     # 차이가 하나라도 있으면 종료 코드 1 (CI용)
    python3 compare_java_python.py --no-report  # compare_report.md를 쓰지 않음

사전 조건: Spring Boot(8080) 실행 중. FastAPI는 필요 없음.
"""
import argparse
import os
import random
import sys
import time
from datetime import datetime
from itertools import permutations

import requests

import data_loader
from game_logic import (run_game, load_price_data, available_card_ids,
                        CARDS, CARD_SELECT_ROUNDS, TICKERS, DECISION_CHOICES, GAME_ROUNDS)

JAVA_URL = os.environ.get('JAVA_URL', 'http://localhost:8080') + '/game/validate'

# data.sql 시나리오 (시작일, '더 산다'에서 사는 기준 지수). Java/Python 모두 시작일 이후 첫 거래일부터 시작
SCENARIOS = [
    ('리먼', '2008-09-01', '^SPX'),
    ('닷컴', '2000-03-01', '^NDX'),
    ('코로나', '2020-02-19', '^SPX'),
]

# 판단 기준 (#125): 모든 조합·모든 라운드에서 차이 0원
REPORT_PATH = 'compare_report.md'

# 위기 대응을 넣을 수 있는 라운드 (2~99 중 카드 선택 라운드 제외)
DECISION_ROUND_POOL = [r for r in range(2, GAME_ROUNDS) if r not in CARD_SELECT_ROUNDS]


def random_decisions(rng):
    """무작위 위기 대응 1~3개 {라운드: 선택}"""
    rounds = rng.sample(DECISION_ROUND_POOL, rng.randint(1, 3))
    return {r: rng.choice(DECISION_CHOICES) for r in sorted(rounds)}


def data_label():
    """비교에 쓴 주가 데이터가 무엇인지 (리포트에 남김)"""
    marker = os.path.join(data_loader.DATA_DIR, 'FIXTURE_DATA.txt')
    if os.path.exists(marker):
        return '테스트용 대체 데이터 (tests/make_fixture_data.py로 만든 가상의 주가 — 실제 주가 아님)'
    return os.environ.get('SURVIVAL_DATA_LABEL', '실제 주가 CSV (backend/data)')


def call_java(start_date, selection, decisions=None, base_ticker='^SPX'):
    """Java /game/validate 호출 → (최종 자산, 라운드별 자산 리스트)"""
    body = {
        'startDate': start_date,
        'cardSelections': {str(r): c for r, c in selection.items()},
        'decisions': {str(r): c for r, c in (decisions or {}).items()},
        'baseTicker': base_ticker,
    }
    resp = requests.post(JAVA_URL, json=body, timeout=30)
    resp.raise_for_status()
    data = resp.json()['data']
    rounds = [int(r['roundAsset']) for r in data['rounds']]
    return int(data['final_asset']), rounds


def first_diverging_round(py_rounds, java_rounds, tol=0):
    """라운드별 자산이 처음으로 tol원 넘게 달라지는 라운드 (없으면 None). 길이가 다르면 짧은 쪽 다음 라운드"""
    if len(py_rounds) != len(java_rounds):
        return min(len(py_rounds), len(java_rounds)) + 1
    for i, (p, j) in enumerate(zip(py_rounds, java_rounds)):
        if abs(p - j) > tol:
            return i + 1
    return None


def count_rank_inversions(py_assets, java_assets):
    """
    두 조합 쌍 (i, j)에 대해 Python에서의 대소 관계와 Java에서의 대소 관계가 다른 쌍의 수.
    - inverted: 한쪽은 i > j, 다른 쪽은 i < j (순위 역전)
    - tie_mismatch: 한쪽은 동점, 다른 쪽은 동점이 아님 (동률 묶기 결과가 달라짐)
    """
    n = len(py_assets)
    inverted = 0
    tie_mismatch = 0
    for i in range(n):
        for j in range(i + 1, n):
            dp = py_assets[i] - py_assets[j]
            dj = java_assets[i] - java_assets[j]
            if dp * dj < 0:
                inverted += 1
            elif (dp == 0) != (dj == 0):
                tie_mismatch += 1
    total_pairs = n * (n - 1) // 2
    return inverted, tie_mismatch, total_pairs


def check_date_alignment(start_date):
    """
    load_price_data()가 종목 가격을 SPX 거래일 기준으로 제대로 맞췄는지 첫 100라운드에서 점검.
    원본 CSV에서 "그 날짜 또는 직전 거래일" 종가를 따로 계산해 load_price_data() 결과와 비교한다.
    """
    import pandas as pd
    from data_loader import load_all

    pdata = load_price_data(start_date)
    spx_dates = pdata['dates'][:100]
    all_data = load_all()
    rows = []
    for t in TICKERS:
        values = pdata['close'][t][:100]
        df = all_data.get(t, pd.DataFrame())
        raw_first = str(df['Date'].iloc[0])[:10] if not df.empty else '-'
        raw = df.set_index('Date')['Close'].astype(float) if not df.empty else pd.Series(dtype=float)
        same_day = prev_day = not_listed = mismatch = 0
        for d, v in zip(spx_dates, values):
            ts = pd.Timestamp(d)
            past = raw[raw.index <= ts]
            if past.empty:
                expected = None
                not_listed += 1
            else:
                expected = float(past.iloc[-1])
                if past.index[-1] == ts:
                    same_day += 1
                else:
                    prev_day += 1
            if expected is None or v is None:
                if expected is not v:          # 한쪽만 None이면 불일치 (결측을 0으로 바꾸면 여기서 잡힘)
                    mismatch += 1
            elif abs(expected - v) > 1e-9:
                mismatch += 1
        rows.append((t, raw_first, same_day, prev_day, not_listed, mismatch))
    return spx_dates[0] if spx_dates else '-', rows


def run(n, seed, write=True):
    """반환: 모든 시나리오에서 차이·오류가 없으면 True"""
    all_combos = list(permutations(sorted(CARDS.keys()), 4))
    rng = random.Random(seed)
    results = {}       # 시나리오 이름 → 집계
    alignment = {}     # 시나리오 이름 → 날짜 점검 결과

    # Java 서버 연결 확인
    try:
        call_java(SCENARIOS[0][1], dict(zip(CARD_SELECT_ROUNDS, all_combos[0])))
    except Exception as e:
        print(f'Java 서버 호출 실패: {e}\nSpring Boot(8080)가 켜져 있는지 확인하세요.')
        return False

    for name, start_date, base_ticker in SCENARIOS:
        print(f'\n=== {name} ({start_date}) ===')
        alignment[name] = check_date_alignment(start_date)

        price_data = load_price_data(start_date)
        pool = available_card_ids(price_data)            # 상장 전 종목 카드 제외
        scenario_combos = list(permutations(pool, 4))
        combos = scenario_combos if n >= len(scenario_combos) else rng.sample(scenario_combos, n)
        print(f'  사용 가능 카드 {len(pool)}장, 조합 {len(scenario_combos)}개 중 {len(combos)}개 비교')

        rows = []   # (combo, py_asset, java_asset, diff, rel_pct, first_div_round, decisions)
        errors = 0
        with_decisions = 0
        t0 = time.time()
        for k, combo in enumerate(combos, 1):
            sel = dict(zip(CARD_SELECT_ROUNDS, combo))
            # 절반은 카드만, 절반은 무작위 위기 대응 포함
            decisions = random_decisions(rng) if k % 2 == 0 else {}
            with_decisions += bool(decisions)
            py = run_game(start_date, sel, price_data=price_data, decisions=decisions, base_ticker=base_ticker)
            py_asset = int(py['final_asset'])
            py_rounds = [int(r['roundAsset']) for r in py['rounds']]
            try:
                java_asset, java_rounds = call_java(start_date, sel, decisions, base_ticker)
            except Exception as e:
                errors += 1
                if errors <= 3:
                    print(f'  [Java 오류] {combo}: {e}')
                continue
            diff = java_asset - py_asset
            rel = diff / py_asset * 100 if py_asset else 0.0
            rows.append((combo, py_asset, java_asset, diff, rel,
                         first_diverging_round(py_rounds, java_rounds), decisions))
            if k % 50 == 0:
                print(f'  {k}/{len(combos)} ({time.time() - t0:.0f}초)')

        if not rows:
            results[name] = None
            continue

        abs_diffs = [abs(r[3]) for r in rows]
        abs_rels = [abs(r[4]) for r in rows]
        inverted, tie_mismatch, total_pairs = count_rank_inversions(
            [r[1] for r in rows], [r[2] for r in rows])

        results[name] = {
            'start_date': start_date,
            'n': len(rows),
            'with_decisions': with_decisions,
            'round_mismatch': sum(1 for r in rows if r[5] is not None),   # 라운드별 자산이 한 번이라도 다른 조합 수
            'errors': errors,
            'zero_ratio': sum(1 for d in abs_diffs if d == 0) / len(rows) * 100,
            'mean_abs': sum(abs_diffs) / len(rows),
            'max_abs': max(abs_diffs),
            'max_rel': max(abs_rels),
            'java_lower_ratio': sum(1 for r in rows if r[3] < 0) / len(rows) * 100,
            'inverted': inverted,
            'tie_mismatch': tie_mismatch,
            'total_pairs': total_pairs,
            'worst': sorted(rows, key=lambda r: -abs(r[3]))[:5],
            'elapsed': time.time() - t0,
        }
        s = results[name]
        print(f'  완료: 평균 |차이| {s["mean_abs"]:.1f}원, 최대 {s["max_abs"]:,}원 '
              f'({s["max_rel"]:.5f}%), 라운드별 불일치 {s["round_mismatch"]}개, '
              f'순위 역전 {inverted}쌍 / 동률 불일치 {tie_mismatch}쌍')

    ok_all = all_passed(results)
    print(f'\n판단: {"통과 — 모든 조합에서 차이 0원" if ok_all else "실패 — 차이가 있는 조합이 있음"}')
    if write:
        write_report(results, alignment, n, seed, ok_all)
    return ok_all


def scenario_passed(s) -> bool:
    return (s is not None and s['max_abs'] == 0 and s['round_mismatch'] == 0
            and s['inverted'] == 0 and s['tie_mismatch'] == 0 and s['errors'] == 0)


def all_passed(results) -> bool:
    return bool(results) and all(scenario_passed(s) for s in results.values())


def write_report(results, alignment, n, seed, ok_all):
    lines = ['# Python·Java 게임 계산 일치 확인', '',
             f'- 생성 시각: {datetime.now().isoformat(timespec="seconds")}',
             f'- 주가 데이터: {data_label()}',
             f'- 시나리오당 조합 수: {n} (시드 {seed}), 그중 절반은 무작위 위기 대응(버틴다/절반 판다/더 산다) 1~3개 포함',
             '- Python: game_logic.run_game() / Java: POST /game/validate',
             '- 두 계산은 같은 연산 순서·버림(현금은 원 단위 정수, 매매 금액 소수점 아래 버림)을 쓴다 (#125)',
             '- 차이 = Java 최종 자산 − Python 최종 자산', '']

    lines += ['## 1. 요약', '',
              '| 시나리오 | 조합 수 (위기 대응 포함) | 차이 0 비율 | 최대 절대 차이 | 라운드별 자산이 다른 조합 | 순위 역전 쌍 | 동률 불일치 쌍 | Java 호출 오류 |',
              '|---|---|---|---|---|---|---|---|']
    for name, s in results.items():
        if s is None:
            lines.append(f'| {name} | 실패 | | | | | | |')
            continue
        lines.append(
            f'| {name} ({s["start_date"]}) | {s["n"]} ({s["with_decisions"]}) | {s["zero_ratio"]:.1f}% | '
            f'{s["max_abs"]:,}원 | {s["round_mismatch"]} | '
            f'{s["inverted"]:,} / {s["total_pairs"]:,} | {s["tie_mismatch"]:,} | {s["errors"]} |')
    lines += ['', '**판단 기준**: 모든 조합에서 최종 자산 차이 0원, 100라운드 모든 라운드의 자산 일치, 순위 역전·동률 불일치 0쌍, Java 호출 오류 0건',
              f'**판단**: {"통과 — 두 계산이 원 단위까지 같음" if ok_all else "실패 — 아래 상세 확인 후 원인 분석 필요"}', '']

    lines += ['## 2. 차이가 있는 조합 (시나리오별 최대 5개)', '']
    for name, s in results.items():
        if s is None:
            continue
        bad = [r for r in s['worst'] if r[3] != 0 or r[5] is not None]
        lines += [f'### {name}', '']
        if not bad:
            lines += ['차이가 있는 조합 없음', '']
            continue
        lines += ['| 조합 (1/25/50/75R) | 위기 대응 | Python | Java | 차이 | 상대 차이 | 처음 달라진 라운드 |',
                  '|---|---|---|---|---|---|---|']
        for combo, py, jv, d, rel, fr, dec in bad:
            names = ' → '.join(CARDS[c]['name'] for c in combo)
            dec_text = ', '.join(f'{r}R {c}' for r, c in dec.items()) or '-'
            lines.append(f'| {names} | {dec_text} | {py:,} | {jv:,} | {d:+,} | {rel:+.5f}% | {fr if fr else "-"} |')
        if s['errors']:
            lines.append(f'\nJava 호출 오류: {s["errors"]}건')
        lines.append('')

    lines += ['## 3. 종목별 날짜 정렬 점검 (첫 100라운드)', '',
              '라운드 기준 날짜는 SPX 거래일. 각 종목은 그 날짜의 종가, 그날 거래가 없으면 직전 거래일 종가, '
              '그 이전 데이터가 없으면(상장 전) 가격 없음(None)으로 둔다(0으로 바꾸지 않음). 원본 CSV로 따로 계산한 값과 load_price_data() 결과를 비교한다.', '']
    for name, (spx_first, rows) in alignment.items():
        bad = sum(r[5] for r in rows)
        lines += [f'### {name} (SPX 첫 거래일 {spx_first}) — 정렬 검증 {"통과" if bad == 0 else f"실패 {bad}건"}', '',
                  '| 종목 | 원본 첫 날짜 | 그날 가격 | 직전 거래일 가격 | 상장 전(가격 없음) | 불일치 |', '|---|---|---|---|---|---|']
        for t, first, same, prev, nl, mm in rows:
            lines.append(f'| {t} | {first} | {same} | {prev} | {nl} | {mm} |')
        lines.append('')

    with open(REPORT_PATH, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
    print(f'\n리포트 저장: {REPORT_PATH}')


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--n', type=int, default=500, help='시나리오당 조합 수 (7920 이상이면 전수)')
    ap.add_argument('--seed', type=int, default=42)
    ap.add_argument('--strict', action='store_true', help='차이가 하나라도 있으면 종료 코드 1 (CI용)')
    ap.add_argument('--no-report', action='store_true', help='compare_report.md를 쓰지 않음')
    args = ap.parse_args()
    passed = run(args.n, args.seed, write=not args.no_report)
    if args.strict and not passed:
        sys.exit(1)
