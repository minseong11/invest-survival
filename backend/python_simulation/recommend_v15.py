"""
V1.5 - 카드 선택 시점 인코딩 (44차원) 기반 RandomForest 모델

구조:
  입력 46차원: SPX_Return, SPX_Volatility + Card{i}_Round{r} 44개
  출력: Final_Return (회귀)

기능:
  1. 모델 학습 + 정량 평가 (R2, MAE, RMSE, 베이스라인 비교)
  2. 데이터 분포 분석 (교수님 피드백 5번 반영)
  3. TOP 5 추천 + 3가지 추천 평가
"""
import os
import pickle
import random
import numpy as np
import pandas as pd
from itertools import permutations
from sklearn.ensemble import RandomForestRegressor
from sklearn.linear_model import LinearRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

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
# 1. 데이터 분포 분석
# =============================================
def analyze_distribution(df: pd.DataFrame):
    """Final_Return 분포 분석 (교수님 피드백 5번 반영)"""
    ret = df['Final_Return']
    print('\n===== 데이터 분포 분석 =====')
    print(f'총 데이터: {len(df):,}건')
    print(f'평균:     {ret.mean():.4f}%')
    print(f'중앙값:   {ret.median():.4f}%')
    print(f'표준편차: {ret.std():.4f}%')
    print(f'최솟값:   {ret.min():.4f}%')
    print(f'최댓값:   {ret.max():.4f}%')
    positive = (ret > 0).sum()
    negative = (ret <= 0).sum()
    print(f'양수 수익률: {positive:,}건 ({positive/len(df)*100:.1f}%)')
    print(f'음수 수익률: {negative:,}건 ({negative/len(df)*100:.1f}%)')
    print(f'SPX_Return 평균: {df["SPX_Return"].mean():.4f}%')
    print(f'SPX_Volatility 평균: {df["SPX_Volatility"].mean():.4f}')


# =============================================
# 2. 모델 학습 + 평가
# =============================================
def train_and_evaluate(df: pd.DataFrame):
    """V1.5 RandomForest 학습 + 베이스라인 비교"""
    X = df[FEATURE_COLS].values
    y = df['Final_Return'].values

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    print(f'\n===== 모델 학습 =====')
    print(f'학습: {len(X_train):,}건  /  테스트: {len(X_test):,}건')
    print(f'입력 차원: {X.shape[1]}차원 (SPX 2 + 카드시점 44)')

    # 베이스라인 1: 평균 예측
    mean_pred = np.full_like(y_test, y_train.mean())
    r2_mean   = r2_score(y_test, mean_pred)
    mae_mean  = mean_absolute_error(y_test, mean_pred)
    print(f'\n[베이스라인 - 평균 예측]')
    print(f'  R2: {r2_mean:.4f}  MAE: {mae_mean:.4f}%')

    # 베이스라인 2: 선형 회귀
    lr = LinearRegression()
    lr.fit(X_train, y_train)
    lr_pred = lr.predict(X_test)
    r2_lr   = r2_score(y_test, lr_pred)
    mae_lr  = mean_absolute_error(y_test, lr_pred)
    print(f'\n[베이스라인 - LinearRegression]')
    print(f'  R2: {r2_lr:.4f}  MAE: {mae_lr:.4f}%')

    # RandomForest V1.5
    rf = RandomForestRegressor(n_estimators=100, max_depth=10, random_state=42, n_jobs=-1)
    rf.fit(X_train, y_train)
    rf_pred = rf.predict(X_test)
    r2_rf   = r2_score(y_test, rf_pred)
    mae_rf  = mean_absolute_error(y_test, rf_pred)
    rmse_rf = np.sqrt(mean_squared_error(y_test, rf_pred))
    print(f'\n[RandomForest V1.5]')
    print(f'  R2: {r2_rf:.4f}  MAE: {mae_rf:.4f}%  RMSE: {rmse_rf:.4f}%')

    # 비교 요약
    print(f'\n===== 모델 비교 요약 =====')
    print(f'{"모델":<25} {"R2":>8} {"MAE":>10}')
    print('-' * 45)
    print(f'{"평균 예측 (베이스라인1)":<25} {r2_mean:>8.4f} {mae_mean:>9.4f}%')
    print(f'{"LinearRegression":<25} {r2_lr:>8.4f} {mae_lr:>9.4f}%')
    print(f'{"RandomForest V1.5":<25} {r2_rf:>8.4f} {mae_rf:>9.4f}%')

    # 모델 저장
    with open(MODEL_PATH, 'wb') as f:
        pickle.dump(rf, f)
    print(f'\n모델 저장: {MODEL_PATH}')

    return rf


