"""
V1.5 추천 시스템 평가 (교수님 피드백 3번 반영)

3가지 평가:
  1. TOP 5 추천 조합의 실제 평균 수익률
  2. 무작위 5개 조합 대비 우수성
  3. AI TOP 5와 실제 TOP 5의 일치도
"""
import warnings
warnings.filterwarnings('ignore')

import os
import pickle
import random
import time
import numpy as np
import pandas as pd
from itertools import permutations

DATA_DIR   = os.path.join(os.path.dirname(__file__), '..', 'data', 'simulation')
DATA_PATH  = os.path.join(DATA_DIR, 'training_data_v15.csv')
MODEL_PATH = os.path.join(DATA_DIR, 'model_v15.pkl')

CARD_SELECT_ROUNDS = [1, 25, 50, 75]
ALL_CARD_IDS       = list(range(1, 12))

CARD_NAMES = {
    1: '거인의 어깨',   2: '황금 적립',     3: '공포탐욕',
    4: '금 피난처',     5: '기술의 파도',   6: '낙폭과대 사냥',
    7: '원유 베팅',     8: '역발상 투자',   9: '애플 줍줍',
    10: '채권 피난처',  11: '분할매수 장인',
}

CARD_ROUND_COLS = [
    f'Card{i}_Round{r}'
    for i in range(1, 12)
    for r in CARD_SELECT_ROUNDS
]
FEATURE_COLS = ['SPX_Return', 'SPX_Volatility'] + CARD_ROUND_COLS  # 46차원


# =============================================
# 유틸 함수
# =============================================
def make_feature(spx_return: float, spx_vol: float, card_selections: dict) -> list:
    """46차원 입력 벡터 생성"""
    enc = {col: 0 for col in CARD_ROUND_COLS}
    for round_num, card_id in card_selections.items():
        col = f'Card{card_id}_Round{round_num}'
        if col in enc:
            enc[col] = 1
    return [spx_return, spx_vol] + [enc[col] for col in CARD_ROUND_COLS]


def get_ai_top5(model, spx_return: float, spx_vol: float):
    """AI 모델로 TOP 5 추천 (배치 예측)"""
    all_combos = list(permutations(ALL_CARD_IDS, 4))
    total = len(all_combos)
    
    print(f'   feature 생성 중... (총 {total:,}개)')
    features = []
    for combo in all_combos:
        card_selections = {1: combo[0], 25: combo[1], 50: combo[2], 75: combo[3]}
        feat = make_feature(spx_return, spx_vol, card_selections)
        features.append(feat)
    
    print(f'   모델 예측 중...')
    predictions = model.predict(features)
    
    print(f'   정렬 중...')
    results = []
    for combo, pred in zip(all_combos, predictions):
        card_selections = {1: combo[0], 25: combo[1], 50: combo[2], 75: combo[3]}
        results.append((card_selections, pred))
    
    results.sort(key=lambda x: -x[1])
    return results[:5], results


def find_matching_games(df: pd.DataFrame, card_selections: dict, 
                        spx_return: float, spx_vol: float, 
                        market_tolerance: float = 5.0):
    """
    실제 데이터에서 같은 카드 조합 + 비슷한 시장 상황 게임 찾기
    """
    mask = pd.Series([True] * len(df))
    
    for round_num, card_id in card_selections.items():
        col = f'Card{card_id}_Round{round_num}'
        if col in df.columns:
            mask &= (df[col] == 1)
    
    mask &= df['SPX_Return'].between(spx_return - market_tolerance, 
                                       spx_return + market_tolerance)
    
    return df[mask]


