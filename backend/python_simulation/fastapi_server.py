"""
FastAPI AI 추천 서버
포트: 8000

엔드포인트:
  POST /ai/v1/recommend — V1.5 사전 추천 (게임 시작 시)
  POST /ai/v2/recommend — V2 실시간 추천 (25·50라운드)

Java Spring Boot가 내부적으로 호출. Flutter는 직접 호출하지 않음.
"""
import os
import pickle
import numpy as np
from itertools import permutations
from typing import List
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

# ── 경로 설정 ──────────────────────────────────────────────
BASE_DIR       = os.path.dirname(__file__)
DATA_DIR       = os.path.join(BASE_DIR, '..', 'data', 'simulation')
MODEL_V15_PATH = os.path.join(DATA_DIR, 'model_v15.pkl')
MODEL_V2_PATH  = os.path.join(DATA_DIR, 'model_v2.pkl')

# ── 카드 정보 ──────────────────────────────────────────────
ALL_CARD_IDS = list(range(1, 12))
CARD_SELECT_ROUNDS = [1, 25, 50, 75]

CARD_NAMES = {
    1: '거인의 어깨',   2: '황금 적립',     3: '공포탐욕',
    4: '금 피난처',     5: '기술의 파도',   6: '낙폭과대 사냥',
    7: '원유 베팅',     8: '역발상 투자',   9: '애플 줍줍',
    10: '채권 피난처',  11: '분할매수 장인',
}

# ── V1.5 Feature 컬럼 ─────────────────────────────────────
CARD_ROUND_COLS_V15 = [
    f'Card{i}_Round{r}'
    for i in range(1, 12)
    for r in CARD_SELECT_ROUNDS
]
FEATURE_COLS_V15 = ['SPX_Return', 'SPX_Volatility', 'SPX_MDD'] + CARD_ROUND_COLS_V15

# ── V2 Feature 컬럼 ───────────────────────────────────────
ALREADY_COLS  = [f'Already_Card{i}' for i in range(1, 12)]
SELECTED_COLS = [f'Selected_Card_{i}' for i in range(1, 12)]
FEATURE_COLS_V2 = [
    'SPX_Return_so_far', 'SPX_Volatility_so_far', 'SPX_MDD_so_far',
    'current_round',
    *ALREADY_COLS,
    *SELECTED_COLS,
]

# ── 앱 초기화 + 모델 로드 ──────────────────────────────────
app = FastAPI(title='투자 서바이벌 AI 추천 서버', version='4.0')

model_v15 = None
model_v2  = None

@app.on_event('startup')
def load_models():
    global model_v15, model_v2

    if os.path.exists(MODEL_V15_PATH):
        with open(MODEL_V15_PATH, 'rb') as f:
            model_v15 = pickle.load(f)
        print(f'✅ V1.5 모델 로드 완료: {MODEL_V15_PATH}')
    else:
        print(f'⚠️  V1.5 모델 없음: {MODEL_V15_PATH}')

    if os.path.exists(MODEL_V2_PATH):
        with open(MODEL_V2_PATH, 'rb') as f:
            model_v2 = pickle.load(f)
        print(f'✅ V2 모델 로드 완료: {MODEL_V2_PATH}')
    else:
        print(f'⚠️  V2 모델 없음: {MODEL_V2_PATH}')


# =============================================
# 요청/응답 스키마
# =============================================

# V1.5 요청: Java → Python
class V1RecommendRequest(BaseModel):
    spxReturn: float      # 전체 100라운드 SPX 수익률 (%)
    spxVolatility: float  # 전체 100라운드 SPX 변동성
    spxMdd: float         # 전체 100라운드 SPX MDD (%)

# V1.5 응답: Python → Java
class V1RecommendItem(BaseModel):
    round: int
    cardId: int
    predictedReturn: float

class V1RecommendResponse(BaseModel):
    recommendations: List[V1RecommendItem]

# V2 요청: Java → Python
class V2RecommendRequest(BaseModel):
    spxReturnSoFar: float      # 현재 라운드까지 SPX 누적 수익률 (%)
    spxVolatilitySoFar: float  # 현재 라운드까지 SPX 변동성
    spxMddSoFar: float         # 현재 라운드까지 SPX MDD (%)
    currentRound: int          # 현재 라운드 (25 또는 50)
    alreadyCards: List[int]    # 이미 선택한 카드 ID 목록
    candidateCards: List[int]  # 이번 라운드 후보 카드 ID 목록 (3개)

# V2 응답: Python → Java
class V2RankingItem(BaseModel):
    rank: int
    cardId: int
    contribution: float

class V2RecommendResponse(BaseModel):
    recommendedCardId: int
    rankings: List[V2RankingItem]


