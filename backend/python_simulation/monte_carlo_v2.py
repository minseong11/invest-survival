"""
몬테카를로 시뮬레이션 V2 재설계 — Card_Contribution 타겟
실시간 추천 모델(V2) 학습용

기존 V2 문제:
  타겟이 Final_Return이라 Selected_Card Feature Importance ~2%
  → 카드 추천이 전부 동일하게 나오는 구조적 문제

재설계 핵심:
  타겟을 Card_Contribution으로 변경
  Card_Contribution = 해당 카드 Final_Return - 11개 카드 평균 Final_Return
  → 시장 효과 상쇄, 카드 효과만 순수하게 학습

데이터 구조:
  게임 1개 → 라운드 4개 × 카드 최대 11개 = 최대 44 row
  10만 게임 → 약 350만 row (중복 제외)

입력 26차원:
  시장 정보 3: SPX_Return_so_far, SPX_Volatility_so_far, SPX_MDD_so_far
  진행 상황 1: current_round
  이미 선택한 카드 11: Already_Card1~11 (multi-hot)
  이번 선택 카드 11: Selected_Card_1~11 (one-hot)
출력: Card_Contribution (회귀)
"""
import os
import random
import csv
import time
import tempfile
import numpy as np
import multiprocessing as mp
from datetime import datetime, timedelta
from game_logic import run_game, CARDS
from data_loader import get_price_list

OUTPUT_DIR  = os.path.join(os.path.dirname(__file__), '..', 'data', 'simulation')
os.makedirs(OUTPUT_DIR, exist_ok=True)
OUTPUT_PATH = os.path.join(OUTPUT_DIR, 'training_data_v2.csv')

ALL_CARD_IDS       = list(CARDS.keys())   # [1, 2, ..., 11]
CARD_SELECT_ROUNDS = [1, 25, 50, 75]
SIM_START          = datetime(2007, 9, 1)
SIM_END            = datetime(2009, 6, 1)
N_SIMULATIONS      = 100_000

ALREADY_COLS  = [f'Already_Card{i}' for i in range(1, 12)]
SELECTED_COLS = [f'Selected_Card_{i}' for i in range(1, 12)]

FIELDNAMES = [
    'sim_id', 'scenario_id', 'start_date',
    'current_round',
    'SPX_Return_so_far', 'SPX_Volatility_so_far', 'SPX_MDD_so_far',
    *ALREADY_COLS,
    *SELECTED_COLS,
    'Card_Contribution',
]


def random_start_date() -> str:
    delta = (SIM_END - SIM_START).days
    rand_day = SIM_START + timedelta(days=random.randint(0, delta))
    return rand_day.strftime('%Y-%m-%d')


def calc_spx_so_far(closes: np.ndarray, up_to_idx: int):
    """현재 라운드까지의 시장 지표 계산"""
    sub = closes[:up_to_idx]
    if len(sub) < 2:
        return 0.0, 0.0, 0.0

    ret   = (sub[-1] - sub[0]) / sub[0] * 100
    daily = np.diff(sub) / sub[:-1] * 100
    vol   = float(np.std(daily)) if len(daily) > 0 else 0.0

    cumul       = sub / sub[0]
    rolling_max = np.maximum.accumulate(cumul)
    drawdowns   = (cumul - rolling_max) / rolling_max * 100
    mdd         = float(drawdowns.min())

    return round(float(ret), 4), round(vol, 4), round(mdd, 4)


def make_already_encoding(selected_so_far: list) -> dict:
    enc = {col: 0 for col in ALREADY_COLS}
    for card_id in selected_so_far:
        key = f'Already_Card{card_id}'
        if key in enc:
            enc[key] = 1
    return enc


def make_selected_encoding(card_id: int) -> dict:
    enc = {col: 0 for col in SELECTED_COLS}
    key = f'Selected_Card_{card_id}'
    if key in enc:
        enc[key] = 1
    return enc


