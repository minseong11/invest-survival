"""
V2 재설계 - Card_Contribution 타겟 모델
RandomForest vs XGBoost 비교

타겟: Card_Contribution (평균 대비 카드 기여도)
입력: 26차원 (시장 3 + current_round 1 + Already 11 + Selected 11)
"""
import os
import pickle
import numpy as np
import pandas as pd
import warnings
warnings.filterwarnings('ignore')
from sklearn.ensemble import RandomForestRegressor
from sklearn.linear_model import LinearRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from xgboost import XGBRegressor

DATA_DIR   = os.path.join(os.path.dirname(__file__), '..', 'data', 'simulation')
DATA_PATH  = os.path.join(DATA_DIR, 'training_data_v2.csv')
MODEL_PATH = os.path.join(DATA_DIR, 'model_v2.pkl')

ALL_CARD_IDS       = list(range(1, 12))
CARD_SELECT_ROUNDS = [1, 25, 50, 75]

CARD_NAMES = {
    1: '거인의 어깨',   2: '황금 적립',     3: '공포탐욕',
    4: '금 피난처',     5: '기술의 파도',   6: '낙폭과대 사냥',
    7: '원유 베팅',     8: '역발상 투자',   9: '애플 줍줍',
    10: '채권 피난처',  11: '분할매수 장인',
}

ALREADY_COLS  = [f'Already_Card{i}' for i in range(1, 12)]
SELECTED_COLS = [f'Selected_Card_{i}' for i in range(1, 12)]

FEATURE_COLS = [
    'SPX_Return_so_far',
    'SPX_Volatility_so_far',
    'SPX_MDD_so_far',
    'current_round',
    *ALREADY_COLS,
    *SELECTED_COLS,
]  # 총 26차원


# =============================================
# 1. 모델 학습 + 평가
# =============================================
def train_and_evaluate(df: pd.DataFrame):
    X = df[FEATURE_COLS].values
    y = df['Card_Contribution'].values

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    print(f'\n===== V2 재설계 모델 학습 =====')
    print(f'학습: {len(X_train):,}건  /  테스트: {len(X_test):,}건')
    print(f'입력 차원: {X.shape[1]}차원')
    print(f'타겟: Card_Contribution (평균 대비 카드 기여도)')

    # 베이스라인 1: 평균 예측
    mean_pred = np.full_like(y_test, y_train.mean())
    r2_mean   = r2_score(y_test, mean_pred)
    mae_mean  = mean_absolute_error(y_test, mean_pred)
    print(f'\n[베이스라인 - 평균 예측]')
    print(f'  R²: {r2_mean:.4f}  MAE: {mae_mean:.4f}%')

    # 베이스라인 2: LinearRegression
    lr = LinearRegression()
    lr.fit(X_train, y_train)
    lr_pred = lr.predict(X_test)
    r2_lr   = r2_score(y_test, lr_pred)
    mae_lr  = mean_absolute_error(y_test, lr_pred)
    print(f'\n[베이스라인 - LinearRegression]')
    print(f'  R²: {r2_lr:.4f}  MAE: {mae_lr:.4f}%')

    # RandomForest
    print(f'\n[RandomForest 학습 중...]')
    rf = RandomForestRegressor(
        n_estimators=100, max_depth=10, random_state=42, n_jobs=-1
    )
    rf.fit(X_train, y_train)
    rf_pred = rf.predict(X_test)
    r2_rf   = r2_score(y_test, rf_pred)
    mae_rf  = mean_absolute_error(y_test, rf_pred)
    rmse_rf = np.sqrt(mean_squared_error(y_test, rf_pred))
    print(f'  R²: {r2_rf:.4f}  MAE: {mae_rf:.4f}%  RMSE: {rmse_rf:.4f}%')

    # XGBoost
    print(f'\n[XGBoost 학습 중...]')
    xgb = XGBRegressor(
        n_estimators=200,
        max_depth=6,
        learning_rate=0.1,
        subsample=0.8,
        colsample_bytree=0.8,
        random_state=42,
        n_jobs=-1,
        verbosity=0,
    )
    xgb.fit(X_train, y_train)
    xgb_pred = xgb.predict(X_test)
    r2_xgb   = r2_score(y_test, xgb_pred)
    mae_xgb  = mean_absolute_error(y_test, xgb_pred)
    rmse_xgb = np.sqrt(mean_squared_error(y_test, xgb_pred))
    print(f'  R²: {r2_xgb:.4f}  MAE: {mae_xgb:.4f}%  RMSE: {rmse_xgb:.4f}%')

    # 비교 요약
    print(f'\n===== 모델 비교 요약 =====')
    print(f'{"모델":<25} {"R²":>8} {"MAE":>10}')
    print('-' * 45)
    print(f'{"평균 예측 (베이스라인1)":<25} {r2_mean:>8.4f} {mae_mean:>9.4f}%')
    print(f'{"LinearRegression":<25} {r2_lr:>8.4f} {mae_lr:>9.4f}%')
    print(f'{"RandomForest V2":<25} {r2_rf:>8.4f} {mae_rf:>9.4f}%')
    print(f'{"XGBoost V2":<25} {r2_xgb:>8.4f} {mae_xgb:>9.4f}%')

    # 최적 모델 선택
    if r2_xgb > r2_rf:
        best_model = xgb
        best_name  = 'XGBoost'
        best_r2    = r2_xgb
        imp_series = pd.Series(
            xgb.feature_importances_, index=FEATURE_COLS
        )
        print(f'\n✅ 최적 모델: XGBoost (R² {r2_xgb:.4f} > RF {r2_rf:.4f})')
    else:
        best_model = rf
        best_name  = 'RandomForest'
        best_r2    = r2_rf
        imp_series = pd.Series(
            rf.feature_importances_, index=FEATURE_COLS
        )
        print(f'\n✅ 최적 모델: RandomForest (R² {r2_rf:.4f} >= XGB {r2_xgb:.4f})')

    # Feature Importance 출력
    print(f'\n===== Feature Importance - {best_name} (상위 15개) =====')
    imp_sorted = imp_series.sort_values(ascending=False)
    for feat, val in imp_sorted.head(15).items():
        bar = '█' * int(val * 200)
        print(f'  {feat:<30} {val:.4f}  {bar}')

    selected_imp = imp_series[[c for c in FEATURE_COLS if 'Selected' in c]].sum()
    already_imp  = imp_series[[c for c in FEATURE_COLS if 'Already' in c]].sum()
    market_imp   = imp_series[['SPX_Return_so_far', 'SPX_Volatility_so_far', 'SPX_MDD_so_far']].sum()
    print(f'\n  시장 지표 합계:       {market_imp:.4f} ({market_imp*100:.1f}%)')
    print(f'  Already_Card 합계:    {already_imp:.4f} ({already_imp*100:.1f}%)')
    print(f'  Selected_Card 합계:   {selected_imp:.4f} ({selected_imp*100:.1f}%)')
    print(f'  current_round:        {imp_series["current_round"]:.4f} ({imp_series["current_round"]*100:.1f}%)')

    # 최적 모델 저장
    with open(MODEL_PATH, 'wb') as f:
        pickle.dump(best_model, f)
    print(f'\n모델 저장: {MODEL_PATH} ({best_name})')

    return best_model


