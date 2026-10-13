"""
eval_test_period.py — 테스트 기간(2019~2024) 정답 + 유사 구간 백테스팅 (+ V2 예측) 생성

7주차 비교 실험용. 테스트 기간의 각 시점(25·50라운드)에서
  1) 정답        : 실제 백테스팅으로 구한 카드별 기여도와 순위 (채점 기준)
  2) 유사 구간   : 2018년까지의 과거에서 시장 상황이 비슷했던 구간을 찾아, 그때의 카드 기여도를 평균 낸 순위
  3) V2 (선택)   : model_v2_A.pkl이 있으면 같은 입력으로 V2 예측 순위
를 계산하고, 2)·3)을 1)과 비교(스피어만, 3장 중 1위 적중률)한다.

카드 결과 정의 — V2 학습 데이터(monte_carlo_v2.run_chunk)와 동일
  - 이미 고른 카드(alreadyCards)는 고정, 이후 라운드(50·75) 카드는 무작위로 고정한 "나머지 카드 세트"를 만든다
  - 그 세트에서 r 자리에 가능한 후보(전체 − 이미 고른 카드 − 이후 라운드 카드)를 하나씩 넣어 run_game
  - 기여도 = 그 후보의 최종 수익률 − 같은 세트 후보들의 평균 수익률
  - 나머지 카드 세트 하나만 쓰면 노이즈가 커서, 세트를 N_REST_SETS개 바꿔가며 카드별 평균을 낸다
시장 지표(so_far)는 monte_carlo_v2.calc_spx_so_far(closes[:r])를 그대로 사용한다 (V2 입력과 동일 공식).

정보 누설 방지 (교수님 조건)
  - 유사 구간 검색은 추천 시점(r라운드)까지의 SPX 정보만 사용
  - 검색 대상 과거 구간은 100라운드 전체가 2018-12-31 안에서 끝나는 구간만 (시작 2006-04-10 이후, USO 상장일)
  - 지표 표준화(평균·표준편차)도 학습 구간 데이터로만 계산
  - 2019~2024 가격은 정답(채점)에만 사용
  - 후보 카드·추천 시점·결과 정의는 V2와 동일

사용법:
    cd backend/python_simulation
    python3 eval_test_period.py              # 전체 (약 70개 시작일 × 2라운드 × 3세트)
    python3 eval_test_period.py --quick      # 빠른 점검 (시작일 5개)
출력:
    ../data/simulation/eval_results.csv     # 시점 × 카드별 정답/유사 구간/V2 값
    ../data/simulation/eval_neighbors.csv   # 시점별로 선택된 과거 구간
    ../data/simulation/eval_summary.md      # 요약 (스피어만, 1위 적중률, 누설 점검)
"""
import argparse
import csv
import os
import pickle
import random
import time
from collections import defaultdict
from datetime import datetime
from itertools import combinations

import numpy as np
import pandas as pd
from scipy.stats import spearmanr

from data_loader import load_all
from game_logic import run_game, load_price_data, available_card_ids, CARDS, CARD_SELECT_ROUNDS
from monte_carlo_v2 import calc_spx_so_far          # V2 학습 데이터와 같은 지표 공식
from evaluate_v2 import make_feature                # V2 학습과 같은 입력 벡터 순서

# ── 기간 설정 ──────────────────────────────────────────────
TRAIN_START     = '2006-04-10'   # 유사 구간 검색 시작 (USO 상장일 — 모든 카드 사용 가능)
TRAIN_LAST_DATE = '2018-12-31'   # 유사 구간 100라운드가 이 날짜 안에서 끝나야 함
TEST_FIRST      = '2019-01-02'   # 테스트 첫 시작일
TEST_LAST_DATE  = '2024-12-31'   # 테스트 게임 100라운드가 이 날짜 안에서 끝나야 함
ROUNDS          = 100
EVAL_ROUNDS     = [25, 50]       # V2 추천 시점

DATA_DIR    = os.path.join(os.path.dirname(__file__), '..', 'data', 'simulation')
MODEL_PATH  = os.path.join(DATA_DIR, 'model_v2_A.pkl')
OUT_RESULTS = os.path.join(DATA_DIR, 'eval_results.csv')
OUT_NEIGH   = os.path.join(DATA_DIR, 'eval_neighbors.csv')
OUT_SUMMARY = os.path.join(DATA_DIR, 'eval_summary.md')


# =============================================
# 공통: 카드 기여도 (V2 학습 데이터와 같은 정의)
# =============================================
_price_cache = {}


