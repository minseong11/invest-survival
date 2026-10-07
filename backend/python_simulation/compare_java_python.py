"""
compare_java_python.py — Python(run_game)과 Java(/game/validate) 최종 자산 차이 측정

같은 카드 조합을 Python game_logic.run_game()과 Java POST /game/validate로 각각 실행해
최종 자산이 얼마나 다른지 측정한다.
  - Python: float로 계산 (backtest.py 사후 분석 순위의 기준)
  - Java  : 매수/매도마다 long으로 버림 (실제 게임 결과의 기준)

추가로, 종목 가격이 SPX 거래일 기준으로 제대로 정렬되었는지도 점검한다.
(그날 거래가 없으면 직전 거래일 가격, 상장 전이면 가격 없음)

사용법:
    cd backend/python_simulation
    python3 compare_java_python.py              # 시나리오당 500개
    python3 compare_java_python.py --n 7920     # 전수 (오래 걸림)

사전 조건: Spring Boot(8080) 실행 중. FastAPI는 필요 없음.
"""
import argparse
import random
import time
from datetime import datetime
from itertools import permutations

import requests

from data_loader import get_price_list
from game_logic import run_game, load_price_data, CARDS, CARD_SELECT_ROUNDS, TICKERS

JAVA_URL = 'http://localhost:8080/game/validate'

# data.sql 시나리오 시작일 (Java/Python 모두 이 날짜 이후 첫 거래일부터 시작)
SCENARIOS = [
    ('리먼', '2008-09-01'),
    ('닷컴', '2000-03-01'),
    ('코로나', '2020-02-19'),
]

# 판단 기준 (이슈에 적은 제안값)
MAX_REL_DIFF_PCT = 0.01   # 최대 상대 차이 0.01% 미만
REPORT_PATH = 'compare_report.md'


def call_java(start_date, selection):
    """Java /game/validate 호출 → (최종 자산, 라운드별 자산 리스트)"""
    body = {
        'startDate': start_date,
        'cardSelections': {str(r): c for r, c in selection.items()},
    }
    resp = requests.post(JAVA_URL, json=body, timeout=30)
    resp.raise_for_status()
    data = resp.json()['data']
    rounds = [int(r['roundAsset']) for r in data['rounds']]
    return int(data['final_asset']), rounds


def first_diverging_round(py_rounds, java_rounds, tol=1):
    """라운드별 자산이 처음으로 tol원 넘게 달라지는 라운드 (없으면 None)"""
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
                expected = 0.0
                not_listed += 1
            else:
                expected = float(past.iloc[-1])
                if past.index[-1] == ts:
                    same_day += 1
                else:
                    prev_day += 1
            if abs(expected - v) > 1e-9:
                mismatch += 1
        rows.append((t, raw_first, same_day, prev_day, not_listed, mismatch))
    return spx_dates[0] if spx_dates else '-', rows


def run(n, seed):
    all_combos = list(permutations(sorted(CARDS.keys()), 4))
    rng = random.Random(seed)
    results = {}       # 시나리오 이름 → 집계
    alignment = {}     # 시나리오 이름 → 날짜 점검 결과

    # Java 서버 연결 확인
    try:
        call_java(SCENARIOS[0][1], dict(zip(CARD_SELECT_ROUNDS, all_combos[0])))
    except Exception as e:
        print(f'Java 서버 호출 실패: {e}\nSpring Boot(8080)가 켜져 있는지 확인하세요.')
        return

    for name, start_date in SCENARIOS:
        print(f'\n=== {name} ({start_date}) ===')
        alignment[name] = check_date_alignment(start_date)

        price_data = load_price_data(start_date)
        combos = all_combos if n >= len(all_combos) else rng.sample(all_combos, n)

        rows = []   # (combo, py_asset, java_asset, diff, rel_pct, first_div_round)
        errors = 0
        t0 = time.time()
        for k, combo in enumerate(combos, 1):
            sel = dict(zip(CARD_SELECT_ROUNDS, combo))
            py = run_game(start_date, sel, price_data=price_data)
            py_asset = int(py['final_asset'])
            py_rounds = [int(r['roundAsset']) for r in py['rounds']]
            try:
                java_asset, java_rounds = call_java(start_date, sel)
            except Exception as e:
                errors += 1
                if errors <= 3:
                    print(f'  [Java 오류] {combo}: {e}')
                continue
            diff = java_asset - py_asset
            rel = diff / py_asset * 100 if py_asset else 0.0
            rows.append((combo, py_asset, java_asset, diff, rel,
                         first_diverging_round(py_rounds, java_rounds)))
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
              f'({s["max_rel"]:.5f}%), 순위 역전 {inverted}쌍 / 동률 불일치 {tie_mismatch}쌍')

    write_report(results, alignment, n, seed)


