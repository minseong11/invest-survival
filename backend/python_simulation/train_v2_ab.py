"""
V2 모델 A/B 학습 (6주차)

입력: training_data_v2.csv (monte_carlo_v2.py, 시작일 2006-04-01 ~ 2018-08-31)
출력:
  model_v2_A.pkl — 학습 기간 전체 → 코로나·2022 시나리오, 7주차 테스트(2019~2024)용
  model_v2_B.pkl — 리먼 구간 제외 → 리먼 시나리오용 (위기 구간을 제외한 교육용 시연 모델)
                   ※ 2010~2018은 학습하므로 "2008년 당시 정보만 쓴 모델"은 아님.
                     일반화 검증은 모델 A의 2019~2024 테스트로 한다.

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
from data_loader import load_all

MODEL_A_PATH = os.path.join(DATA_DIR, 'model_v2_A.pkl')
MODEL_B_PATH = os.path.join(DATA_DIR, 'model_v2_B.pkl')

# 모델 B에서 제외할 구간 (리먼 시나리오 게임 기간을 포함하는 위기 국면)
# 게임의 "전체 100라운드 기간"이 이 구간과 하루라도 겹치면 제외한다.
#   (시작일만 보면 2007-09 이전에 시작해 구간 안까지 이어지는 게임이 남음 — 6주차 피드백)
LEHMAN_EXCLUDE_START = '2007-09-01'
LEHMAN_EXCLUDE_END   = '2009-10-31'
LEHMAN_SCENARIO_START = '2008-09-01'
# USO(원유) 데이터 시작일. 이보다 먼저 시작한 게임은 원유 카드 가격이 결측이라 학습에서 제외 (#87 결측 구분)
TRAIN_MIN_START = '2006-04-10'
ROUNDS = 100


def game_end_dates(start_dates: pd.Series) -> pd.Series:
    """각 시작일의 100번째 SPX 거래일(= 게임 마지막 라운드 날짜)"""
    spx_dates = pd.DatetimeIndex(load_all()['^SPX']['Date']).sort_values()
    uniq = pd.to_datetime(pd.Series(start_dates.unique()))
    first_idx = spx_dates.searchsorted(uniq.values, side='left')
    last_idx = first_idx + (ROUNDS - 1)
    ends = [spx_dates[i] if i < len(spx_dates) else pd.NaT for i in last_idx]
    mapping = dict(zip(start_dates.unique(), ends))
    return start_dates.map(mapping)


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

    # 원유(USO) 데이터 시작 전 게임 제외 — 원유 카드가 "가격 없음" 상태로 섞이지 않도록
    early = starts < TRAIN_MIN_START
    if early.any():
        print(f'USO 데이터 시작({TRAIN_MIN_START}) 전 시작 게임 {df.loc[early, "sim_id"].nunique():,}개 제외')
        df = df[~early].reset_index(drop=True)
        starts = pd.to_datetime(df['start_date'])

    train_one(df, '모델 A (2006.04.10~2018.08 전체)', MODEL_A_PATH)

    # 게임 전체 기간 [시작일, 100라운드 날짜]가 제외 구간과 겹치는지
    ends = pd.to_datetime(game_end_dates(df['start_date']))
    overlap = (starts <= LEHMAN_EXCLUDE_END) & (ends >= LEHMAN_EXCLUDE_START)
    start_only = (starts >= LEHMAN_EXCLUDE_START) & (starts <= LEHMAN_EXCLUDE_END)
    n_overlap = df.loc[overlap, 'sim_id'].nunique()
    n_start_only = df.loc[start_only, 'sim_id'].nunique()

    # 리먼 시나리오 실제 게임 기간이 제외 구간 안에 있는지 확인
    lehman_end = game_end_dates(pd.Series([LEHMAN_SCENARIO_START])).iloc[0]
    print(f'\n리먼 시나리오 게임 기간: {LEHMAN_SCENARIO_START} ~ {pd.Timestamp(lehman_end).date()}')
    print(f'모델 B 제외 구간: {LEHMAN_EXCLUDE_START} ~ {LEHMAN_EXCLUDE_END} (게임 전체 기간이 겹치면 제외)')
    print(f'  시작일 기준이었다면 제외: {n_start_only:,}게임')
    print(f'  기간 겹침 기준 제외:      {n_overlap:,}게임 (+{n_overlap - n_start_only:,})')

    df_b = df[~overlap]
    b_ends = ends[~overlap]
    leaked = ((pd.to_datetime(df_b['start_date']) <= LEHMAN_EXCLUDE_END) &
              (b_ends >= LEHMAN_EXCLUDE_START)).sum()
    print(f'  확인: 모델 B 학습 데이터 중 제외 구간과 겹치는 행 = {leaked}')
    train_one(df_b, f'모델 B (게임 기간이 {LEHMAN_EXCLUDE_START}~{LEHMAN_EXCLUDE_END}와 겹치면 제외)', MODEL_B_PATH)


if __name__ == '__main__':
    main()