"""
RandomForest 기반 카드 추천 CLI
사용자가 시장 수익률 + 변동성 입력하면 최적의 카드 조합 추천
"""
import os
import pickle
from itertools import combinations

import pandas as pd
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error, r2_score


# ===== 경로 설정 =====
BASE_DIR   = os.path.dirname(os.path.abspath(__file__))
CSV_PATH   = os.path.join(BASE_DIR, '..', 'data', 'simulation', 'training_data.csv')
MODEL_PATH = os.path.join(BASE_DIR, '..', 'data', 'simulation', 'model.pkl')


# ===== 카드 정보 (사람이 읽기 쉬운 이름) =====
CARD_NAMES = {
    1:  '거인의 어깨',
    2:  '황금 적립',
    3:  '공포탐욕',
    4:  '금 피난처',
    5:  '기술의 파도',
    6:  '낙폭과대 사냥',
    7:  '원유 베팅',
    8:  '역발상 투자',
    9:  '애플 줍줍',
    10: '채권 피난처',
    11: '분할매수 장인',
}

FEATURE_COLS = ['SPX_Return', 'SPX_Volatility'] + [f'Card{i}_Active' for i in range(1, 12)]


# ===== 모델 학습 / 로드 =====
def train_model():
    """CSV 데이터로 RandomForest 학습"""
    print('\n[모델 학습 시작]')
    df = pd.read_csv(CSV_PATH)
    print(f'  데이터 개수: {len(df):,}개')

    X = df[FEATURE_COLS]
    y = df['Final_Return']

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    model = RandomForestRegressor(n_estimators=100, max_depth=10, random_state=42, n_jobs=-1)
    model.fit(X_train, y_train)

    y_pred = model.predict(X_test)
    mae = mean_absolute_error(y_test, y_pred)
    r2  = r2_score(y_test, y_pred)
    print(f'  평균 오차(MAE): {mae:.2f}%')
    print(f'  R² Score:      {r2:.3f}')

    # 모델 저장
    with open(MODEL_PATH, 'wb') as f:
        pickle.dump(model, f)
    print(f'  모델 저장: {MODEL_PATH}\n')

    return model


def load_or_train_model():
    """저장된 모델이 있으면 로드, 없으면 학습"""
    if os.path.exists(MODEL_PATH):
        print(f'[저장된 모델 로드] {MODEL_PATH}')
        with open(MODEL_PATH, 'rb') as f:
            return pickle.load(f)
    return train_model()


# ===== 카드 추천 =====
def recommend_cards(model, spx_return: float, spx_volatility: float, top_n: int = 5):
    """11개 카드 중 4개 조합 전부 예측 → top_n 반환"""
    results = []
    for combo in combinations(range(1, 12), 4):
        multi_hot = [1 if i in combo else 0 for i in range(1, 12)]
        X = [[spx_return, spx_volatility] + multi_hot]
        predicted = model.predict(X)[0]
        results.append((combo, predicted))

    results.sort(key=lambda x: -x[1])
    return results[:top_n]


# ===== CLI 메인 =====
def main():
    print('=' * 50)
    print(' 📊 카드 추천 시스템 (RandomForest)')
    print('=' * 50)

    model = load_or_train_model()

    while True:
        print()
        print('-' * 50)
        print(' 🌍 시장 수익률 (%) — 100라운드 동안 SPX 누적 수익률')
        print('   예시:')
        print('     강한 상승장: +20 이상   /   약한 상승장: +5 ~ +20')
        print('     횡보장:     -5 ~ +5')
        print('     약한 하락장: -5 ~ -20  /   강한 하락장: -20 이하')
        print('-' * 50)

        try:
            spx_return = float(input(' 시장 수익률 입력 → '))
        except ValueError:
            print(' ⚠️  숫자를 입력해주세요.')
            continue

        print()
        print('-' * 50)
        print(' 🌊 시장 변동성 — 일일 수익률의 표준편차')
        print('   예시:')
        print('     잔잔: 1.0 ~ 1.5   /   보통: 1.5 ~ 2.5')
        print('     격동: 2.5 ~ 4.0   /   극심: 4.0 이상')
        print('-' * 50)

        try:
            spx_volatility = float(input(' 시장 변동성 입력 → '))
        except ValueError:
            print(' ⚠️  숫자를 입력해주세요.')
            continue

        # 추천 실행
        print('\n 분석 중...')
        recommendations = recommend_cards(model, spx_return, spx_volatility, top_n=5)

        print()
        print('=' * 50)
        print(f' 📈 입력: 수익률 {spx_return:+.2f}% / 변동성 {spx_volatility}')
        print('=' * 50)
        print(' 🏆 추천 카드 조합 TOP 5')
        print('-' * 50)
        for rank, (combo, pred) in enumerate(recommendations, 1):
            names = ', '.join(CARD_NAMES[c] for c in combo)
            print(f' {rank}위 [{pred:+.2f}%]  {names}')
        print('-' * 50)

        # 계속할지
        again = input('\n 다시 입력하시겠습니까? (y/n) → ').strip().lower()
        if again != 'y':
            print(' 👋 종료합니다.')
            break


if __name__ == '__main__':
    main()