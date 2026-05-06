"""
V1.5 - 카드 선택 시점 인코딩 (44차원) RandomForest 모델

구조:
  입력 46차원: SPX_Return, SPX_Volatility + Card{i}_Round{r} 44개
  출력: Final_Return (회귀)

기능:
  - 모델 학습 + 정량 평가 (R2, MAE, RMSE)
  - 베이스라인 비교 (평균 예측, LinearRegression)
  - 시장 상황 입력 → TOP 5 카드 조합 추천 (CLI)
  -> 교수님 피드백 1, 2번 반영

데이터 분포 분석은 visualize_distribution.py
추천 평가(피드백 3번)는 evaluate_v15.py
"""
import os
import pickle
import numpy as np
import pandas as pd
import warnings
warnings.filterwarnings('ignore')
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
# 1. 모델 학습 + 평가 (피드백 1, 2번)
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
# 2. TOP 5 추천 (CLI용)
# =============================================
def make_feature(spx_return: float, spx_vol: float, card_selections: dict) -> list:
    """46차원 입력 벡터 생성"""
    enc = {col: 0 for col in CARD_ROUND_COLS}
    for round_num, card_id in card_selections.items():
        col = f'Card{card_id}_Round{round_num}'
        if col in enc:
            enc[col] = 1
    return [spx_return, spx_vol] + [enc[col] for col in CARD_ROUND_COLS]


def recommend_top5(model, spx_return: float, spx_vol: float, top_n: int = 5):
    """순열 7920개 전부 예측 → top_n 반환"""
    all_combos = []
    for combo in permutations(ALL_CARD_IDS, 4):
        card_selections = {1: combo[0], 25: combo[1], 50: combo[2], 75: combo[3]}
        feat = make_feature(spx_return, spx_vol, card_selections)
        pred = model.predict([feat])[0]
        all_combos.append((card_selections, pred))
    
    all_combos.sort(key=lambda x: -x[1])
    return all_combos[:top_n]


def print_top5(top5):
    """TOP 5 출력"""
    print('\n' + '=' * 60)
    print(' 🏆 TOP 5 추천 카드 조합')
    print('=' * 60)
    for rank, (sel, pred) in enumerate(top5, 1):
        print(f'\n {rank}위 [{pred:+.2f}%]')
        for r in CARD_SELECT_ROUNDS:
            print(f'   라운드 {r:>2}: {CARD_NAMES[sel[r]]}')


# =============================================
# 메인
# =============================================
def main():
    if not os.path.exists(DATA_PATH):
        print(f'❌ 학습 데이터 없음: {DATA_PATH}')
        print('먼저 monte_carlo.py를 실행하세요.')
        return

    df = pd.read_csv(DATA_PATH)
    print(f'데이터 로드: {len(df):,}건  /  컬럼: {len(df.columns)}개')

    # 학습 or 로드
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

    # CLI 추천
    print('\n' + '=' * 60)
    print(' 📊 카드 추천 시스템 (V1.5)')
    print('=' * 60)
    
    while True:
        print()
        print('-' * 60)
        print(' 🌍 시장 수익률 (%)')
        print('   강한 상승장: +20 이상  /  잔잔한 상승장: +5 ~ +20')
        print('   횡보장:     -5 ~ +5')
        print('   약한 하락장: -5 ~ -20  /  강한 하락장: -20 이하')
        print('-' * 60)
        try:
            spx_return = float(input(' 시장 수익률 입력 → '))
        except ValueError:
            print(' ⚠️  숫자를 입력해주세요.')
            continue

        print()
        print('-' * 60)
        print(' 🌊 시장 변동성')
        print('   잔잔: 1.0 ~ 1.5  /  보통: 1.5 ~ 2.5')
        print('   격동: 2.5 ~ 4.0  /  극심: 4.0 이상')
        print('-' * 60)
        try:
            spx_vol = float(input(' 시장 변동성 입력 → '))
        except ValueError:
            print(' ⚠️  숫자를 입력해주세요.')
            continue

        # 추천 실행
        print('\n 분석 중... (전체 7920 순열 검사)')
        top5 = recommend_top5(model, spx_return, spx_vol, top_n=5)
        print_top5(top5)

        # 계속할지
        again = input('\n 다시 추천받으시겠습니까? (y/n) → ').strip().lower()
        if again != 'y':
            print(' 👋 종료합니다.')
            print(' 추천 평가는 evaluate_v15.py 실행')
            print(' 데이터 분포 분석은 visualize_distribution.py 실행')
            break


if __name__ == '__main__':
    main()