def get_price_data(start_date: str) -> dict:
    if start_date not in _price_cache:
        _price_cache[start_date] = load_price_data(start_date)
    return _price_cache[start_date]


def card_contributions(start_date: str, r: int, already: list, rng: random.Random, n_sets: int) -> dict:
    """
    start_date 게임의 r라운드에서 카드별 평균 기여도.
    already: r 이전 라운드에 고른 카드 (라운드 순서대로)
    반환: {카드ID: 평균 기여도(%p)}
    """
    price_data = get_price_data(start_date)
    pool = available_card_ids(price_data)
    rounds_before = [x for x in CARD_SELECT_ROUNDS if x < r]
    rounds_after = [x for x in CARD_SELECT_ROUNDS if x > r]
    fixed_before = dict(zip(rounds_before, already))
    rest_pool = [c for c in pool if c not in already]

    contribs = defaultdict(list)
    for _ in range(n_sets):
        later = rng.sample(rest_pool, len(rounds_after))           # 이후 라운드 카드 무작위 고정
        sel_after = dict(zip(rounds_after, later))
        candidates = [c for c in rest_pool if c not in later]       # 이번 라운드 후보
        rets = {}
        for c in candidates:
            sel = {**fixed_before, r: c, **sel_after}
            rets[c] = run_game(start_date, sel, price_data=price_data)['final_return_rate']
        avg = float(np.mean(list(rets.values())))
        for c, v in rets.items():
            contribs[c].append(v - avg)
    return {c: float(np.mean(v)) for c, v in contribs.items()}


# =============================================
# 거래일·구간
# =============================================
def spx_series():
    df = load_all()['^SPX'].sort_values('Date').reset_index(drop=True)
    dates = pd.DatetimeIndex(df['Date'])
    closes = df['Close'].astype(float).values
    return dates, closes


def train_windows(dates, closes):
    """유사 구간 후보: 시작 ≥ TRAIN_START, 100번째 거래일 ≤ TRAIN_LAST_DATE"""
    first = dates.searchsorted(pd.Timestamp(TRAIN_START), side='left')
    last_date = pd.Timestamp(TRAIN_LAST_DATE)
    idxs = [i for i in range(first, len(dates) - ROUNDS + 1) if dates[i + ROUNDS - 1] <= last_date]
    feats = {r: np.array([calc_spx_so_far(closes[i:i + ROUNDS], r) for i in idxs], dtype=float)
             for r in EVAL_ROUNDS}
    return idxs, feats


def test_starts(dates, step):
    """테스트 시작일: TEST_FIRST부터 step거래일 간격, 100번째 거래일 ≤ TEST_LAST_DATE"""
    i = dates.searchsorted(pd.Timestamp(TEST_FIRST), side='left')
    last_date = pd.Timestamp(TEST_LAST_DATE)
    out = []
    while i + ROUNDS - 1 < len(dates) and dates[i + ROUNDS - 1] <= last_date:
        out.append(i)
        i += step
    return out


def pick_neighbors(query, train_feat, mean, std, idxs, k, min_gap):
    """표준화 거리로 가까운 순 정렬 → 서로 min_gap 거래일 이상 떨어진 k개 선택"""
    z_train = (train_feat - mean) / std
    z_q = (np.asarray(query) - mean) / std
    dist = np.sqrt(((z_train - z_q) ** 2).sum(axis=1))
    chosen = []
    for j in np.argsort(dist):
        if all(abs(idxs[j] - idxs[c]) >= min_gap for c in chosen):
            chosen.append(j)
            if len(chosen) == k:
                break
    return [(idxs[j], float(dist[j])) for j in chosen]


# =============================================
# 채점
# =============================================
def top1_hit_rate(truth: dict, pred: dict) -> float:
    """후보 3장 조합 전체에 대해, 예측 1위가 정답 1위와 같은 비율 (무작위 = 1/3)"""
    cards = [c for c in truth if c in pred]
    triples = list(combinations(cards, 3))
    if not triples:
        return float('nan')
    hits = sum(1 for t in triples if max(t, key=lambda c: pred[c]) == max(t, key=lambda c: truth[c]))
    return hits / len(triples)


def rho(truth: dict, pred: dict) -> float:
    cards = [c for c in truth if c in pred]
    if len(cards) < 3:
        return float('nan')
    return float(spearmanr([truth[c] for c in cards], [pred[c] for c in cards])[0])


