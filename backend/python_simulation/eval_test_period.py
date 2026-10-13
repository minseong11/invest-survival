"""
eval_test_period.py — 테스트 기간(2019~2024) 정답 + 유사 구간 백테스팅 (+ V2 예측) 생성·채점

7주차 비교 실험용. 테스트 기간의 각 시점(25·50라운드)에서
  1) 정답        : 실제 백테스팅으로 구한 카드별 기여도와 순위 (채점 기준)
  2) 유사 구간   : 2018년까지의 과거에서 시장 상황이 비슷했던 구간을 찾아, 그때의 카드 기여도를 평균 낸 순위
  3) V2 (선택)   : model_v2_A.pkl이 있으면 같은 입력으로 V2 예측 순위
를 계산하고, 2)·3)을 1)과 비교(스피어만, 3장 중 1위 적중률)한다.

결과 해석용 (v2)
  - 정답 재현성(점수 상한): 정답을 다른 무작위 세트로 한 번 더 계산해 두 정답끼리 비교.
    어떤 방법도 이 값보다 정답과 더 잘 맞기는 어렵다.
  - 95% 신뢰구간: 테스트 시작일을 시간 순서대로 연속 블록(기본 5개 = 100거래일)으로 묶어 재표본(이동 블록 부트스트랩).
    인접 시작일의 게임 기간이 겹치는(서로 독립이 아닌) 점을 반영한다.
  - 기간 비중복 부분집합: 게임 기간이 겹치지 않도록 시작일을 5개마다 1개씩 고른 부분집합 결과.
  - V2 − 유사 구간 차이의 신뢰구간 (V2 모델이 있을 때)

카드 결과 정의 — V2 학습 데이터(monte_carlo_v2.run_chunk)와 동일
  - 이미 고른 카드(alreadyCards)는 고정, 이후 라운드(50·75) 카드는 무작위로 고정한 "나머지 카드 세트"를 만든다
  - 그 세트에서 r 자리에 가능한 후보(전체 − 이미 고른 카드 − 이후 라운드 카드)를 하나씩 넣어 run_game
  - 기여도 = 그 후보의 최종 수익률 − 같은 세트 후보들의 평균 수익률
  - 나머지 카드 세트 하나만 쓰면 노이즈가 커서, 세트를 N개 바꿔가며 카드별 평균을 낸다
시장 지표(so_far)는 monte_carlo_v2.calc_spx_so_far(closes[:r])를 그대로 사용한다 (V2 입력과 동일 공식).

정보 누설 방지 (교수님 조건)
  - 유사 구간 검색은 추천 시점(r라운드)까지의 SPX 정보만 사용
  - 검색 대상 과거 구간은 100라운드 전체가 2018-12-31 안에서 끝나는 구간만 (시작 2006-04-10 이후, USO 상장일)
  - 지표 표준화(평균·표준편차)도 학습 구간 데이터로만 계산
  - 2019~2024 가격은 정답(채점)에만 사용
  - 후보 카드·추천 시점·결과 정의는 V2와 동일

사용법:
    cd backend/python_simulation
    python3 eval_test_period.py                 # 전체 계산 + 채점 (약 8분)
    python3 eval_test_period.py --quick         # 빠른 점검 (시작일 5개)
    python3 eval_test_period.py --summary-only  # 계산 없이 기존 eval_results.csv로 다시 채점
                                                #  (model_v2_A.pkl을 받은 뒤 V2 채점만 추가할 때 — 수 초)
출력:
    ../data/simulation/eval_results.csv     # 시점 × 카드별 정답/정답2/유사 구간/V2 값
    ../data/simulation/eval_neighbors.csv   # 시점별로 선택된 과거 구간
    ../data/simulation/eval_meta.json       # 실행 설정 (요약 재생성용)
    ../data/simulation/eval_summary.md      # 요약 (점수, 신뢰구간, 점수 상한, 누설 점검)
"""
import argparse
import csv
import json
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

N_BOOT          = 2000           # 부트스트랩 반복 수
RANDOM_HIT      = 1 / 3          # 3장 중 1위 무작위 적중률