# =============================================
# V1.5 추천 로직
# =============================================
def make_feature_v15(spx_return: float, spx_vol: float, spx_mdd: float,
                     card_selections: dict) -> list:
    """V1.5 47차원 입력 벡터 생성"""
    enc = {col: 0 for col in CARD_ROUND_COLS_V15}
    for round_num, card_id in card_selections.items():
        col = f'Card{card_id}_Round{round_num}'
        if col in enc:
            enc[col] = 1
    return [spx_return, spx_vol, spx_mdd] + [enc[col] for col in CARD_ROUND_COLS_V15]


def get_v15_top_per_round(spx_return: float, spx_vol: float, spx_mdd: float) -> dict:
    """
    V1.5 모델로 라운드별 최적 카드 추천
    7920개 순열 전체 예측 후 라운드별 최고 카드 반환
    """
    all_results = []
    for combo in permutations(ALL_CARD_IDS, 4):
        card_selections = {
            1: combo[0], 25: combo[1], 50: combo[2], 75: combo[3]
        }
        feat = make_feature_v15(spx_return, spx_vol, spx_mdd, card_selections)
        pred = float(model_v15.predict([feat])[0])
        all_results.append((card_selections, pred))

    all_results.sort(key=lambda x: -x[1])

    # TOP 조합에서 라운드별 카드 추출
    top = all_results[0]
    return {
        'selections': top[0],
        'predicted_return': top[1]
    }


# =============================================
# V2 추천 로직
# =============================================
def make_feature_v2(spx_return: float, spx_vol: float, spx_mdd: float,
                    current_round: int, already_cards: list,
                    selected_card: int) -> list:
    """V2 26차원 입력 벡터 생성"""
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


# =============================================
# 엔드포인트
# =============================================

@app.get('/')
def health_check():
    return {
        'status': 'ok',
        'v15_model': model_v15 is not None,
        'v2_model':  model_v2  is not None,
    }


@app.post('/ai/v1/recommend', response_model=V1RecommendResponse)
def recommend_v1(req: V1RecommendRequest):
    """
    V1.5 사전 추천
    전체 100라운드 SPX 시장 지표 → 라운드별 최적 카드 추천
    """
    if model_v15 is None:
        raise HTTPException(status_code=503, detail='V1.5 모델이 로드되지 않았습니다')

    try:
        result = get_v15_top_per_round(
            req.spxReturn, req.spxVolatility, req.spxMdd
        )
        selections      = result['selections']
        predicted_return = result['predicted_return']

        recommendations = []
        for round_num in CARD_SELECT_ROUNDS:
            card_id = selections[round_num]
            # 라운드별 개별 예측값 계산
            feat = make_feature_v15(
                req.spxReturn, req.spxVolatility, req.spxMdd,
                {r: (card_id if r == round_num else selections[r])
                 for r in CARD_SELECT_ROUNDS}
            )
            recommendations.append(V1RecommendItem(
                round=round_num,
                cardId=card_id,
                predictedReturn=round(predicted_return / 4, 2)
            ))

        return V1RecommendResponse(recommendations=recommendations)

    except Exception as e:
        raise HTTPException(status_code=500, detail=f'V1.5 추천 오류: {str(e)}')


@app.post('/ai/v2/recommend', response_model=V2RecommendResponse)
def recommend_v2(req: V2RecommendRequest):
    """
    V2 실시간 추천
    현재까지 시장 지표 + 이미 선택한 카드 → 후보 카드 중 최적 추천
    """
    if model_v2 is None:
        raise HTTPException(status_code=503, detail='V2 모델이 로드되지 않았습니다')

    if req.currentRound not in [25, 50]:
        raise HTTPException(
            status_code=400,
            detail=f'지원하지 않는 라운드: {req.currentRound} (25 또는 50만 가능)'
        )

    if not req.candidateCards:
        raise HTTPException(status_code=400, detail='후보 카드가 없습니다')

    try:
        features = [
            make_feature_v2(
                req.spxReturnSoFar, req.spxVolatilitySoFar, req.spxMddSoFar,
                req.currentRound, req.alreadyCards, card_id
            )
            for card_id in req.candidateCards
        ]

        predictions = model_v2.predict(features)

        ranked = sorted(
            zip(req.candidateCards, predictions),
            key=lambda x: -x[1]
        )

        rankings = [
            V2RankingItem(
                rank=i + 1,
                cardId=card_id,
                contribution=round(float(pred), 2)
            )
            for i, (card_id, pred) in enumerate(ranked)
        ]

        return V2RecommendResponse(
            recommendedCardId=rankings[0].cardId,
            rankings=rankings
        )

    except Exception as e:
        raise HTTPException(status_code=500, detail=f'V2 추천 오류: {str(e)}')


# =============================================
# 실행
# =============================================
if __name__ == '__main__':
    import uvicorn
    uvicorn.run(app, host='0.0.0.0', port=8000)
