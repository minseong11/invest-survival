"""
V2 모델 A/B 학습 (6주차)

입력: training_data_v2.csv (monte_carlo_v2.py, 시작일 2006-04-01 ~ 2018-08-31)
출력:
  model_v2_A.pkl — 학습 기간 전체 → 코로나·2022 시나리오, 7주차 테스트(2019~2024)용
  model_v2_B.pkl — 리먼 구간 제외 → 리먼 시나리오용 (리먼 기간을 보지 않은 모델)

입력 26차원·타겟(Card_Contribution)·XGBoost 설정은 recommend_v2.py와 동일.
내부 평가는 같은 게임(sim_id)의 행이 학습/평가에 섞이지 않도록 게임 단위로 나눈다.
  (기존 recommend_v2.py는 행 단위 무작위 분할 → 같은 게임 행이 양쪽에 들어가 점수가 높게 나옴)
※ 여기 나오는 R²는 학습 기간 안의 참고치. 실제 성능 평가는 7주차 2019~2024 테스트.

실행: python3 train_v2_ab.py
"""
import os
import pickle
import numpy as np
import pandas as pd
from sklearn.model_selection import GroupShuffleSplit
from sklearn.metrics import r2_score, mean_absolute_error
from xgboost import XGBRegressor

from recommend_v2 import FEATURE_COLS, DATA_DIR, DATA_PATH

MODEL_A_PATH = os.path.join(DATA_DIR, 'model_v2_A.pkl')
MODEL_B_PATH = os.path.join(DATA_DIR, 'model_v2_B.pkl')

# 모델 B에서 제외할 시작일 구간 (리먼 시나리오 2008-09-02 시작 게임과 겹치는 시장 국면)
LEHMAN_EXCLUDE_START = '2007-09-01'
LEHMAN_EXCLUDE_END   = '2009-10-31'


def make_xgb():
    return XGBRegressor(
        n_estimators=200, max_depth=6, learning_rate=0.1,
        subsample=0.8, colsample_bytree=0.8,
        random_state=42, n_jobs=-1, verbosity=0,
    )


def train_one(df: pd.DataFrame, name: str, path: str):
    X = df[FEATURE_COLS].values
    y = df['Card_Contribution'].values
    groups = df['sim_id'].values

    # 게임 단위 분할로 참고 점수 계산
    splitter = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=42)
    tr_idx, te_idx = next(splitter.split(X, y, groups))
    model = make_xgb()
    model.fit(X[tr_idx], y[tr_idx])
    pred = model.predict(X[te_idx])
    r2 = r2_score(y[te_idx], pred)
    mae = mean_absolute_error(y[te_idx], pred)

    # 저장용 모델은 전체 데이터로 다시 학습
    final = make_xgb()
    final.fit(X, y)
    with open(path, 'wb') as f:
        pickle.dump(final, f)

    starts = pd.to_datetime(df['start_date'])
    print(f'\n[{name}]')
    print(f'  게임 수: {df["sim_id"].nunique():,}  /  행 수: {len(df):,}')
    print(f'  시작일 범위: {starts.min().date()} ~ {starts.max().date()}')
    print(f'  게임 단위 분할 참고치  R²: {r2:.4f}  MAE: {mae:.4f}%')
    print(f'  저장: {path}')


def main():
    if not os.path.exists(DATA_PATH):
        print(f'❌ 학습 데이터 없음: {DATA_PATH}\n먼저 monte_carlo_v2.py를 실행하세요.')
        return
    df = pd.read_csv(DATA_PATH)
    starts = pd.to_datetime(df['start_date'])

    # 안전 확인: 테스트 기간(2019~) 시작 게임이 섞여 있으면 중단
    if (starts > '2018-08-31').any():
        print('❌ 2018-08-31 이후 시작 게임이 있습니다. monte_carlo_v2.py 기간 설정을 확인하세요.')
        return

    train_one(df, '모델 A (2006.04~2018.08 전체)', MODEL_A_PATH)

    in_lehman = (starts >= LEHMAN_EXCLUDE_START) & (starts <= LEHMAN_EXCLUDE_END)
    df_b = df[~in_lehman]
    print(f'\n모델 B: 리먼 구간 시작 게임 {df.loc[in_lehman, "sim_id"].nunique():,}개 제외')
    train_one(df_b, f'모델 B (리먼 {LEHMAN_EXCLUDE_START}~{LEHMAN_EXCLUDE_END} 제외)', MODEL_B_PATH)


if __name__ == '__main__':
    main()