def run_chunk(args):
    """
    병렬 워커 — 게임 청크 단위 실행
    각 게임마다:
      1. 시작 날짜 고정
      2. 나머지 카드 조합 랜덤 고정
      3. 각 라운드에서 가능한 카드 전부 시도
      4. Card_Contribution = 해당 카드 수익률 - 가능한 카드들의 평균 수익률
    """
    chunk_id, sim_id_start, chunk_size = args
    random.seed(chunk_id)

    tmp_path = os.path.join(
        tempfile.gettempdir(),
        f'mc_v2_chunk_{chunk_id}.csv'
    )

    with open(tmp_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=FIELDNAMES)
        writer.writeheader()

        completed = 0
        for i in range(chunk_size):
            sim_id     = sim_id_start + i
            start_date = random_start_date()

            # SPX 전체 100라운드 데이터 로드
            spx = get_price_list(start_date, '^SPX')
            if len(spx) < 100:
                continue
            closes = spx.iloc[:100]['Close'].values

            # 기준 카드 조합 설정 (나머지 3장 랜덤 고정)
            base_selections = {}
            pool = ALL_CARD_IDS.copy()
            random.shuffle(pool)
            for idx, r in enumerate(CARD_SELECT_ROUNDS):
                base_selections[r] = pool[idx]

            # 라운드별로 카드 전부 시도
            round_to_idx   = {1: 2, 25: 25, 50: 50, 75: 75}
            already_so_far = []

            for r in CARD_SELECT_ROUNDS:
                up_to_idx = round_to_idx[r]
                ret_so_far, vol_so_far, mdd_so_far = calc_spx_so_far(
                    closes, up_to_idx
                )

                # 나머지 라운드 카드 고정
                other_rounds_cards = {
                    other_r: base_selections[other_r]
                    for other_r in CARD_SELECT_ROUNDS
                    if other_r != r
                }

                # 이번 라운드에서 시도 가능한 카드
                # (이미 선택한 카드 + 나머지 라운드 고정 카드 제외)
                excluded = set(already_so_far) | set(other_rounds_cards.values())
                candidates = [c for c in ALL_CARD_IDS if c not in excluded]

                if len(candidates) < 2:
                    already_so_far.append(base_selections[r])
                    continue

                # 각 후보 카드로 게임 실행
                final_returns = {}
                for candidate_card in candidates:
                    card_selections = dict(other_rounds_cards)
                    card_selections[r] = candidate_card

                    try:
                        result = run_game(start_date, card_selections)
                        final_returns[candidate_card] = result['final_return_rate']
                    except Exception:
                        continue

                if len(final_returns) < 2:
                    already_so_far.append(base_selections[r])
                    continue

                # Card_Contribution 계산
                avg_return  = np.mean(list(final_returns.values()))
                already_enc = make_already_encoding(already_so_far)

                for candidate_card, final_return in final_returns.items():
                    contribution = round(final_return - avg_return, 4)
                    selected_enc = make_selected_encoding(candidate_card)

                    row = {
                        'sim_id':                sim_id,
                        'scenario_id':           'lehman',
                        'start_date':            start_date,
                        'current_round':         r,
                        'SPX_Return_so_far':     ret_so_far,
                        'SPX_Volatility_so_far': vol_so_far,
                        'SPX_MDD_so_far':        mdd_so_far,
                        **already_enc,
                        **selected_enc,
                        'Card_Contribution':     contribution,
                    }
                    writer.writerow(row)

                # 다음 라운드를 위해 base 카드 누적
                already_so_far.append(base_selections[r])

            completed += 1

    return tmp_path, completed


def merge_chunks(tmp_paths: list, output_path: str) -> int:
    total = 0
    with open(output_path, 'w', newline='', encoding='utf-8') as out_f:
        writer = csv.DictWriter(out_f, fieldnames=FIELDNAMES)
        writer.writeheader()
        for tmp_path in tmp_paths:
            if not os.path.exists(tmp_path):
                continue
            with open(tmp_path, 'r', encoding='utf-8') as in_f:
                reader = csv.DictReader(in_f)
                for row in reader:
                    writer.writerow(row)
                    total += 1
            os.remove(tmp_path)
    return total


def run_simulation(n: int = N_SIMULATIONS):
    n_cores    = mp.cpu_count()
    chunk_size = n // n_cores
    remainder  = n % n_cores

    chunks = []
    sim_id_cursor = 1
    for i in range(n_cores):
        size = chunk_size + (1 if i < remainder else 0)
        chunks.append((i, sim_id_cursor, size))
        sim_id_cursor += size

    print(f'V2 재설계 시뮬레이션 시작: {n:,}게임 / {n_cores}코어 병렬')
    print(f'게임당 최대 44 row (4라운드 × 11카드, 중복 제외)')
    print(f'코어당 약 {chunk_size:,}게임\n')

    start_time = time.time()

    with mp.Pool(processes=n_cores) as pool:
        results = []
        for idx, (tmp_path, completed) in enumerate(
            pool.imap_unordered(run_chunk, chunks)
        ):
            results.append(tmp_path)
            elapsed = time.time() - start_time
            print(f'  청크 {idx + 1}/{n_cores} 완료 — {completed:,}게임 '
                  f'({elapsed:.0f}초 경과)')

    print('\nCSV 병합 중...')
    total = merge_chunks(results, OUTPUT_PATH)

    elapsed = time.time() - start_time
    print(f'\n✅ V2 재설계 시뮬레이션 완료: {OUTPUT_PATH}')
    print(f'총 시간: {elapsed:.1f}초')
    print(f'저장 row 수: {total:,}개')
    print(f'게임 수: {n:,}개')
    print(f'게임당 평균 row: {total / max(n, 1):.1f}개')
    print(f'1게임 평균: {elapsed / max(n, 1) * 1000:.1f}ms')


if __name__ == '__main__':
    try:
        n_input = input(
            f'시뮬레이션 게임 수 입력 (기본값 {N_SIMULATIONS:,}): '
        ).strip()
        n = int(n_input) if n_input else N_SIMULATIONS
    except ValueError:
        n = N_SIMULATIONS
    run_simulation(n)