# =============================================
# 메인
# =============================================
def run(k, n_sets, n_already, step, min_gap, seed, quick, model_path):
    t0 = time.time()
    dates, closes = spx_series()
    idxs, feats = train_windows(dates, closes)
    stats = {r: (feats[r].mean(axis=0), feats[r].std(axis=0)) for r in EVAL_ROUNDS}   # 학습 구간으로만 표준화
    starts = test_starts(dates, step)
    if quick:
        starts = starts[:5]
    if not idxs or not starts:
        print('유사 구간 후보 또는 테스트 시작일이 없습니다. 데이터 기간을 확인하세요.')
        return

    model = None
    if model_path and os.path.exists(model_path):
        with open(model_path, 'rb') as f:
            model = pickle.load(f)
        print(f'V2 모델 로드: {model_path}')
    else:
        print(f'V2 모델 없음 ({model_path}) → 정답·유사 구간만 계산')

    print(f'유사 구간 후보 {len(idxs):,}개 ({dates[idxs[0]].date()} ~ {dates[idxs[-1]].date()} 시작)')
    print(f'테스트 시작일 {len(starts)}개 ({dates[starts[0]].date()} ~ {dates[starts[-1]].date()}), '
          f'시점 {len(starts) * len(EVAL_ROUNDS) * n_already}개 / K={k}, 세트={n_sets}\n')

    rows, neigh_rows, scores = [], [], []
    leak_violations = 0
    point_id = 0
    for si, s_idx in enumerate(starts):
        start = dates[s_idx].strftime('%Y-%m-%d')
        test_closes = closes[s_idx:s_idx + ROUNDS]
        pool = available_card_ids(get_price_data(start))
        for r in EVAL_ROUNDS:
            n_before = len([x for x in CARD_SELECT_ROUNDS if x < r])
            # 추천 시점까지의 정보만 사용 (closes[:r])
            so_far = calc_spx_so_far(test_closes, r)
            neighbors = pick_neighbors(so_far, feats[r], *stats[r], idxs, k, min_gap)
            for a in range(n_already):
                point_id += 1
                rng = random.Random(f'{seed}-{start}-{r}-{a}')
                already = rng.sample(pool, n_before)

                truth = card_contributions(start, r, already, rng, n_sets)

                sim_acc = defaultdict(list)
                for n_idx, d in neighbors:
                    n_start = dates[n_idx].strftime('%Y-%m-%d')
                    if dates[n_idx + ROUNDS - 1] > pd.Timestamp(TRAIN_LAST_DATE) or dates[n_idx] < pd.Timestamp(TRAIN_START):
                        leak_violations += 1
                    c = card_contributions(n_start, r, already, random.Random(f'{seed}-{point_id}-{n_start}'), n_sets)
                    for card, v in c.items():
                        sim_acc[card].append(v)
                    if a == 0:
                        neigh_rows.append([start, r, n_start, dates[n_idx + ROUNDS - 1].strftime('%Y-%m-%d'), round(d, 4)])
                similar = {card: float(np.mean(v)) for card, v in sim_acc.items()}

                v2 = {}
                if model is not None:
                    cands = [c for c in sorted(CARDS) if c not in already]
                    preds = model.predict([make_feature(*so_far, r, already, c) for c in cands])
                    v2 = {c: float(p) for c, p in zip(cands, preds)}

                score = {'point_id': point_id, 'start': start, 'round': r,
                         'rho_similar': rho(truth, similar), 'hit_similar': top1_hit_rate(truth, similar)}
                if v2:
                    score.update({'rho_v2': rho(truth, v2), 'hit_v2': top1_hit_rate(truth, v2)})
                scores.append(score)

                t_rank = {c: i + 1 for i, c in enumerate(sorted(truth, key=lambda c: -truth[c]))}
                s_rank = {c: i + 1 for i, c in enumerate(sorted(similar, key=lambda c: -similar[c]))}
                v_rank = {c: i + 1 for i, c in enumerate(sorted(v2, key=lambda c: -v2[c]))}
                for card in sorted(truth):
                    rows.append([point_id, start, r, '|'.join(map(str, already)), card, CARDS[card]['name'],
                                 round(truth[card], 4), t_rank[card],
                                 round(similar.get(card, float('nan')), 4), s_rank.get(card, ''),
                                 round(v2[card], 4) if card in v2 else '', v_rank.get(card, '')])
        elapsed = time.time() - t0
        print(f'  시작일 {si + 1}/{len(starts)} ({start}) 완료 — {elapsed:.0f}초, '
              f'남은 예상 {elapsed / (si + 1) * (len(starts) - si - 1):.0f}초')

    os.makedirs(DATA_DIR, exist_ok=True)
    with open(OUT_RESULTS, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['point_id', 'start_date', 'round', 'already', 'card_id', 'card_name',
                    'truth_contribution', 'truth_rank', 'similar_contribution', 'similar_rank',
                    'v2_prediction', 'v2_rank'])
        w.writerows(rows)
    with open(OUT_NEIGH, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['test_start', 'round', 'neighbor_start', 'neighbor_end', 'distance'])
        w.writerows(neigh_rows)

    write_summary(scores, len(starts), len(idxs), dates, idxs, starts, k, n_sets, n_already, step,
                  min_gap, leak_violations, model is not None, time.time() - t0)
    print(f'\n저장: {OUT_RESULTS}\n      {OUT_NEIGH}\n      {OUT_SUMMARY}')