# =============================================
# 3. TOP 5 추천 + 평가
# =============================================
def make_feature(spx_return: float, spx_vol: float, card_selections: dict) -> list:
    """46차원 입력 벡터 생성"""
    enc = {col: 0 for col in CARD_ROUND_COLS}
    for round_num, card_id in card_selections.items():
        col = f'Card{card_id}_Round{round_num}'
        if col in enc:
            enc[col] = 1
    return [spx_return, spx_vol] + [enc[col] for col in CARD_ROUND_COLS]


def evaluate_recommendation(model, spx_return: float, spx_vol: float):
    """TOP 5 추천 + 3가지 평가"""
    # 전체 순열 예측 (7,920가지)
    all_combos = []
    for combo in permutations(ALL_CARD_IDS, 4):
        card_selections = {1: combo[0], 25: combo[1], 50: combo[2], 75: combo[3]}
        feat = make_feature(spx_return, spx_vol, card_selections)
        pred = model.predict([feat])[0]
        all_combos.append((card_selections, pred))
    all_combos.sort(key=lambda x: -x[1])

    top5     = all_combos[:5]
    true_top = all_combos[0]

    # TOP 5 출력
    print('\n===== TOP 5 추천 =====')
    for rank, (sel, pred) in enumerate(top5, 1):
        names = [CARD_NAMES[sel[r]] for r in CARD_SELECT_ROUNDS]
        print(f'  {rank}위 [{pred:+.2f}%]  {", ".join(names)}')
        print(f'       1R={CARD_NAMES[sel[1]]}  25R={CARD_NAMES[sel[25]]}  '
              f'50R={CARD_NAMES[sel[50]]}  75R={CARD_NAMES[sel[75]]}')

    # 평가 1: TOP 5 vs 랜덤 vs 전체 평균
    top5_avg   = np.mean([p for _, p in top5])
    random5    = random.sample(all_combos, 5)
    random_avg = np.mean([p for _, p in random5])
    all_avg    = np.mean([p for _, p in all_combos])
    print(f'\n===== 추천 평가 =====')
    print(f'TOP 5 예측 평균:    {top5_avg:+.4f}%')
    print(f'랜덤 5개 예측 평균: {random_avg:+.4f}%')
    print(f'전체 평균 예측:     {all_avg:+.4f}%')

    # 평가 2: 진짜 TOP 1과 일치도
    top5_sels   = [frozenset(sel.values()) for sel, _ in top5]
    true_top_sel = frozenset(true_top[0].values())
    match = true_top_sel in top5_sels
    true_names = ', '.join([CARD_NAMES[true_top[0][r]] for r in CARD_SELECT_ROUNDS])
    print(f'\n진짜 1위 조합: {true_names} [{true_top[1]:+.2f}%]')
    print(f'TOP 5에 포함: {"✅ 포함" if match else "❌ 미포함"}')


# =============================================
# 메인
# =============================================
if __name__ == '__main__':
    if not os.path.exists(DATA_PATH):
        print(f'학습 데이터 없음: {DATA_PATH}')
        print('먼저 monte_carlo.py를 실행하세요.')
        exit(1)

    df = pd.read_csv(DATA_PATH)
    print(f'데이터 로드: {len(df):,}건  /  컬럼: {len(df.columns)}개')

    # 1. 분포 분석
    analyze_distribution(df)

    # 2. 모델 학습 or 로드
    if os.path.exists(MODEL_PATH):
        ans = input('\n저장된 모델이 있습니다. 재학습할까요? (y/n): ').strip().lower()
        if ans == 'y':
            model = train_and_evaluate(df)
        else:
            with open(MODEL_PATH, 'rb') as f:
                model = pickle.load(f)
            print('저장된 모델 로드 완료')
    else:
        model = train_and_evaluate(df)

    # 3. 추천 + 평가
    print('\n===== 시장 상황 입력 =====')
    print('예시: 리먼 폭락장 -> 수익률 -30, 변동성 3.5')
    print('      잔잔한 상승장 -> 수익률 +20, 변동성 1.5')
    try:
        spx_return = float(input('SPX 수익률 입력 (%): '))
        spx_vol    = float(input('SPX 변동성 입력: '))
    except ValueError:
        spx_return, spx_vol = -30.0, 3.5
        print(f'기본값 사용: 수익률={spx_return}, 변동성={spx_vol}')

    evaluate_recommendation(model, spx_return, spx_vol)

    while True:
        again = input('\n다른 시장 상황으로 추천받을까요? (y/n): ').strip().lower()
        if again != 'y':
            break
        try:
            spx_return = float(input('SPX 수익률 입력 (%): '))
            spx_vol    = float(input('SPX 변동성 입력: '))
        except ValueError:
            continue
        evaluate_recommendation(model, spx_return, spx_vol)