# =============================================
# 평가 1: TOP 5 추천 실제 평균 수익률
# =============================================
def evaluate_actual_return(df, ai_top5, spx_return, spx_vol):
    """AI가 추천한 TOP 5의 실제 평균 수익률 측정"""
    print('\n' + '=' * 60)
    print(' [평가 1] TOP 5 추천 조합의 실제 평균 수익률')
    print('=' * 60)
    
    actual_returns = []
    
    for rank, (sel, predicted) in enumerate(ai_top5, 1):
        matching = find_matching_games(df, sel, spx_return, spx_vol)
        names = [CARD_NAMES[sel[r]] for r in CARD_SELECT_ROUNDS]
        
        if len(matching) > 0:
            actual_avg = matching['Final_Return'].mean()
            actual_returns.append(actual_avg)
            print(f' {rank}위: 예측 {predicted:+.2f}% / 실제 {actual_avg:+.2f}% '
                  f'({len(matching)}건)')
        else:
            print(f' {rank}위: 예측 {predicted:+.2f}% / 실제 데이터 없음')
        print(f'     {", ".join(names)}')
    
    if actual_returns:
        avg_predicted = np.mean([p for _, p in ai_top5])
        avg_actual = np.mean(actual_returns)
        print(f'\n TOP 5 예측 평균: {avg_predicted:+.2f}%')
        print(f' TOP 5 실제 평균: {avg_actual:+.2f}%')
        print(f' 예측 오차:       {abs(avg_predicted - avg_actual):.2f}%p')
        return avg_actual
    return None


# =============================================
# 평가 2: 랜덤 5개 조합 대비 우수성
# =============================================
def evaluate_random_comparison(df, ai_top5, spx_return, spx_vol, 
                                  n_trials: int = 100):
    """랜덤하게 뽑은 5개 조합과 AI TOP 5 비교"""
    print('\n' + '=' * 60)
    print(' [평가 2] 무작위 5개 조합 대비 AI 추천의 우수성')
    print('=' * 60)
    
    # AI TOP 5 실제 평균
    ai_returns = []
    for sel, _ in ai_top5:
        matching = find_matching_games(df, sel, spx_return, spx_vol)
        if len(matching) > 0:
            ai_returns.append(matching['Final_Return'].mean())
    
    ai_avg = np.mean(ai_returns) if ai_returns else 0
    
    # 랜덤 5개 조합
    print(f' 랜덤 비교 진행 중... ({n_trials}회)')
    random_avgs = []
    
    for trial in range(n_trials):
        if (trial + 1) % 20 == 0:
            print(f'   {trial+1}/{n_trials} 완료')
        
        random_combos = []
        for _ in range(5):
            combo = random.sample(ALL_CARD_IDS, 4)
            sel = {1: combo[0], 25: combo[1], 50: combo[2], 75: combo[3]}
            random_combos.append(sel)
        
        trial_returns = []
        for sel in random_combos:
            matching = find_matching_games(df, sel, spx_return, spx_vol)
            if len(matching) > 0:
                trial_returns.append(matching['Final_Return'].mean())
        
        if trial_returns:
            random_avgs.append(np.mean(trial_returns))
    
    random_avg = np.mean(random_avgs) if random_avgs else 0
    
    print(f'\n AI TOP 5 실제 평균:  {ai_avg:+.2f}%')
    print(f' 랜덤 5개 평균 ({n_trials}회): {random_avg:+.2f}%')
    print(f' AI 우수성:           {ai_avg - random_avg:+.2f}%p')
    
    if ai_avg > random_avg:
        print(f' ✅ AI 추천이 랜덤보다 평균 {ai_avg - random_avg:.2f}%p 우수')
    else:
        print(f' ⚠️  AI 추천이 랜덤과 비슷하거나 못함 (모델 개선 필요)')
    
    return ai_avg, random_avg


