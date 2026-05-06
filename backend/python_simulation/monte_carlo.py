"""
몬테카를로 시뮬레이션 — V1.5 학습 데이터 생성
카드 선택 시점 인코딩: Card{i}_Round{r} 44차원
"""
import os
import random
import csv
import time
import numpy as np
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

# V1.5 컬럼: Card{i}_Round{r} 44개
CARD_ROUND_COLS = [
    f'Card{i}_Round{r}'
    for i in range(1, 12)
    for r in CARD_SELECT_ROUNDS
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


def run_simulation(n: int = 1000):
    start_time = time.time()
    fieldnames = [
        'sim_id', 'scenario_id', 'start_date',
        'SPX_Return', 'SPX_Volatility',
        *CARD_ROUND_COLS,
        'Final_Return'
    ]

    with open(OUTPUT_PATH, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()

        completed = 0
        for sim_id in range(1, n + 1):
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

            # V1.5 인코딩
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

            if sim_id % 100 == 0:
                elapsed = time.time() - start_time
                est_total = elapsed / sim_id * n
                print(f'  {sim_id}/{n} 완료 ({elapsed:.0f}초 경과, 예상 총 {est_total:.0f}초)')

    elapsed = time.time() - start_time
    print(f'\n시뮬레이션 완료: {OUTPUT_PATH}')
    print(f'총 시간: {elapsed:.1f}초  /  1회 평균: {elapsed/max(completed,1)*1000:.1f}ms')
    print(f'저장 건수: {completed}건')


if __name__ == '__main__':
    try:
        n = int(input('시뮬레이션 횟수 입력 (예: 1000): ') or 1000)
    except ValueError:
        n = 1000
    run_simulation(n)
