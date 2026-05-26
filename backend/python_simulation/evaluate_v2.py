"""
V2 재설계 모델 평가 — 스피어만 순위 상관관계 검증

평가 방식:
  RandomForest / XGBoost / Best 모델 각각 스피어만 계산 후 비교

스피어만 vs 평가 3 차이:
  평가 3: TOP 5 맞았냐 틀렸냐 (이진 판단, 데이터 부족 시 0/5)
  스피어만: 전체 순위가 얼마나 비슷한가 (연속 값 -1~+1, 더 공정)
"""
import warnings
warnings.filterwarnings('ignore')

import os
import pickle
import time
import numpy as np
import pandas as pd
from scipy.stats import spearmanr

DATA_DIR        = os.path.join(os.path.dirname(__file__), '..', 'data', 'simulation')
DATA_PATH       = os.path.join(DATA_DIR, 'training_data_v2.csv')
MODEL_PATH_RF   = os.path.join(DATA_DIR, 'model_v2_rf.pkl')
MODEL_PATH_XGB  = os.path.join(DATA_DIR, 'model_v2_xgb.pkl')
MODEL_PATH_BEST = os.path.join(DATA_DIR, 'model_v2.pkl')

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
]


# =============================================
# 유틸 함수
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


def load_model(path: str, name: str):
    if not os.path.exists(path):
        print(f' ⚠️  {name} 모델 없음: {path}')
        return None
    with open(path, 'rb') as f:
        model = pickle.load(f)
    print(f' ✅ {name} 로드 완료')
    return model


def get_ai_ranking(model, spx_return: float, spx_vol: float, spx_mdd: float,
                   current_round: int, already_cards: list) -> list:
    candidates = [c for c in ALL_CARD_IDS if c not in already_cards]
    features = [
        make_feature(spx_return, spx_vol, spx_mdd,
                     current_round, already_cards, c)
        for c in candidates
    ]
    predictions = model.predict(features)
    results = sorted(zip(candidates, predictions), key=lambda x: -x[1])
    return results


def get_actual_ranking(df: pd.DataFrame,
                       spx_return: float,
                       current_round: int,
                       already_cards: list,
                       market_tolerance: float = 5.0,
                       min_count: int = 3) -> list:
    mask = (
        (df['current_round'] == current_round) &
        (df['SPX_Return_so_far'].between(
            spx_return - market_tolerance,
            spx_return + market_tolerance
        ))
    )
    for card_id in already_cards:
        col = f'Already_Card{card_id}'
        if col in df.columns:
            mask &= (df[col] == 1)

    filtered = df[mask]
    if len(filtered) == 0:
        return []

    candidates = [c for c in ALL_CARD_IDS if c not in already_cards]
    results = []
    for card_id in candidates:
        col = f'Selected_Card_{card_id}'
        if col not in filtered.columns:
            continue
        card_data = filtered[filtered[col] == 1]['Card_Contribution']
        if len(card_data) >= min_count:
            results.append((card_id, card_data.mean(), card_data.median(), len(card_data)))

    results.sort(key=lambda x: -x[1])
    return results


# =============================================
# 단일 모델 스피어만 계산
# =============================================
def calc_spearman(model, ai_results: list, actual_results: list, model_name: str):
    if not actual_results:
        return None, None

    actual_card_ids = [r[0] for r in actual_results]
    ai_card_map = {card_id: pred for card_id, pred in ai_results}
    common_cards = [c for c in actual_card_ids if c in ai_card_map]

    if len(common_cards) < 3:
        print(f' ⚠️  [{model_name}] 공통 카드 부족 ({len(common_cards)}개)')
        return None, None

    ai_preds    = [ai_card_map[c] for c in common_cards]
    actual_avgs = [next(r[1] for r in actual_results if r[0] == c)
                   for c in common_cards]

    correlation, pvalue = spearmanr(ai_preds, actual_avgs)
    return correlation, pvalue