def write_report(results, alignment, n, seed):
    lines = ['# Python·Java 게임 계산 최종 자산 차이 측정', '',
             f'- 생성 시각: {datetime.now().isoformat(timespec="seconds")}',
             f'- 시나리오당 조합 수: {n} (시드 {seed})',
             '- Python: game_logic.run_game() (float) / Java: POST /game/validate (매수·매도마다 long 버림)',
             '- 차이 = Java 최종 자산 − Python 최종 자산', '']

    lines += ['## 1. 요약', '',
              '| 시나리오 | 조합 수 | 차이 0 비율 | 평균 절대 차이 | 최대 절대 차이 | 최대 상대 차이 | Java가 더 낮은 비율 | 순위 역전 쌍 | 동률 불일치 쌍 |',
              '|---|---|---|---|---|---|---|---|---|']
    ok_all = True
    for name, s in results.items():
        if s is None:
            lines.append(f'| {name} | 실패 | | | | | | | |')
            ok_all = False
            continue
        lines.append(
            f'| {name} ({s["start_date"]}) | {s["n"]} | {s["zero_ratio"]:.1f}% | {s["mean_abs"]:.1f}원 | '
            f'{s["max_abs"]:,}원 | {s["max_rel"]:.5f}% | {s["java_lower_ratio"]:.1f}% | '
            f'{s["inverted"]:,} / {s["total_pairs"]:,} | {s["tie_mismatch"]:,} |')
        if s['max_rel'] >= MAX_REL_DIFF_PCT or s['inverted'] > 0 or s['errors'] > 0:
            ok_all = False
    lines += ['', f'**판단 기준**: 최대 상대 차이 {MAX_REL_DIFF_PCT}% 미만, 순위 역전 0쌍, Java 호출 오류 0건',
              f'**판단**: {"무시 가능 — 보고서에 수치만 기록" if ok_all else "기준 초과 — 아래 상세 확인 후 원인 분석 필요"}', '']

    lines += ['## 2. 차이가 큰 조합 (시나리오별 상위 5개)', '']
    for name, s in results.items():
        if s is None:
            continue
        lines += [f'### {name}', '',
                  '| 조합 (1/25/50/75R) | Python | Java | 차이 | 상대 차이 | 처음 1원 넘게 달라진 라운드 |',
                  '|---|---|---|---|---|---|']
        for combo, py, jv, d, rel, fr in s['worst']:
            names = ' → '.join(CARDS[c]['name'] for c in combo)
            lines.append(f'| {names} | {py:,} | {jv:,} | {d:+,} | {rel:+.5f}% | {fr if fr else "-"} |')
        if s['errors']:
            lines.append(f'\nJava 호출 오류: {s["errors"]}건')
        lines.append('')

    lines += ['## 3. 종목별 날짜 정렬 점검 (첫 100라운드)', '',
              '라운드 기준 날짜는 SPX 거래일. 각 종목은 그 날짜의 종가, 그날 거래가 없으면 직전 거래일 종가, '
              '그 이전 데이터가 없으면(상장 전) 0을 사용한다. 원본 CSV로 따로 계산한 값과 load_price_data() 결과를 비교한다.', '']
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
    args = ap.parse_args()
    run(args.n, args.seed)
