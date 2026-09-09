"""
FastAPI AI 추천 서버
포트: 8000

엔드포인트:
  POST /ai/v1/recommend — V1.5 사전 추천 (게임 시작 시)
  POST /ai/v2/recommend — V2 실시간 추천 (25·50라운드)
  POST /ai/v2/feedback  — V2 LLM 자연어 피드백 (25·50라운드, v5.0 신규)

Java Spring Boot가 내부적으로 호출. Flutter는 직접 호출하지 않음.
"""
import os
import pickle
import numpy as np
from itertools import permutations
from typing import List
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import anthropic

client = anthropic.Anthropic()

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

# 카드 실제 발동 조건 (game_logic.py CARDS 딕셔너리 기준, v5.0 명세서 5장)
CARD_LOGIC = {
    1:  '1라운드 즉시 현금 30% SPX 매수 (1회성)',
    2:  '매 라운드 조건 없이 현금 5%씩 GLD 매수 (무제한)',
    3:  'SPX 전일대비 -3% 이하일 때마다 현금 20% SPX 매수',
    4:  'SPX 전일대비 -5% 이하일 때마다 현금 15% GLD 매수',
    5:  'NDX 전일대비 +2% 이상일 때마다 현금 10% NDX 매수',
    6:  'NDX -4% 이하일 때 현금 25% NDX 매수 (최대 3회)',
    7:  '1라운드 즉시 현금 20% USO 매수 (1회성)',
    8:  'SPX +3% 이상일 때마다 보유 SPX 물량 15% 매도',
    9:  'AAPL -5% 이하일 때마다 현금 10% AAPL 매수 (최대 5회)',
    10: '매 라운드 조건 없이 현금 3%씩 TLT 매수 (무제한)',
    11: '조건 없이 5라운드마다 정기 NDX 매수',
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
app = FastAPI(title='투자 서바이벌 AI 추천 서버', version='5.0')

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

# V2 피드백 요청: Java → Python (v5.0 신규)
class V2FeedbackRankingItem(BaseModel):
    rank: int
    cardId: int
    contribution: float

class V2FeedbackRequest(BaseModel):
    spxReturnSoFar: float
    spxVolatilitySoFar: float
    spxMddSoFar: float
    currentRound: int
    alreadyCards: List[int]
    rankings: List[V2FeedbackRankingItem]

# V2 피드백 응답: Python → Java (v5.0 신규)
class V2FeedbackResponse(BaseModel):
    feedback: str


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
# V2 피드백 로직 (v5.0 신규)
# =============================================
def format_card_line(card_id: int) -> str:
    name = CARD_NAMES.get(card_id, f'카드{card_id}')
    logic = CARD_LOGIC.get(card_id, '조건 정보 없음')
    return f'- {name}: {logic}'


def format_rankings(rankings: List[V2FeedbackRankingItem]) -> str:
    return '\n'.join(
        f'{r.rank}위. {CARD_NAMES.get(r.cardId, r.cardId)} '
        f'({CARD_LOGIC.get(r.cardId, "")}) — 예상 기여도 {r.contribution}%'
        for r in rankings
    )


def format_already(already_cards: List[int]) -> str:
    if not already_cards:
        return '(없음)'
    return '\n'.join(format_card_line(cid) for cid in already_cards)


def build_prompt(req: V2FeedbackRequest) -> str:
    rankings_text = format_rankings(req.rankings)
    already_text = format_already(req.alreadyCards)
    return (
        f'현재 시장: SPX 누적수익률 {req.spxReturnSoFar}%, '
        f'변동성 {req.spxVolatilitySoFar}, MDD {req.spxMddSoFar}%\n'
        f'현재 라운드: {req.currentRound}\n\n'
        f'이미 보유한 카드(정확한 발동 조건 포함):\n{already_text}\n\n'
        f'후보 카드 순위(정확한 발동 조건 포함):\n{rankings_text}\n\n'
        f'위 카드들의 실제 발동 조건을 근거로 1위 카드가 왜 유리한지 '
        f'2~3문장으로 한국어로 설명해줘. 카드 로직에 없는 내용은 지어내지 마.'
    )


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


@app.post('/ai/v2/feedback', response_model=V2FeedbackResponse)
def generate_feedback(req: V2FeedbackRequest):
    """
    V2 LLM 자연어 피드백 (v5.0 신규)
    /ai/v2/recommend 결과(rankings) + 시장 상황 → Claude API로 자연어 설명 생성
    실패해도 카드 추천 자체는 이미 끝난 상태이므로, 예외를 던지지 않고
    feedback=""을 200으로 반환한다 (명세서 4장 에러 처리).
    """
    try:
        msg = client.messages.create(
            model='claude-sonnet-4-6',
            max_tokens=300,
            messages=[{'role': 'user', 'content': build_prompt(req)}]
        )
        return V2FeedbackResponse(feedback=msg.content[0].text)
    except Exception as e:
        print(f'⚠️  LLM 피드백 생성 실패: {e}')
        return V2FeedbackResponse(feedback='')


# =============================================
# 실행
# =============================================
if __name__ == '__main__':
    import uvicorn
    uvicorn.run(app, host='0.0.0.0', port=8000)