def _agg(values):
    v = [x for x in values if x == x]   # NaN 제외
    if not v:
        return '-'
    return f'{np.mean(v):+.3f} (표준편차 {np.std(v):.3f}, n={len(v)})'


def write_summary(scores, n_starts, n_windows, dates, idxs, starts, k, n_sets, n_already, step,
                  min_gap, leak_violations, has_v2, elapsed):
    df = pd.DataFrame(scores)
    lines = ['# 테스트 기간 평가 요약 (정답 vs 유사 구간 백테스팅 vs V2)', '',
             f'- 생성 시각: {datetime.now().isoformat(timespec="seconds")} / 소요 {elapsed:.0f}초',
             f'- 테스트 시작일 {n_starts}개 ({dates[starts[0]].date()} ~ {dates[starts[-1]].date()}, {step}거래일 간격) '
             f'× 라운드 {EVAL_ROUNDS} × alreadyCards {n_already}세트 = 시점 {len(df)}개',
             f'- 유사 구간 후보 {n_windows:,}개 (시작 {dates[idxs[0]].date()} ~ {dates[idxs[-1]].date()}, '
             f'100라운드가 {TRAIN_LAST_DATE} 안에서 끝남), K={k}, 최소 간격 {min_gap}거래일',
             f'- 카드 기여도: 나머지 카드 세트 {n_sets}개 평균 (V2 학습 데이터와 같은 정의)', '',
             '## 1. 결과', '',
             '| 방법 | 라운드 | 스피어만 ρ 평균 | 3장 중 1위 적중률 (무작위 0.333) |', '|---|---|---|---|']
    methods = [('유사 구간 백테스팅', 'rho_similar', 'hit_similar')]
    if has_v2:
        methods.append(('V2 (모델 A)', 'rho_v2', 'hit_v2'))
    for name, rc, hc in methods:
        for r in EVAL_ROUNDS + ['전체']:
            sub = df if r == '전체' else df[df['round'] == r]
            lines.append(f'| {name} | {r} | {_agg(sub[rc])} | {_agg(sub[hc])} |')
    lines += ['', '## 2. 누설 점검', '',
              f'- 유사 구간 중 학습 기간 밖(시작 < {TRAIN_START} 또는 100라운드 > {TRAIN_LAST_DATE}) 사용: {leak_violations}건',
              '- 테스트 시점의 유사 구간 검색 입력: 해당 게임의 closes[:r] (추천 시점까지)만 사용',
              '- 지표 표준화: 학습 구간 후보 통계로만 계산', '',
              '## 3. 해석 시 주의', '',
              f'- 테스트 시작일 간격({step}거래일)이 게임 길이({ROUNDS}거래일)보다 짧아, 인접 시작일의 게임 기간이 겹친다. 시점들은 서로 독립된 표본이 아니다.',
              '- 정답은 나머지 카드 세트를 무작위로 바꿔 평균 낸 값이므로, 세트 수에 따라 약간의 노이즈가 남는다.']
    with open(OUT_SUMMARY, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
    print('\n' + '\n'.join(lines[9:9 + 2 + 3 * len(methods)]))


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--k', type=int, default=10, help='유사 구간 개수')
    ap.add_argument('--sets', type=int, default=20, help='나머지 카드 세트 수 (기여도 평균용)')
    ap.add_argument('--already-sets', type=int, default=3, help='시점마다 alreadyCards 무작위 세트 수')
    ap.add_argument('--step', type=int, default=20, help='테스트 시작일 간격(거래일)')
    ap.add_argument('--min-gap', type=int, default=20, help='유사 구간끼리 최소 간격(거래일)')
    ap.add_argument('--seed', type=int, default=42)
    ap.add_argument('--quick', action='store_true', help='테스트 시작일 5개만 (빠른 점검)')
    ap.add_argument('--model', default=MODEL_PATH, help='V2 모델 경로 (없으면 V2 비교 생략)')
    a = ap.parse_args()
    run(a.k, a.sets, a.already_sets, a.step, a.min_gap, a.seed, a.quick, a.model)
