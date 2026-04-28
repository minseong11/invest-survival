"""
몬테카를로 시뮬레이션 — 학습 데이터 생성
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
OUTPUT_PATH = os.path.join(OUTPUT_DIR, 'training_data.csv')

ALL_CARD_IDS       = list(CARDS.keys())   # [1..11]
CARD_SELECT_ROUNDS = [1, 25, 50, 75]
SIM_START          = datetime(2007, 9, 1)
SIM_END            = datetime(2009, 6, 1)  # 100라운드 확보 위해 여유


def random_start_date() -> str:
    """2007-09-01 ~ 2009-06-01 사이 랜덤 날짜"""
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


def run_simulation(n: int = 1000):
    start_time = time.time()
    fieldnames = [
        'sim_id', 'scenario_id', 'start_date',
        'SPX_Return', 'SPX_Volatility',
        *[f'Card{i}_Active' for i in range(1, 12)],
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

            # 카드 선택 (각 라운드마다 11개 중 3개 뽑고 1개 선택)
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

            card_active = {f'Card{i}_Active': (1 if i in selected_ids else 0) for i in range(1, 12)}

            row = {
                'sim_id':         sim_id,
                'scenario_id':    'lehman',
                'start_date':     start_date,
                'SPX_Return':     spx_return,
                'SPX_Volatility': spx_vol,
                **card_active,
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
    print(f'1만 회 예상: {elapsed/max(completed,1)*10000:.0f}초')


if __name__ == '__main__':
    try:
        n = int(input('시뮬레이션 횟수 입력 (예: 1000): ') or 1000)
    except ValueError:
        n = 1000
    run_simulation(n)
