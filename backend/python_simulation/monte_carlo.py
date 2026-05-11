"""
몬테카를로 시뮬레이션 — V1.5 학습 데이터 생성
카드 선택 시점 인코딩: Card{i}_Round{r} 44차원
10만 건 확장 + multiprocessing 병렬화
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

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), '..', 'data', 'simulation')
os.makedirs(OUTPUT_DIR, exist_ok=True)
OUTPUT_PATH = os.path.join(OUTPUT_DIR, 'training_data_v15.csv')

ALL_CARD_IDS       = list(CARDS.keys())
CARD_SELECT_ROUNDS = [1, 25, 50, 75]
SIM_START          = datetime(2007, 9, 1)
SIM_END            = datetime(2009, 6, 1)
N_SIMULATIONS      = 100_000   # 기본 시뮬레이션 횟수

# V1.5 컬럼: Card{i}_Round{r} 44개
CARD_ROUND_COLS = [
    f'Card{i}_Round{r}'
    for i in range(1, 12)
    for r in CARD_SELECT_ROUNDS
]

FIELDNAMES = [
    'sim_id', 'scenario_id', 'start_date',
    'SPX_Return', 'SPX_Volatility',
    *CARD_ROUND_COLS,
    'Final_Return'
]


def random_start_date() -> str:
    delta = (SIM_END - SIM_START).days
    rand_day = SIM_START + timedelta(days=random.randint(0, delta))
    return rand_day.strftime('%Y-%m-%d')


def calc_spx_stats(start_date: str):
    """SPX 100라운드 수익률 및 변동성 계산"""
    spx = get_price_list(start_date, '^SPX')
    if len(spx) < 100:
        return None, None
    closes = spx.iloc[:100]['Close'].values
    total_return = (closes[-1] - closes[0]) / closes[0] * 100
    daily_returns = np.diff(closes) / closes[:-1] * 100
    volatility = float(np.std(daily_returns))
    return round(float(total_return), 4), round(volatility, 4)


def make_card_round_encoding(card_selections: dict) -> dict:
    """
    card_selections: {1: 3, 25: 5, 50: 8, 75: 11}
    -> Card3_Round1=1, Card5_Round25=1, ... 나머지 0
    """
    encoding = {col: 0 for col in CARD_ROUND_COLS}
    for round_num, card_id in card_selections.items():
        col = f'Card{card_id}_Round{round_num}'
        if col in encoding:
            encoding[col] = 1
    return encoding


def run_chunk(args):
    """
    병렬 워커 함수 — 시뮬레이션 청크 단위 실행 후 임시 CSV 경로 반환
    args: (chunk_id, sim_id_start, chunk_size)
    """
    chunk_id, sim_id_start, chunk_size = args
    random.seed(chunk_id)  # 청크별 시드 고정으로 재현성 확보

    tmp_path = os.path.join(
        tempfile.gettempdir(),
        f'mc_chunk_{chunk_id}.csv'
    )

    with open(tmp_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=FIELDNAMES)
        writer.writeheader()

        completed = 0
        for i in range(chunk_size):
            sim_id = sim_id_start + i
            start_date = random_start_date()

            spx_return, spx_vol = calc_spx_stats(start_date)
            if spx_return is None:
                continue

            # 카드 선택 (각 라운드마다 3개 뽑고 1개 선택, 중복 없이)
            selected_ids = []
            card_selections = {}
            for r in CARD_SELECT_ROUNDS:
                pool = [c for c in ALL_CARD_IDS if c not in selected_ids]
                if len(pool) < 3:
                    pool = ALL_CARD_IDS.copy()
                options = random.sample(pool, min(3, len(pool)))
                chosen  = random.choice(options)
                card_selections[r] = chosen
                selected_ids.append(chosen)

            try:
                result = run_game(start_date, card_selections)
            except Exception:
                continue

            card_round_enc = make_card_round_encoding(card_selections)

            row = {
                'sim_id':         sim_id,
                'scenario_id':    'lehman',
                'start_date':     start_date,
                'SPX_Return':     spx_return,
                'SPX_Volatility': spx_vol,
                **card_round_enc,
                'Final_Return':   result['final_return_rate'],
            }
            writer.writerow(row)
            completed += 1

    return tmp_path, completed


def merge_chunks(tmp_paths: list, output_path: str) -> int:
    """임시 CSV 파일들을 하나로 병합"""
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
            os.remove(tmp_path)  # 임시 파일 삭제

    return total


def run_simulation(n: int = N_SIMULATIONS):
    n_cores = mp.cpu_count()
    chunk_size = n // n_cores
    remainder  = n % n_cores

    # 청크 분배: (chunk_id, sim_id_start, chunk_size)
    chunks = []
    sim_id_cursor = 1
    for i in range(n_cores):
        size = chunk_size + (1 if i < remainder else 0)
        chunks.append((i, sim_id_cursor, size))
        sim_id_cursor += size

    print(f'시뮬레이션 시작: {n:,}건 / {n_cores}코어 병렬')
    print(f'코어당 약 {chunk_size:,}건\n')

    start_time = time.time()

    with mp.Pool(processes=n_cores) as pool:
        results = []
        for idx, (tmp_path, completed) in enumerate(pool.imap_unordered(run_chunk, chunks)):
            results.append(tmp_path)
            elapsed = time.time() - start_time
            print(f'  청크 {idx + 1}/{n_cores} 완료 — {completed:,}건 ({elapsed:.0f}초 경과)')

    print('\nCSV 병합 중...')
    total = merge_chunks(results, OUTPUT_PATH)

    elapsed = time.time() - start_time
    print(f'\n✅ 시뮬레이션 완료: {OUTPUT_PATH}')
    print(f'총 시간: {elapsed:.1f}초')
    print(f'저장 건수: {total:,}건')
    print(f'1회 평균: {elapsed / max(total, 1) * 1000:.1f}ms')


if __name__ == '__main__':
    try:
        n_input = input(f'시뮬레이션 횟수 입력 (기본값 {N_SIMULATIONS:,}): ').strip()
        n = int(n_input) if n_input else N_SIMULATIONS
    except ValueError:
        n = N_SIMULATIONS
    run_simulation(n)