# =============================================
# 평가 3: 진짜 TOP 5와 일치도
# =============================================
def evaluate_match_with_true_top(df, ai_top5, spx_return, spx_vol):
    """AI TOP 5와 실제 데이터 기반 진짜 TOP 5의 일치도"""
    print('\n' + '=' * 60)
    print(' [평가 3] AI TOP 5 vs 실제 TOP 5 일치도')
    print('=' * 60)
    
    # 모든 순열의 실제 평균 수익률 계산
    all_perms = list(permutations(ALL_CARD_IDS, 4))
    total = len(all_perms)
    print(f' 실제 TOP 5 계산 중... (총 {total:,}개 순열 검사)')
    
    all_combos_actual = []
    
    for i, combo in enumerate(all_perms):
        if (i + 1) % 1000 == 0:
            print(f'   {i+1:,}/{total:,} ({(i+1)/total*100:.0f}%)')
        
        sel = {1: combo[0], 25: combo[1], 50: combo[2], 75: combo[3]}
        matching = find_matching_games(df, sel, spx_return, spx_vol)
        
        if len(matching) >= 1:
            actual_avg = matching['Final_Return'].mean()
            all_combos_actual.append((sel, actual_avg, len(matching)))
    
    print(f'   완료! (실제 데이터 있는 조합: {len(all_combos_actual):,}개)')
    
    all_combos_actual.sort(key=lambda x: -x[1])
    true_top5 = all_combos_actual[:5]
    
    # 출력
    print('\n [실제 TOP 5 (시뮬레이션 데이터 기반)]')
    for rank, (sel, actual, count) in enumerate(true_top5, 1):
        names = [CARD_NAMES[sel[r]] for r in CARD_SELECT_ROUNDS]
        print(f'  {rank}위: 실제 {actual:+.2f}% ({count}건)')
        print(f'      {", ".join(names)}')
    
    print('\n [AI TOP 5 (모델 예측 기반)]')
    for rank, (sel, predicted) in enumerate(ai_top5, 1):
        names = [CARD_NAMES[sel[r]] for r in CARD_SELECT_ROUNDS]
        print(f'  {rank}위: 예측 {predicted:+.2f}%')
        print(f'      {", ".join(names)}')
    
    # 일치도 계산
    true_top5_keys = set()
    for sel, _, _ in true_top5:
        key = tuple(sorted(sel.items()))
        true_top5_keys.add(key)
    
    ai_top5_keys = set()
    for sel, _ in ai_top5:
        key = tuple(sorted(sel.items()))
        ai_top5_keys.add(key)
    
    matched = true_top5_keys & ai_top5_keys
    match_count = len(matched)
    match_rate = match_count / 5 * 100
    
    print(f'\n 일치 개수: {match_count}/5')
    print(f' 일치율:   {match_rate:.1f}%')
    
    if match_count >= 3:
        print(f' ✅ AI 추천이 실제 최적과 잘 일치')
    elif match_count >= 1:
        print(f' ⚠️  부분 일치 (개선 여지 있음)')
    else:
        print(f' ❌ 실제 최적과 거의 일치 안함 (모델 개선 필요)')
    
    return match_count, true_top5


# =============================================
# 메인
# =============================================
def main():
    if not os.path.exists(DATA_PATH):
        print(f'❌ 학습 데이터 없음: {DATA_PATH}')
        print('먼저 monte_carlo.py를 실행하세요.')
        return
    
    if not os.path.exists(MODEL_PATH):
        print(f'❌ 모델 없음: {MODEL_PATH}')
        print('먼저 recommend_v15.py를 실행하세요.')
        return
    
    print('=' * 60)
    print(' V1.5 추천 시스템 평가 (교수님 피드백 3번)')
    print('=' * 60)
    
    # 데이터 + 모델 로드
    df = pd.read_csv(DATA_PATH)
    print(f' 데이터 로드: {len(df):,}건')
    
    with open(MODEL_PATH, 'rb') as f:
        model = pickle.load(f)
    print(f' 모델 로드 완료')
    
    # 평가할 시장 상황 입력
    print('\n' + '-' * 60)
    print(' 평가할 시장 상황 입력')
    print('-' * 60)
    
    try:
        spx_return = float(input(' SPX 수익률 (%) [-30]: ') or '-30')
        spx_vol = float(input(' SPX 변동성 [3.5]: ') or '3.5')
    except ValueError:
        print('❌ 잘못된 입력')
        return
    
    print(f'\n 평가 대상: 시장 {spx_return:+.1f}%, 변동성 {spx_vol}')
    
    start_time = time.time()
    
    # AI TOP 5 추천 받기
    print('\n AI TOP 5 추천 계산 중...')
    ai_top5, _ = get_ai_top5(model, spx_return, spx_vol)
    
    # 평가 1
    evaluate_actual_return(df, ai_top5, spx_return, spx_vol)
    
    # 평가 2
    evaluate_random_comparison(df, ai_top5, spx_return, spx_vol, n_trials=100)
    
    # 평가 3
    evaluate_match_with_true_top(df, ai_top5, spx_return, spx_vol)
    
    elapsed = time.time() - start_time
    print('\n' + '=' * 60)
    print(f' 평가 완료 (소요 시간: {elapsed:.1f}초)')
    print('=' * 60)


if __name__ == '__main__':
    main()