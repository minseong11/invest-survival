"""
몬테카를로 시뮬레이션 V2 — 라운드별 스냅샷 데이터 생성
실시간 추천 모델(V2) 학습용

V1.5와 차이:
  V1.5: 게임당 1 row (4개 카드 완성 상태) → 사후 평가용
  V2:   게임당 4 row (라운드별 스냅샷)    → 실시간 추천용

V2 입력 25차원:
  시장 정보 3개: SPX_Return_so_far, SPX_Volatility_so_far, SPX_MDD_so_far
  진행 상황 1개: current_round (1, 25, 50, 75)
  이미 선택한 카드 11개: Already_Card1~11 (multi-hot)
  이번 선택 카드 11개: Selected_Card_1~11 (one-hot)
  출력: Final_Return (회귀)
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

ALL_CARD_IDS       = list(CARDS.keys())          # [1, 2, ..., 11]
CARD_SELECT_ROUNDS = [1, 25, 50, 75]
SIM_START          = datetime(2007, 9, 1)
SIM_END            = datetime(2009, 6, 1)
N_SIMULATIONS      = 100_000   # 게임 수 (row는 4배인 40만)ㄴㄴㄴ

# 컬럼 정의
ALREADY_COLS  = [f'Already_Card{i}' for i in range(1, 12)]   # 11개
SELECTED_COLS = [f'Selected_Card_{i}' for i in range(1, 12)] # 11개

FIELDNAMES = [
    'sim_id', 'scenario_id', 'start_date',
    'current_round',
    'SPX_Return_so_far', 'SPX_Volatility_so_far', 'SPX_MDD_so_far',
    *ALREADY_COLS,
    *SELECTED_COLS,
    'Final_Return',
]


# ── 날짜 헬퍼 ────────────────────────────────────────────
def random_start_date() -> str:
    delta = (SIM_END - SIM_START).days
    rand_day = SIM_START + timedelta(days=random.randint(0, delta))
    return rand_day.strftime('%Y-%m-%d')


# ── 시장 지표 계산 ────────────────────────────────────────
def calc_spx_so_far(closes: np.ndarray, up_to_idx: int):
    """
    closes: 전체 100라운드 종가 배열
    up_to_idx: 현재 라운드까지의 인덱스 (exclusive)
    returns: (return_so_far, volatility_so_far, mdd_so_far)
    """
    sub = closes[:up_to_idx]
    if len(sub) < 2:
        return 0.0, 0.0, 0.0

    ret = (sub[-1] - sub[0]) / sub[0] * 100
    daily = np.diff(sub) / sub[:-1] * 100
    vol   = float(np.std(daily)) if len(daily) > 0 else 0.0

    cumul       = sub / sub[0]
    rolling_max = np.maximum.accumulate(cumul)
    drawdowns   = (cumul - rolling_max) / rolling_max * 100
    mdd         = float(drawdowns.min())

    return round(float(ret), 4), round(vol, 4), round(mdd, 4)


# ── 인코딩 헬퍼 ──────────────────────────────────────────
def make_already_encoding(selected_so_far: list) -> dict:
    """이미 선택한 카드 multi-hot 인코딩"""
    enc = {col: 0 for col in ALREADY_COLS}
    for card_id in selected_so_far:
        col = f'Already_Card{card_id}'
        if col in enc:
            enc[col] = 1
    return enc


def make_selected_encoding(card_id: int) -> dict:
    """이번 라운드 선택 카드 one-hot 인코딩"""
    enc = {col: 0 for col in SELECTED_COLS}
    col = f'Selected_Card_{card_id}'
    if col in enc:
        enc[col] = 1
    return enc


# ── 청크 워커 ────────────────────────────────────────────
def run_chunk(args):
    """
    병렬 워커 — 게임 청크 단위 실행 후 임시 CSV 경로 반환
    args: (chunk_id, sim_id_start, chunk_size)
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

            # 카드 선택 (각 라운드마다 3개 뽑고 1개 선택, 중복 없이)
            selected_ids    = []
            card_selections = {}
            for r in CARD_SELECT_ROUNDS:
                pool    = [c for c in ALL_CARD_IDS if c not in selected_ids]
                if len(pool) < 3:
                    pool = ALL_CARD_IDS.copy()
                options = random.sample(pool, min(3, len(pool)))
                chosen  = random.choice(options)
                card_selections[r] = chosen
                selected_ids.append(chosen)

            # 게임 실행 → Final_Return
            try:
                result = run_game(start_date, card_selections)
            except Exception:
                continue

            final_return = result['final_return_rate']

            # 라운드별 스냅샷 4 row 생성
            round_to_idx   = {1: 1, 25: 25, 50: 50, 75: 75}
            already_so_far = []  # 이전 라운드들에서 선택한 카드 누적

            for r in CARD_SELECT_ROUNDS:
                up_to_idx = round_to_idx[r]
                ret_so_far, vol_so_far, mdd_so_far = calc_spx_so_far(
                    closes, up_to_idx
                )

                selected_card = card_selections[r]
                already_enc   = make_already_encoding(already_so_far)
                selected_enc  = make_selected_encoding(selected_card)

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
                    'Final_Return':          final_return,
                }
                writer.writerow(row)

                # 다음 라운드를 위해 이번 선택 카드 누적
                already_so_far.append(selected_card)

            completed += 1

    return tmp_path, completed


# ── CSV 병합 ─────────────────────────────────────────────
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


# ── 메인 ─────────────────────────────────────────────────
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

    print(f'V2 시뮬레이션 시작: {n:,}게임 / {n_cores}코어 병렬')
    print(f'예상 총 row 수: {n * 4:,}개 (게임당 4 row)')
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
                  f'({completed * 4:,} row) ({elapsed:.0f}초 경과)')

    print('\nCSV 병합 중...')
    total = merge_chunks(results, OUTPUT_PATH)

    elapsed = time.time() - start_time
    print(f'\n✅ V2 시뮬레이션 완료: {OUTPUT_PATH}')
    print(f'총 시간: {elapsed:.1f}초')
    print(f'저장 row 수: {total:,}개')
    print(f'게임 수: {total // 4:,}개')
    print(f'1게임 평균: {elapsed / max(total // 4, 1) * 1000:.1f}ms')


if __name__ == '__main__':
    try:
        n_input = input(
            f'시뮬레이션 게임 수 입력 (기본값 {N_SIMULATIONS:,}): '
        ).strip()
        n = int(n_input) if n_input else N_SIMULATIONS
    except ValueError:
        n = N_SIMULATIONS
    run_simulation(n)