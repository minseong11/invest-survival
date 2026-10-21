"""
train_v2_resid.py — V2 "평균 + 시장 차이" 모델 학습 (8주차 실험)

배경 (7주차 평가, eval_test_period.py)
  2019~2024 테스트에서 V2(모델 A)는 무작위보다 낫지만,
  시장을 보지 않는 고정 순위(라운드·카드별 평균 순서)보다 낫다는 근거가 없었다.
  V2 순위가 고정 순위와 가장 닮아 있어(일치도 0.50) "평소 잘 되는 카드"를 주로 배운 것으로 보임.

이 실험
  타겟을 Card_Contribution − (라운드·카드별 평균)으로 바꿔 XGBoost가 "시장에 따른 차이"만 배우게 한다.
  예측 = 평균 + 시장 차이 예측 (residual_model.ResidualModel)
  - 시장 정보로 차이를 맞힐 수 있으면 → 고정 순위보다 좋아짐
  - 못 맞히면 → 고정 순위와 비슷해짐 (= "시장 지표로는 카드 차이를 맞히기 어렵다"는 결론)

학습 데이터·기간·제외 규칙·XGBoost 설정은 train_v2_ab.py와 동일 (설정은 6주차 그대로 고정, 테스트 결과를 보고 바꾸지 않음)
  - 평균(base)도 학습 데이터 안에서만 계산 (테스트 기간 정보 사용 안 함)

출력 (기존 모델은 덮어쓰지 않음)
  model_v2_A_resid.pkl, model_v2_B_resid.pkl

실행:
  python3 train_v2_resid.py
  python3 eval_test_period.py --summary-only --model ../data/simulation/model_v2_A_resid.pkl
"""
import os
import pickle
import pandas as pd
from sklearn.model_selection import GroupShuffleSplit
from sklearn.metrics import r2_score, mean_absolute_error

from recommend_v2 import FEATURE_COLS, DATA_DIR, DATA_PATH
from train_v2_ab import (make_xgb, game_end_dates, TRAIN_MIN_START,
                         LEHMAN_EXCLUDE_START, LEHMAN_EXCLUDE_END)
from residual_model import ResidualModel

MODEL_A_RESID_PATH = os.path.join(DATA_DIR, 'model_v2_A_resid.pkl')
MODEL_B_RESID_PATH = os.path.join(DATA_DIR, 'model_v2_B_resid.pkl')


def round_card_base(df: pd.DataFrame) -> dict:
    """{(라운드, 카드ID): 평균 Card_Contribution} — 넘겨받은 학습 데이터 안에서만 계산"""
    card = df[[f'Selected_Card_{i}' for i in range(1, 12)]].values.argmax(axis=1) + 1
    g = (pd.DataFrame({'r': df['current_round'].values, 'c': card,
                       'y': df['Card_Contribution'].values})
         .groupby(['r', 'c'])['y'].mean())
    return {(int(r), int(c)): float(v) for (r, c), v in g.items()}


def fit_residual(df: pd.DataFrame) -> ResidualModel:
    base = round_card_base(df)
    tmp = ResidualModel(base, None)
    X = df[FEATURE_COLS].values
    resid = df['Card_Contribution'].values - tmp.base_values(X)
    m = make_xgb()
    m.fit(X, resid)
    return ResidualModel(base, m)


def train_one(df: pd.DataFrame, name: str, path: str):
    X = df[FEATURE_COLS].values
    y = df['Card_Contribution'].values

    # 게임 단위 분할 참고 점수 (평균도 학습 쪽 데이터로만 계산)
    splitter = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=42)
    tr_idx, te_idx = next(splitter.split(X, y, df['sim_id'].values))
    model = fit_residual(df.iloc[tr_idx])
    base_only = model.base_values(X[te_idx])
    pred = model.predict(X[te_idx])

    final = fit_residual(df)
    with open(path, 'wb') as f:
        pickle.dump(final, f)

    print(f'\n[{name}]')
    print(f'  게임 수: {df["sim_id"].nunique():,}  /  행 수: {len(df):,}')
    print(f'  게임 단위 분할 참고치 (같은 학습 기간 안)')
    print(f'    평균만(고정 순위)   R²: {r2_score(y[te_idx], base_only):.4f}  MAE: {mean_absolute_error(y[te_idx], base_only):.4f}%')
    print(f'    평균 + 시장 차이    R²: {r2_score(y[te_idx], pred):.4f}  MAE: {mean_absolute_error(y[te_idx], pred):.4f}%')
    print(f'  저장: {path}')


def main():
    if not os.path.exists(DATA_PATH):
        print(f'❌ 학습 데이터 없음: {DATA_PATH}')
        return
    df = pd.read_csv(DATA_PATH)
    starts = pd.to_datetime(df['start_date'])
    if (starts > '2018-08-31').any():
        print('❌ 2018-08-31 이후 시작 게임이 있습니다. 학습 데이터 기간을 확인하세요.')
        return

    early = starts < TRAIN_MIN_START
    if early.any():
        print(f'USO 데이터 시작({TRAIN_MIN_START}) 전 시작 게임 {df.loc[early, "sim_id"].nunique():,}개 제외')
        df = df[~early].reset_index(drop=True)
        starts = pd.to_datetime(df['start_date'])

    train_one(df, '모델 A 평균+시장차이 (2006.04.10~2018.08 전체)', MODEL_A_RESID_PATH)

    ends = pd.to_datetime(game_end_dates(df['start_date']))
    overlap = (starts <= LEHMAN_EXCLUDE_END) & (ends >= LEHMAN_EXCLUDE_START)
    print(f'\n모델 B: 게임 기간이 {LEHMAN_EXCLUDE_START}~{LEHMAN_EXCLUDE_END}와 겹치는 {df.loc[overlap, "sim_id"].nunique():,}게임 제외')
    train_one(df[~overlap].reset_index(drop=True), '모델 B 평균+시장차이 (리먼 구간 제외)', MODEL_B_RESID_PATH)


if __name__ == '__main__':
    main()
