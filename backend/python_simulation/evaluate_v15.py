"""
V1.5 추천 시스템 평가 (교수님 피드백 3번 반영)

3가지 평가:
  1. TOP 5 추천 조합의 실제 평균/중앙값 수익률
  2. 무작위 5개 조합 대비 우수성 (평균/중앙값)
  3. AI TOP 5와 실제 TOP 5의 일치도

※ 매칭 조건은 교수님 제안대로 SPX_Return만 사용
※ 모델 예측 시 SPX_MDD 포함 (47차원)
※ 평가 3은 최소 매칭 건수(MIN_MATCH_COUNT) 이상만 실제 TOP 후보로 사용
※ 중앙값 병기 (교수님 피드백 2-B: fat tail 강건성)
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

# 평가 3: 실제 TOP 후보로 인정할 최소 매칭 건수
# 1건짜리 운빨 조합을 제외하여 통계적 신뢰성 확보
MIN_MATCH_COUNT = 3

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
# SPX_MDD 포함 47차원
FEATURE_COLS = ['SPX_Return', 'SPX_Volatility', 'SPX_MDD'] + CARD_ROUND_COLS


# =============================================
# 유틸 함수
# =============================================
def make_feature(spx_return: float, spx_vol: float, spx_mdd: float,
                 card_selections: dict) -> list:
    """47차원 입력 벡터 생성"""
    enc = {col: 0 for col in CARD_ROUND_COLS}
    for round_num, card_id in card_selections.items():
        col = f'Card{card_id}_Round{round_num}'
        if col in enc:
            enc[col] = 1
    return [spx_return, spx_vol, spx_mdd] + [enc[col] for col in CARD_ROUND_COLS]


def get_ai_top5(model, spx_return: float, spx_vol: float, spx_mdd: float):
    """AI 모델로 TOP 5 추천 (배치 예측)"""
    all_combos = list(permutations(ALL_CARD_IDS, 4))
    total = len(all_combos)

    print(f'   feature 생성 중... (총 {total:,}개)')
    features = []
    for combo in all_combos:
        card_selections = {1: combo[0], 25: combo[1], 50: combo[2], 75: combo[3]}
        feat = make_feature(spx_return, spx_vol, spx_mdd, card_selections)
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
                        spx_return: float,
                        market_tolerance: float = 5.0):
    """
    실제 데이터에서 같은 카드 조합 + 비슷한 시장 수익률 게임 찾기
    ※ 교수님 제안: 매칭 조건은 SPX_Return만 사용
    """
    mask = pd.Series([True] * len(df), index=df.index)

    for round_num, card_id in card_selections.items():
        col = f'Card{card_id}_Round{round_num}'
        if col in df.columns:
            mask &= (df[col] == 1)

    mask &= df['SPX_Return'].between(spx_return - market_tolerance,
                                      spx_return + market_tolerance)

    return df[mask]


# =============================================
# 평가 1: TOP 5 추천 실제 평균/중앙값 수익률
# =============================================
def evaluate_actual_return(df, ai_top5, spx_return):
    """AI가 추천한 TOP 5의 실제 평균/중앙값 수익률 측정"""
    print('\n' + '=' * 60)
    print(' [평가 1] TOP 5 추천 조합의 실제 평균/중앙값 수익률')
    print('=' * 60)

    actual_means   = []
    actual_medians = []

    for rank, (sel, predicted) in enumerate(ai_top5, 1):
        matching = find_matching_games(df, sel, spx_return)
        names = [CARD_NAMES[sel[r]] for r in CARD_SELECT_ROUNDS]

        if len(matching) > 0:
            actual_avg    = matching['Final_Return'].mean()
            actual_median = matching['Final_Return'].median()
            actual_means.append(actual_avg)
            actual_medians.append(actual_median)
            print(f' {rank}위: 예측 {predicted:+.2f}% / '
                  f'실제 평균 {actual_avg:+.2f}% / 중앙값 {actual_median:+.2f}% '
                  f'({len(matching)}건)')
        else:
            print(f' {rank}위: 예측 {predicted:+.2f}% / 실제 데이터 없음')
        print(f'     {", ".join(names)}')

    if actual_means:
        avg_predicted  = np.mean([p for _, p in ai_top5])
        avg_actual     = np.mean(actual_means)
        median_actual  = np.median(actual_medians)
        print(f'\n TOP 5 예측 평균:    {avg_predicted:+.2f}%')
        print(f' TOP 5 실제 평균:    {avg_actual:+.2f}%')
        print(f' TOP 5 실제 중앙값:  {median_actual:+.2f}%')
        print(f' 예측 오차 (평균):   {abs(avg_predicted - avg_actual):.2f}%p')
        print(f' 예측 오차 (중앙값): {abs(avg_predicted - median_actual):.2f}%p')
        return avg_actual, median_actual
    return None, None


# =============================================
# 평가 2: 랜덤 5개 조합 대비 우수성 (평균/중앙값)
# =============================================
def evaluate_random_comparison(df, ai_top5, spx_return, n_trials: int = 100):
    """랜덤하게 뽑은 5개 조합과 AI TOP 5 비교 (평균/중앙값)"""
    print('\n' + '=' * 60)
    print(' [평가 2] 무작위 5개 조합 대비 AI 추천의 우수성')
    print('=' * 60)

    # AI TOP 5 실제 평균/중앙값
    ai_means   = []
    ai_medians = []
    for sel, _ in ai_top5:
        matching = find_matching_games(df, sel, spx_return)
        if len(matching) > 0:
            ai_means.append(matching['Final_Return'].mean())
            ai_medians.append(matching['Final_Return'].median())

    ai_avg    = np.mean(ai_means)      if ai_means   else 0
    ai_median = np.median(ai_medians)  if ai_medians else 0

    # 랜덤 5개 조합
    print(f' 랜덤 비교 진행 중... ({n_trials}회)')
    random_means   = []
    random_medians = []

    for trial in range(n_trials):
        if (trial + 1) % 20 == 0:
            print(f'   {trial+1}/{n_trials} 완료')

        random_combos = []
        for _ in range(5):
            combo = random.sample(ALL_CARD_IDS, 4)
            sel = {1: combo[0], 25: combo[1], 50: combo[2], 75: combo[3]}
            random_combos.append(sel)

        trial_means   = []
        trial_medians = []
        for sel in random_combos:
            matching = find_matching_games(df, sel, spx_return)
            if len(matching) > 0:
                trial_means.append(matching['Final_Return'].mean())
                trial_medians.append(matching['Final_Return'].median())

        if trial_means:
            random_means.append(np.mean(trial_means))
            random_medians.append(np.median(trial_medians))

    random_avg    = np.mean(random_means)      if random_means   else 0
    random_median = np.median(random_medians)  if random_medians else 0

    print(f'\n [평균 기준]')
    print(f'   AI TOP 5 실제 평균:       {ai_avg:+.2f}%')
    print(f'   랜덤 5개 평균 ({n_trials}회):    {random_avg:+.2f}%')
    print(f'   AI 우수성:                {ai_avg - random_avg:+.2f}%p')

    print(f'\n [중앙값 기준] (fat tail 강건)')
    print(f'   AI TOP 5 실제 중앙값:     {ai_median:+.2f}%')
    print(f'   랜덤 5개 중앙값 ({n_trials}회):  {random_median:+.2f}%')
    print(f'   AI 우수성:                {ai_median - random_median:+.2f}%p')

    if ai_avg > random_avg:
        print(f'\n ✅ AI 추천이 랜덤보다 평균 {ai_avg - random_avg:.2f}%p 우수')
    else:
        print(f'\n ⚠️  AI 추천이 랜덤과 비슷하거나 못함 (모델 개선 필요)')

    return ai_avg, random_avg, ai_median, random_median


# =============================================
# 평가 3: 진짜 TOP 5와 일치도
# =============================================
def evaluate_match_with_true_top(df, ai_top5, spx_return):
    """
    AI TOP 5와 실제 데이터 기반 진짜 TOP 5의 일치도

    ※ 개선: 최소 MIN_MATCH_COUNT건 이상 매칭된 조합만 실제 TOP 후보로 사용
       1건짜리 운빨 조합을 제외하여 통계적 신뢰성 확보
    """
    print('\n' + '=' * 60)
    print(' [평가 3] AI TOP 5 vs 실제 TOP 5 일치도')
    print('=' * 60)
    print(f' (실제 TOP 후보 조건: 최소 {MIN_MATCH_COUNT}건 이상 매칭)')

    all_perms = list(permutations(ALL_CARD_IDS, 4))
    total = len(all_perms)
    print(f' 실제 TOP 5 계산 중... (총 {total:,}개 순열 검사)')

    all_combos_actual = []
    excluded_count = 0  # MIN_MATCH_COUNT 미만으로 제외된 조합 수

    for i, combo in enumerate(all_perms):
        if (i + 1) % 1000 == 0:
            print(f'   {i+1:,}/{total:,} ({(i+1)/total*100:.0f}%)')

        sel = {1: combo[0], 25: combo[1], 50: combo[2], 75: combo[3]}
        matching = find_matching_games(df, sel, spx_return)

        if len(matching) >= MIN_MATCH_COUNT:
            actual_avg    = matching['Final_Return'].mean()
            actual_median = matching['Final_Return'].median()
            all_combos_actual.append((sel, actual_avg, actual_median, len(matching)))
        elif len(matching) >= 1:
            excluded_count += 1

    print(f'   완료!')
    print(f'   실제 TOP 후보 ({MIN_MATCH_COUNT}건 이상): {len(all_combos_actual):,}개')
    print(f'   제외된 조합 (1~{MIN_MATCH_COUNT-1}건): {excluded_count:,}개')

    if len(all_combos_actual) == 0:
        print(f'\n ⚠️  {MIN_MATCH_COUNT}건 이상 매칭된 조합이 없어 평가 불가')
        print(f'    시뮬레이션 데이터 확장이 필요합니다.')
        return 0, []

    # 실제 평균 기준 정렬
    all_combos_actual.sort(key=lambda x: -x[1])
    true_top5 = all_combos_actual[:5]

    print(f'\n [실제 TOP 5 (시뮬레이션 데이터 기반, 최소 {MIN_MATCH_COUNT}건 이상)]')
    for rank, (sel, actual, median, count) in enumerate(true_top5, 1):
        names = [CARD_NAMES[sel[r]] for r in CARD_SELECT_ROUNDS]
        print(f'  {rank}위: 실제 평균 {actual:+.2f}% / 중앙값 {median:+.2f}% ({count}건)')
        print(f'      {", ".join(names)}')

    print('\n [AI TOP 5 (모델 예측 기반)]')
    for rank, (sel, predicted) in enumerate(ai_top5, 1):
        names = [CARD_NAMES[sel[r]] for r in CARD_SELECT_ROUNDS]
        print(f'  {rank}위: 예측 {predicted:+.2f}%')
        print(f'      {", ".join(names)}')

    # 일치도 계산
    true_top5_keys = set()
    for sel, _, _, _ in true_top5:
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
        spx_vol    = float(input(' SPX 변동성 [3.5]: ')    or '3.5')
        spx_mdd    = float(input(' SPX MDD (%) [-35]: ')   or '-35')
    except ValueError:
        print('❌ 잘못된 입력')
        return

    print(f'\n 평가 대상: 시장 {spx_return:+.1f}%, 변동성 {spx_vol}, MDD {spx_mdd:+.1f}%')

    start_time = time.time()

    # AI TOP 5 추천 받기
    print('\n AI TOP 5 추천 계산 중...')
    ai_top5, _ = get_ai_top5(model, spx_return, spx_vol, spx_mdd)

    # 평가 1 (매칭: SPX_Return만)
    evaluate_actual_return(df, ai_top5, spx_return)

    # 평가 2 (매칭: SPX_Return만)
    evaluate_random_comparison(df, ai_top5, spx_return, n_trials=100)

    # 평가 3 (매칭: SPX_Return만, 최소 MIN_MATCH_COUNT건)
    evaluate_match_with_true_top(df, ai_top5, spx_return)

    elapsed = time.time() - start_time
    print('\n' + '=' * 60)
    print(f' 평가 완료 (소요 시간: {elapsed:.1f}초)')
    print('=' * 60)


if __name__ == '__main__':
    main()