# =============================================
# 2. 실시간 추천 함수
# =============================================
def make_feature(spx_return: float, spx_vol: float, spx_mdd: float,
                 current_round: int, already_cards: list,
                 selected_card: int) -> list:
    already_enc  = {f'Already_Card{i}': 0 for i in range(1, 12)}
    selected_enc = {f'Selected_Card_{i}': 0 for i in range(1, 12)}

    for card_id in already_cards:
        already_enc[f'Already_Card{card_id}'] = 1
    selected_enc[f'Selected_Card_{selected_card}'] = 1

    return [
        spx_return, spx_vol, spx_mdd, current_round,
        *[already_enc[c] for c in ALREADY_COLS],
        *[selected_enc[c] for c in SELECTED_COLS],
    ]


def recommend_card(model, spx_return: float, spx_vol: float, spx_mdd: float,
                   current_round: int, already_cards: list) -> list:
    candidates = [c for c in ALL_CARD_IDS if c not in already_cards]

    features = [
        make_feature(spx_return, spx_vol, spx_mdd,
                     current_round, already_cards, c)
        for c in candidates
    ]

    predictions = model.predict(features)
    results = sorted(
        zip(candidates, predictions),
        key=lambda x: -x[1]
    )
    return results


# =============================================
# 3. CLI
# =============================================
def run_cli(model):
    print('\n' + '=' * 60)
    print(' 📊 V2 실시간 카드 추천 시스템 (재설계)')
    print(' 추천 기준: 평균 대비 카드 기여도 (Card_Contribution)')
    print('=' * 60)

    while True:
        print('\n' + '-' * 60)
        try:
            spx_return    = float(input(' SPX 수익률 so_far (%) → '))
            spx_vol       = float(input(' SPX 변동성 so_far    → '))
            spx_mdd       = float(input(' SPX MDD so_far (%)   → '))
            current_round = int(input(' 현재 라운드 (1/25/50/75) → '))
        except ValueError:
            print(' ⚠️  숫자를 입력해주세요.')
            continue

        if current_round not in CARD_SELECT_ROUNDS:
            print(' ⚠️  라운드는 1, 25, 50, 75 중 하나여야 합니다.')
            continue

        already_cards = []
        round_idx = CARD_SELECT_ROUNDS.index(current_round)
        if round_idx > 0:
            print(f'\n 이미 선택한 카드 {round_idx}개를 입력하세요.')
            print(' ' + ', '.join([f'{k}:{v}' for k, v in CARD_NAMES.items()]))
            for i in range(round_idx):
                try:
                    card_id = int(input(f'   {i+1}번째 카드 ID → '))
                    if card_id in ALL_CARD_IDS:
                        already_cards.append(card_id)
                except ValueError:
                    pass

        results = recommend_card(
            model, spx_return, spx_vol, spx_mdd,
            current_round, already_cards
        )

        print(f'\n {"순위":<4} {"카드":>14} {"기여도 예측":>12}')
        print(' ' + '-' * 36)
        for rank, (card_id, pred) in enumerate(results, 1):
            marker = ' ★' if rank == 1 else ''
            print(f' {rank}위   {CARD_NAMES[card_id]:>14}   {pred:>+.2f}%{marker}')

        again = input('\n 다시 추천받으시겠습니까? (y/n) → ').strip().lower()
        if again != 'y':
            print(' 👋 종료합니다.')
            break


# =============================================
# 메인
# =============================================
def main():
    if not os.path.exists(DATA_PATH):
        print(f'❌ 학습 데이터 없음: {DATA_PATH}')
        print('먼저 monte_carlo_v2.py를 실행하세요.')
        return

    df = pd.read_csv(DATA_PATH)
    print(f'데이터 로드: {len(df):,}건  /  컬럼: {len(df.columns)}개')
    print(f'게임 수: {df["sim_id"].nunique():,}개')
    print(f'Card_Contribution 평균: {df["Card_Contribution"].mean():.4f}%')
    print(f'Card_Contribution 표준편차: {df["Card_Contribution"].std():.4f}%')

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

    run_cli(model)


if __name__ == '__main__':
    main()