DATA_DIR    = os.path.join(os.path.dirname(__file__), '..', 'data', 'simulation')
MODEL_PATH  = os.path.join(DATA_DIR, 'model_v2_A.pkl')
OUT_RESULTS = os.path.join(DATA_DIR, 'eval_results.csv')
OUT_NEIGH   = os.path.join(DATA_DIR, 'eval_neighbors.csv')
OUT_META    = os.path.join(DATA_DIR, 'eval_meta.json')
OUT_SUMMARY = os.path.join(DATA_DIR, 'eval_summary.md')

RESULT_COLS = ['point_id', 'start_date', 'round', 'already',
               'so_far_return', 'so_far_vol', 'so_far_mdd',
               'card_id', 'card_name',
               'truth_contribution', 'truth_rank', 'truth2_contribution',
               'similar_contribution', 'similar_rank',
               'v2_prediction', 'v2_rank']


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
# 1단계: 계산 (정답 · 정답2 · 유사 구간)
# =============================================
def run(k, n_sets, n_already, step, min_gap, seed, quick):
    t0 = time.time()
    dates, closes = spx_series()
    idxs, feats = train_windows(dates, closes)
    stats = {r: (feats[r].mean(axis=0), feats[r].std(axis=0)) for r in EVAL_ROUNDS}   # 학습 구간으로만 표준화
    starts = test_starts(dates, step)
    if quick:
        starts = starts[:5]
    if not idxs or not starts:
        print('유사 구간 후보 또는 테스트 시작일이 없습니다. 데이터 기간을 확인하세요.')
        return False

    print(f'유사 구간 후보 {len(idxs):,}개 ({dates[idxs[0]].date()} ~ {dates[idxs[-1]].date()} 시작)')
    print(f'테스트 시작일 {len(starts)}개 ({dates[starts[0]].date()} ~ {dates[starts[-1]].date()}), '
          f'시점 {len(starts) * len(EVAL_ROUNDS) * n_already}개 / K={k}, 세트={n_sets}\n')

    rows, neigh_rows = [], []
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
                # 정답 재현성 측정용: 같은 시점·같은 alreadyCards, 다른 무작위 세트로 한 번 더
                truth2 = card_contributions(start, r, already, random.Random(f'{seed}-{start}-{r}-{a}-retest'), n_sets)

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

                t_rank = _ranks(truth)
                s_rank = _ranks(similar)
                for card in sorted(truth):
                    rows.append([point_id, start, r, '|'.join(map(str, already)), *so_far,
                                 card, CARDS[card]['name'],
                                 round(truth[card], 4), t_rank[card],
                                 round(truth2[card], 4) if card in truth2 else '',
                                 round(similar[card], 4) if card in similar else '', s_rank.get(card, ''),
                                 '', ''])
        elapsed = time.time() - t0
        print(f'  시작일 {si + 1}/{len(starts)} ({start}) 완료 — {elapsed:.0f}초, '
              f'남은 예상 {elapsed / (si + 1) * (len(starts) - si - 1):.0f}초')

    os.makedirs(DATA_DIR, exist_ok=True)
    with open(OUT_RESULTS, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(RESULT_COLS)
        w.writerows(rows)
    with open(OUT_NEIGH, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['test_start', 'round', 'neighbor_start', 'neighbor_end', 'distance'])
        w.writerows(neigh_rows)
    meta = {
        'k': k, 'n_sets': n_sets, 'n_already': n_already, 'step': step, 'min_gap': min_gap, 'seed': seed,
        'n_windows': len(idxs),
        'window_first': str(dates[idxs[0]].date()), 'window_last': str(dates[idxs[-1]].date()),
        'test_first': str(dates[starts[0]].date()), 'test_last': str(dates[starts[-1]].date()),
        'n_starts': len(starts), 'leak_violations': leak_violations,
        'train_start': TRAIN_START, 'train_last_date': TRAIN_LAST_DATE,
        'compute_seconds': round(time.time() - t0),
    }
    with open(OUT_META, 'w', encoding='utf-8') as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    print(f'\n계산 완료 ({time.time() - t0:.0f}초) → {OUT_RESULTS}')
    return True


def _ranks(scores: dict) -> dict:
    return {c: i + 1 for i, c in enumerate(sorted(scores, key=lambda c: -scores[c]))}


# =============================================
# 2단계: 채점 (V2 예측 추가 · 점수 · 신뢰구간)
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


def add_v2_predictions(df: pd.DataFrame, model) -> pd.DataFrame:
    """저장된 시장 지표·alreadyCards로 V2 예측을 계산해 열을 채운다 (재계산 불필요)"""
    df = df.copy()
    df['v2_prediction'] = np.nan
    df['v2_rank'] = np.nan
    for pid, g in df.groupby('point_id'):
        r = int(g['round'].iloc[0])
        already = [int(x) for x in str(g['already'].iloc[0]).split('|') if x != '']
        so_far = (float(g['so_far_return'].iloc[0]), float(g['so_far_vol'].iloc[0]), float(g['so_far_mdd'].iloc[0]))
        cards = [int(c) for c in g['card_id']]
        preds = model.predict([make_feature(*so_far, r, already, c) for c in cards])
        pred = {c: float(p) for c, p in zip(cards, preds)}
        rank = _ranks(pred)
        df.loc[g.index, 'v2_prediction'] = [round(pred[c], 4) for c in cards]
        df.loc[g.index, 'v2_rank'] = [rank[c] for c in cards]
    df['v2_rank'] = df['v2_rank'].astype('Int64')
    return df


def point_scores(df: pd.DataFrame, has_v2: bool) -> pd.DataFrame:
    out = []
    for pid, g in df.groupby('point_id'):
        def col(name):
            s = g.set_index('card_id')[name]
            s = pd.to_numeric(s, errors='coerce').dropna()
            return {int(c): float(v) for c, v in s.items()}
        truth, truth2, similar = col('truth_contribution'), col('truth2_contribution'), col('similar_contribution')
        row = {'point_id': pid, 'start': g['start_date'].iloc[0], 'round': int(g['round'].iloc[0]),
               'rho_ceiling': rho(truth, truth2), 'hit_ceiling': top1_hit_rate(truth, truth2),
               'rho_similar': rho(truth, similar), 'hit_similar': top1_hit_rate(truth, similar)}
        if has_v2:
            v2 = col('v2_prediction')
            row.update({'rho_v2': rho(truth, v2), 'hit_v2': top1_hit_rate(truth, v2)})
        out.append(row)
    return pd.DataFrame(out)


def block_bootstrap_ci(scores: pd.DataFrame, value_col: str, block: int, n_boot: int, seed: int):
    """
    이동 블록 부트스트랩 — 시작일을 시간 순서로 정렬하고, 연속된 block개 시작일을 한 덩어리로 재표본.
    인접 시작일의 게임 기간이 겹치는(독립이 아닌) 점을 반영한다.
    반환: (평균, 2.5% 하한, 97.5% 상한)
    """
    s = scores[['start', value_col]].dropna()
    if s.empty:
        return float('nan'), float('nan'), float('nan')
    starts = sorted(s['start'].unique())
    per_start = s.groupby('start')[value_col].agg(['sum', 'count']).reindex(starts)
    sums, counts = per_start['sum'].values, per_start['count'].values
    n = len(starts)
    b = max(1, min(block, n))
    n_blocks = int(np.ceil(n / b))
    rng = np.random.default_rng(seed)
    means = np.empty(n_boot)
    for i in range(n_boot):
        begins = rng.integers(0, n, size=n_blocks)
        idx = (begins[:, None] + np.arange(b)[None, :]).ravel() % n     # 원형으로 이어 붙임
        means[i] = sums[idx].sum() / counts[idx].sum()
    point = s[value_col].mean()
    return float(point), float(np.percentile(means, 2.5)), float(np.percentile(means, 97.5))


def non_overlap_range(scores: pd.DataFrame, value_col: str, block: int):
    """게임 기간이 겹치지 않도록 시작일을 block개마다 1개씩 고른 부분집합들(block개)의 평균 범위"""
    starts = sorted(scores['start'].unique())
    vals = []
    for off in range(block):
        chosen = set(starts[off::block])
        sub = scores[scores['start'].isin(chosen)][value_col].dropna()
        if len(sub):
            vals.append(sub.mean())
    if not vals:
        return float('nan'), float('nan'), 0
    return float(min(vals)), float(max(vals)), len(starts[0::block])


def fmt_ci(t, base=None):
    m, lo, hi = t
    if m != m:
        return '-'
    mark = ''
    if base is not None:
        mark = ' ✅' if lo > base else (' ❌' if hi < base else ' ➖')
    return f'{m:+.3f} [{lo:+.3f}, {hi:+.3f}]{mark}'


def summarize(model_path, seed=42):
    if not os.path.exists(OUT_RESULTS):
        print(f'결과 파일 없음: {OUT_RESULTS} — 먼저 계산을 실행하세요.')
        return
    df = pd.read_csv(OUT_RESULTS)
    meta = {}
    if os.path.exists(OUT_META):
        with open(OUT_META, encoding='utf-8') as f:
            meta = json.load(f)

    model = None
    if model_path and os.path.exists(model_path):
        with open(model_path, 'rb') as f:
            model = pickle.load(f)
        print(f'V2 모델 로드: {model_path} → V2 예측 추가')
        df = add_v2_predictions(df, model)
        df.to_csv(OUT_RESULTS, index=False)
    else:
        print(f'V2 모델 없음 ({model_path}) → 정답·유사 구간만 채점')
    has_v2 = model is not None

    scores = point_scores(df, has_v2)
    step = meta.get('step', 20)
    block = max(1, int(np.ceil(ROUNDS / step)))       # 게임 길이만큼의 시작일 묶음 (20거래일 간격 → 5개)

    methods = [('정답 재현성 (점수 상한)', 'ceiling'), ('유사 구간 백테스팅', 'similar')]
    if has_v2:
        methods.append(('V2 (모델 A)', 'v2'))

    lines = ['# 테스트 기간 평가 요약 (정답 vs 유사 구간 백테스팅 vs V2)', '',
             f'- 생성 시각: {datetime.now().isoformat(timespec="seconds")}'
             + (f' / 계산 {meta["compute_seconds"]}초' if 'compute_seconds' in meta else ''),
             f'- 테스트 시작일 {scores["start"].nunique()}개 '
             f'({meta.get("test_first", "?")} ~ {meta.get("test_last", "?")}, {step}거래일 간격) '
             f'× 라운드 {EVAL_ROUNDS} × alreadyCards {meta.get("n_already", "?")}세트 = 시점 {len(scores)}개',
             f'- 유사 구간 후보 {meta.get("n_windows", "?"):,}개 (시작 {meta.get("window_first", "?")} ~ '
             f'{meta.get("window_last", "?")}, 100라운드가 {TRAIN_LAST_DATE} 안에서 끝남), '
             f'K={meta.get("k", "?")}, 최소 간격 {meta.get("min_gap", "?")}거래일'
             if isinstance(meta.get('n_windows'), int) else '- 유사 구간 설정: eval_meta.json 없음',
             f'- 카드 기여도: 나머지 카드 세트 {meta.get("n_sets", "?")}개 평균 (V2 학습 데이터와 같은 정의)',
             f'- 신뢰구간: 시작일 {block}개(= {ROUNDS}거래일) 연속 블록 부트스트랩 {N_BOOT:,}회, 95%', '',
             '## 1. 결과 (평균 [95% 신뢰구간])', '',
             '표시: ✅ 신뢰구간 전체가 무작위 기준보다 높음 / ➖ 기준을 포함(구분 불가) / ❌ 기준보다 낮음', '',
             '| 방법 | 라운드 | 스피어만 ρ (무작위 0) | 3장 중 1위 적중률 (무작위 0.333) |', '|---|---|---|---|']
    for name, key in methods:
        for r in EVAL_ROUNDS + ['전체']:
            sub = scores if r == '전체' else scores[scores['round'] == r]
            lines.append(f'| {name} | {r} | '
                         f'{fmt_ci(block_bootstrap_ci(sub, "rho_" + key, block, N_BOOT, seed), 0.0)} | '
                         f'{fmt_ci(block_bootstrap_ci(sub, "hit_" + key, block, N_BOOT, seed), RANDOM_HIT)} |')

    lines += ['', '## 2. 기간 비중복 부분집합 (강건성 확인)', '',
              f'게임 기간이 겹치지 않도록 시작일을 {block}개마다 1개씩 고른 부분집합 {block}개(각 약 '
              f'{non_overlap_range(scores, "rho_similar", block)[2]}개 시작일)의 평균이 어느 범위에 있는지.', '',
              '| 방법 | 스피어만 ρ 범위 | 1위 적중률 범위 |', '|---|---|---|']
    for name, key in methods:
        r_lo, r_hi, _ = non_overlap_range(scores, 'rho_' + key, block)
        h_lo, h_hi, _ = non_overlap_range(scores, 'hit_' + key, block)
        lines.append(f'| {name} | {r_lo:+.3f} ~ {r_hi:+.3f} | {h_lo:.3f} ~ {h_hi:.3f} |')

    if has_v2:
        diff = scores.copy()
        diff['rho_diff'] = diff['rho_v2'] - diff['rho_similar']
        diff['hit_diff'] = diff['hit_v2'] - diff['hit_similar']
        lines += ['', '## 3. V2 − 유사 구간 (같은 시점끼리 차이)', '',
                  '표시: ✅ V2가 확실히 높음 / ➖ 구분 불가 / ❌ 유사 구간이 확실히 높음', '',
                  '| 라운드 | 스피어만 ρ 차이 | 1위 적중률 차이 |', '|---|---|---|']
        for r in EVAL_ROUNDS + ['전체']:
            sub = diff if r == '전체' else diff[diff['round'] == r]
            lines.append(f'| {r} | {fmt_ci(block_bootstrap_ci(sub, "rho_diff", block, N_BOOT, seed), 0.0)} | '
                         f'{fmt_ci(block_bootstrap_ci(sub, "hit_diff", block, N_BOOT, seed), 0.0)} |')

    n = 4 if has_v2 else 3
    lines += ['', f'## {n}. 누설 점검', '',
              f'- 유사 구간 중 학습 기간 밖(시작 < {TRAIN_START} 또는 100라운드 > {TRAIN_LAST_DATE}) 사용: '
              f'{meta.get("leak_violations", "?")}건',
              '- 테스트 시점의 유사 구간 검색 입력: 해당 게임의 closes[:r] (추천 시점까지)만 사용',
              '- 지표 표준화: 학습 구간 후보 통계로만 계산',
              '- V2 입력: 저장된 so_far 지표(closes[:r])·alreadyCards·후보 카드만 사용', '',
              f'## {n + 1}. 해석 시 주의', '',
              '- 정답 재현성(점수 상한)은 같은 시점의 정답을 무작위 세트만 바꿔 다시 계산했을 때 얼마나 일치하는지다. '
              '방법의 점수는 이 값과 비교해 읽는다.',
              f'- 시작일 간격({step}거래일)이 게임 길이({ROUNDS}거래일)보다 짧아 시점들이 독립이 아니다. '
              '신뢰구간은 이를 반영한 블록 부트스트랩이며, 기간 비중복 부분집합 결과도 함께 확인한다.',
              '- 테스트 기간(2019~2024)은 코로나 급락·2022 하락장을 포함한 한 번의 시장 경로다. 다른 기간에서도 같은 결과가 나온다는 뜻은 아니다.']

    with open(OUT_SUMMARY, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
    start = lines.index('## 1. 결과 (평균 [95% 신뢰구간])')
    print('\n' + '\n'.join(lines[start:]))
    print(f'\n저장: {OUT_SUMMARY}')


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--k', type=int, default=10, help='유사 구간 개수')
    ap.add_argument('--sets', type=int, default=20, help='나머지 카드 세트 수 (기여도 평균용)')
    ap.add_argument('--already-sets', type=int, default=3, help='시점마다 alreadyCards 무작위 세트 수')
    ap.add_argument('--step', type=int, default=20, help='테스트 시작일 간격(거래일)')
    ap.add_argument('--min-gap', type=int, default=20, help='유사 구간끼리 최소 간격(거래일)')
    ap.add_argument('--seed', type=int, default=42)
    ap.add_argument('--quick', action='store_true', help='테스트 시작일 5개만 (빠른 점검)')
    ap.add_argument('--summary-only', action='store_true', help='계산 없이 기존 결과로 다시 채점 (V2 추가 등)')
    ap.add_argument('--model', default=MODEL_PATH, help='V2 모델 경로 (없으면 V2 비교 생략)')
    a = ap.parse_args()
    if a.summary_only or run(a.k, a.sets, a.already_sets, a.step, a.min_gap, a.seed, a.quick):
        summarize(a.model, a.seed)