# =============================================
# 메인 평가
# =============================================
def evaluate_all_models(models: dict, df: pd.DataFrame,
                        spx_return: float, spx_vol: float, spx_mdd: float,
                        current_round: int, already_cards: list):

    print('\n' + '=' * 60)
    print(' [스피어만 순위 상관관계 검증]')
    print('=' * 60)
    print(f' 평가 조건:')
    print(f'   라운드: {current_round}')
    print(f'   시장: {spx_return:+.1f}%, 변동성 {spx_vol}, MDD {spx_mdd:+.1f}%')
    print(f'   Already: {[CARD_NAMES[c] for c in already_cards]}')

    # 실제 순위 (공통)
    actual_results = get_actual_ranking(
        df, spx_return, current_round, already_cards
    )

    if len(actual_results) < 3:
        print(f'\n ⚠️  실제 데이터 매칭 부족 ({len(actual_results)}개)')
        print(f'    최소 3건 이상 필요. 시장 조건 조정 또는 데이터 확장 필요.')
        return

    # 실제 순위 출력
    print(f'\n [실제 순위 (시뮬레이션 데이터 기반, 최소 3건)]')
    print(f' {"순위":<4} {"카드":>14} {"실제 평균":>10} {"중앙값":>8} {"건수":>6}')
    print(' ' + '-' * 52)
    for rank, (card_id, mean, median, count) in enumerate(actual_results, 1):
        print(f' {rank}위   {CARD_NAMES[card_id]:>14}   '
              f'{mean:>+.2f}%   {median:>+.2f}%   ({count}건)')

    # 모델별 평가
    spearman_results = {}

    for model_name, model in models.items():
        if model is None:
            continue

        print(f'\n {"=" * 60}')
        print(f' [{model_name}] AI 예측 순위')
        print(f' {"=" * 60}')

        ai_results = get_ai_ranking(
            model, spx_return, spx_vol, spx_mdd,
            current_round, already_cards
        )

        # AI 순위 출력
        print(f' {"순위":<4} {"카드":>14} {"예측 기여도":>12}')
        print(' ' + '-' * 36)
        for rank, (card_id, pred) in enumerate(ai_results, 1):
            marker = ' ★' if rank == 1 else ''
            print(f' {rank}위   {CARD_NAMES[card_id]:>14}   {pred:>+.2f}%{marker}')

        # 스피어만 계산
        correlation, pvalue = calc_spearman(
            model, ai_results, actual_results, model_name
        )

        if correlation is not None:
            spearman_results[model_name] = (correlation, pvalue)
            print(f'\n 스피어만 상관계수: {correlation:+.4f}  (p={pvalue:.4f})')

    # =============================================
    # 모델 비교 요약
    # =============================================
    if len(spearman_results) > 1:
        print('\n' + '=' * 60)
        print(' [모델별 스피어만 비교]')
        print('=' * 60)
        print(f' {"모델":<20} {"상관계수":>10} {"p-value":>10} {"평가"}')
        print(' ' + '-' * 55)

        best_name = max(spearman_results, key=lambda k: spearman_results[k][0])

        for name, (corr, pval) in spearman_results.items():
            marker = ' ← 최고' if name == best_name else ''
            sig = '유의' if pval < 0.05 else '비유의'
            print(f' {name:<20} {corr:>+.4f}     {pval:>8.4f}   {sig}{marker}')

        # 해석
        best_corr = spearman_results[best_name][0]
        print(f'\n [해석]')
        if best_corr >= 0.7:
            print(f' ✅ 강한 순위 일치 (ρ={best_corr:.2f})')
        elif best_corr >= 0.4:
            print(f' ⚠️  중간 순위 일치 (ρ={best_corr:.2f})')
        elif best_corr >= 0.0:
            print(f' ⚠️  약한 순위 일치 (ρ={best_corr:.2f})')
        else:
            print(f' ❌ 역상관 (ρ={best_corr:.2f})')

        print(f'\n [평가 3과 비교]')
        print(f' 평가 3: TOP 5 일치도 → 이진 판단 (0/5, 1/5...)')
        print(f' 스피어만: 전체 순위 상관관계 → 연속 값 (더 공정)')


# =============================================
# 메인
# =============================================
def main():
    if not os.path.exists(DATA_PATH):
        print(f'❌ 학습 데이터 없음: {DATA_PATH}')
        print('먼저 monte_carlo_v2.py를 실행하세요.')
        return

    print('=' * 60)
    print(' V2 재설계 스피어만 순위 검증 (RF / XGB / Best)')
    print('=' * 60)

    # 데이터 로드
    print('\n 데이터 로드 중...')
    df = pd.read_csv(DATA_PATH)
    print(f' 데이터 로드: {len(df):,}건')

    # 모델 로드
    print('\n 모델 로드 중...')
    models = {}
    rf   = load_model(MODEL_PATH_RF,   'RandomForest')
    xgb  = load_model(MODEL_PATH_XGB,  'XGBoost')
    best = load_model(MODEL_PATH_BEST, 'Best')

    if rf:   models['RandomForest'] = rf
    if xgb:  models['XGBoost']      = xgb
    if best: models['Best']         = best

    if not models:
        print('❌ 로드 가능한 모델 없음')
        return

    # 평가 조건 입력
    print('\n' + '-' * 60)
    print(' 평가할 시장 상황 입력')
    print('-' * 60)

    try:
        spx_return    = float(input(' SPX 수익률 so_far (%) [-15]: ') or '-15')
        spx_vol       = float(input(' SPX 변동성 so_far [2.0]: ')     or '2.0')
        spx_mdd       = float(input(' SPX MDD so_far (%) [-10]: ')    or '-10')
        current_round = int(input(' 현재 라운드 (25/50/75) [25]: ')   or '25')
    except ValueError:
        print('❌ 잘못된 입력')
        return

    if current_round not in [25, 50, 75]:
        print('❌ 라운드는 25, 50, 75 중 하나 (라운드 1 제외)')
        return

    # Already 카드 입력
    already_cards = []
    round_idx = [25, 50, 75].index(current_round)
    n_already = round_idx + 1
    print(f'\n 이미 선택한 카드 {n_already}개를 입력하세요.')
    print(' ' + ', '.join([f'{k}:{v}' for k, v in CARD_NAMES.items()]))
    for i in range(n_already):
        try:
            card_id = int(input(f'   {i+1}번째 카드 ID: '))
            if card_id in ALL_CARD_IDS:
                already_cards.append(card_id)
        except ValueError:
            pass

    start_time = time.time()

    evaluate_all_models(
        models, df,
        spx_return, spx_vol, spx_mdd,
        current_round, already_cards
    )

    elapsed = time.time() - start_time
    print('\n' + '=' * 60)
    print(f' 평가 완료 (소요 시간: {elapsed:.1f}초)')
    print('=' * 60)

    print('\n 다른 조건으로 다시 평가하시겠습니까? (y/n): ', end='')
    if input().strip().lower() == 'y':
        main()


if __name__ == '__main__':
    main()