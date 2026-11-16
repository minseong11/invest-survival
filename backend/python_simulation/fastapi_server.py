"""
FastAPI AI 추천 서버
포트: 8000

엔드포인트:
  POST /ai/v1/recommend — V1.5 사전 추천 (게임 시작 시)
  POST /ai/v2/recommend — V2 실시간 추천 (25·50라운드)
  POST /ai/v2/feedback  — V2 LLM 자연어 피드백 (25·50라운드, v5.0 신규)
  POST /ai/analysis/backtest — 사후 분석: 전체 조합 백테스팅 (v6.0 신규, 사용 가능 카드 기준)
                               + 받은 후보 안 최선 조합·라운드별 대안 (11주차, offeredCards)
                               + 등급·최대 낙폭·카드별 성적표·위기 대응 돌아보기·그 후 이야기 (#125)
  POST /ai/analysis/prewarm  — 전체 조합 결과 미리 계산 (#125, 게임 중 호출 → 결과 화면이 바로 뜸)
  POST /ai/analysis/coach    — 사후 분석 AI 코치 한마디 (#125, 사실은 프로그램이 쓰고 LLM은 한 문장만)

Java Spring Boot가 내부적으로 호출. Flutter는 직접 호출하지 않음.
"""
import os
import re
import pickle
import numpy as np
from contextlib import asynccontextmanager
from itertools import permutations
from typing import Dict, List, Optional
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import anthropic
from backtest import run_backtest, prewarm
import result_coach
from verify_feedback import verify_feedback, CARD_FACTS
from data_loader import load_all
import pandas as pd

# ── LLM 설정 (#125) ───────────────────────────────────────
# 모델은 환경변수 LLM_MODEL로 바꿀 수 있다 (기본값은 지금까지 검증에 써 온 모델 그대로).
# 시간 제한: 한 문장 생성이 길어지면 게임 화면이 멈춘 것처럼 보이므로 8초 + 재시도 1회로 끊고,
#           실패하면 프로그램이 만든 기본 문장으로 응답한다 (Spring Boot 응답 대기 30초 안에 끝남).
LLM_MODEL = os.environ.get('LLM_MODEL', 'claude-sonnet-4-6')
LLM_TIMEOUT_SEC = float(os.environ.get('LLM_TIMEOUT_SEC', '8'))
client = anthropic.Anthropic(timeout=LLM_TIMEOUT_SEC, max_retries=1)

# ── 경로 설정 ──────────────────────────────────────────────
BASE_DIR       = os.path.dirname(__file__)
DATA_DIR       = os.path.join(BASE_DIR, '..', 'data', 'simulation')
MODEL_V15_PATH = os.path.join(DATA_DIR, 'model_v15.pkl')
MODEL_V2_PATH  = os.path.join(DATA_DIR, 'model_v2.pkl')     # 기존 V2 (리먼 구간 학습) — 비교용 보관, 대체 경로
MODEL_V2_A_PATH = os.path.join(DATA_DIR, 'model_v2_A.pkl')  # 학습 2006.04~2018 전체
MODEL_V2_B_PATH = os.path.join(DATA_DIR, 'model_v2_B.pkl')  # 리먼 구간(2007.09~2009.10) 제외

# 모델 B를 쓰는 기준: 게임 100라운드 기간이 이 구간과 겹치면 B (train_v2_ab.py와 동일)
LEHMAN_EXCLUDE_START = pd.Timestamp('2007-09-01')
LEHMAN_EXCLUDE_END   = pd.Timestamp('2009-10-31')
GAME_ROUNDS = 100

# ── 카드 정보 ──────────────────────────────────────────────
ALL_CARD_IDS = list(range(1, 12))
CARD_SELECT_ROUNDS = [1, 25, 50, 75]

# (10주차) 카드 이름·규칙은 verify_feedback.CARD_FACTS 하나에서 가져온다 (중복 정의 제거)
CARD_NAMES = {cid: fact.name for cid, fact in CARD_FACTS.items()}

# 카드 실제 발동 조건 — 손으로 쓴 문장 대신 CARD_FACTS의 설명을 그대로 사용
# (예전에는 같은 문장이 여기와 CARD_FACTS에 따로 있었고, 둘 다 거인의 어깨·원유 베팅을
#  '1라운드 즉시 매수'로 잘못 적고 있었음 → 실제로는 카드를 고른 라운드에 매수)
CARD_LOGIC = {cid: fact.condition_desc for cid, fact in CARD_FACTS.items()}

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
model_v15 = None
model_v2  = None   # 기존 V2
model_v2_a = None
model_v2_b = None


@asynccontextmanager
async def lifespan(_app: FastAPI):
    # (#125) on_event('startup')은 지원 종료 예정이라 lifespan으로 옮김
    load_models()
    yield


app = FastAPI(title='투자 서바이벌 AI 추천 서버', version='9.0', lifespan=lifespan)


def load_models():
    global model_v15, model_v2, model_v2_a, model_v2_b

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

    for label, path in [('A', MODEL_V2_A_PATH), ('B', MODEL_V2_B_PATH)]:
        if os.path.exists(path):
            with open(path, 'rb') as f:
                m = pickle.load(f)
            if label == 'A':
                model_v2_a = m
            else:
                model_v2_b = m
            print(f'✅ V2 모델 {label} 로드 완료: {path}')
        else:
            print(f'⚠️  V2 모델 {label} 없음: {path}')


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
    startDate: Optional[str] = None  # 게임 시작일 (v7.0) — 모델 A/B 선택용. 없으면 모델 A

# V2 응답: Python → Java
class V2RankingItem(BaseModel):
    rank: int
    cardId: int
    contribution: float

class V2RecommendResponse(BaseModel):
    recommendedCardId: int
    rankings: List[V2RankingItem]
    modelVersion: str = ''     # 추천에 사용한 모델 (v2_A / v2_B / v2_legacy)

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
    verified: Optional[bool] = None   # (v7.0) True: 구현된 검사 통과 / False: 검사 실패 → 대체 문장 / None: LLM 실패
    #   ※ verified=True는 "구현된 검사(규칙 v3 + 숫자 출처 + 무조건부 카드 조건화)를 통과"라는 뜻이지 내용 전체의 사실 확인이 아님
    status: str = ''                  # (v8.0) 'llm' | 'fallback' | 'failed' — 화면·로그에서 상태 구분용

# 사후 분석(백테스팅) 요청/응답 (v6.0 신규)
class BacktestRequest(BaseModel):
    startDate: str                          # 게임 시작일 (예: "2008-09-02")
    playerCardSelections: Dict[str, int]    # {"1": 1, "25": 4, "50": 5, "75": 9}
    topN: int = 3
    offeredCards: Optional[Dict[str, List[int]]] = None   # (11주차) {"1": [1,3,10], "25": [...], ...} 라운드별 제시 후보
    decisions: Optional[Dict[str, str]] = None            # (#125) 위기 대응 {"10": "SELL_HALF", "20": "HOLD"} — 모든 조합에 똑같이 적용
    baseTicker: Optional[str] = None                      # (#125) '더 산다'에서 사는 종목 (^SPX / ^NDX). 없으면 ^SPX

class BacktestCombo(BaseModel):
    rank: int
    tiedCount: int                          # 같은 결과(최종 자산)를 내는 조합 수 (대표 1개만 반환)
    cardSelections: Dict[str, int]
    finalAsset: int
    finalReturnRate: float

class BacktestPlayerResult(BaseModel):
    cardSelections: Dict[str, int]
    finalAsset: int
    finalReturnRate: float
    rank: int
    tiedCount: int                          # 내 조합 포함, 같은 결과를 내는 조합 수
    topPercent: float                       # rank/total × 100 (상위 몇 %, 작을수록 좋음)

# (11주차) 받은 후보 안 분석
class OfferedAlternative(BaseModel):
    cardId: int
    finalAsset: int
    finalReturnRate: float
    diffReturnRate: float                   # 대안 - 내 결과 (%p, +면 대안이 더 좋았음)

class OfferedRoundAlternatives(BaseModel):
    round: int
    offeredCards: List[int]                 # 이 라운드에 제시된 후보
    playerCardId: int                       # 내가 고른 카드
    alternatives: List[OfferedAlternative]  # 이 라운드만 다른 후보로 바꿨을 때 (나머지 선택은 그대로)

class OfferedAnalysis(BaseModel):
    totalCombinations: int                  # 받은 후보로 만들 수 있는 조합 수 (최대 81)
    bestCombo: BacktestCombo
    playerResult: BacktestPlayerResult
    roundAlternatives: List[OfferedRoundAlternatives]

# (#125) 최대 낙폭
class RiskInfo(BaseModel):
    playerMdd: float                        # 내 자산의 최대 낙폭(%, 0 이하)
    playerMddRound: Optional[int] = None    # 가장 깊었던 라운드 (낙폭이 없으면 null)
    playerMddDate: Optional[str] = None
    marketMdd: float                        # 같은 기간 S&P500 최대 낙폭(%)
    marketMddRound: Optional[int] = None
    marketMddDate: Optional[str] = None
    marketReturnRate: float                 # 같은 기간 S&P500 수익률(%)

# (#125) 카드별 성적표
class CardReportItem(BaseModel):
    round: int
    cardId: int
    cardName: str
    cardType: str
    triggerCount: int                       # 실제로 매매가 일어난 횟수
    tradeAmount: int                        # 매매 금액 합계 (원)
    skips: Dict[str, int]                   # 조건은 맞았지만 실행되지 못한 횟수 {CASH_LOW / MAX_REACHED / NO_HOLDINGS / NO_PRICE}
    withoutFinalAsset: int                  # 이 카드만 고르지 않았을 때의 최종 자산
    withoutFinalReturnRate: float
    effectAsset: int                        # 내 결과 − 이 카드를 뺀 결과 (원)
    effectReturnRate: float                 # 같은 값을 %p로 (+면 이 카드가 결과를 끌어올림)

# (#125) 위기 대응 돌아보기
class DecisionAlternative(BaseModel):
    choice: str
    finalAsset: int
    finalReturnRate: float
    diffReturnRate: float                   # 다른 선택 − 내 결과 (%p, +면 다른 선택이 더 좋았음)

class DecisionRoundReview(BaseModel):
    round: int
    date: str
    choice: str                             # HOLD / SELL_HALF / BUY_MORE
    tradeAmount: int                        # 그때 팔거나 산 금액 (원)
    alternatives: List[DecisionAlternative]

class DecisionReview(BaseModel):
    rounds: List[DecisionRoundReview]
    allHoldFinalAsset: int                  # 전부 버텼을 때
    allHoldFinalReturnRate: float
    effectReturnRate: float                 # 내 결과 − 전부 버텼을 때 (%p)

# (#125) 그 후 이야기
class EpiloguePoint(BaseModel):
    label: str                              # "6개월 뒤" / "1년 뒤"
    tradingDays: int
    date: str
    spxChangeRate: float                    # 게임 종료일 대비 S&P500 (%)
    playerAsset: int                        # 내 최종 보유 자산을 그대로 뒀을 때 평가액
    playerReturnRate: float                 # 원금 대비 (%)
    bestAsset: Optional[int] = None         # 게임 1위 조합을 그대로 뒀을 때
    bestReturnRate: Optional[float] = None

class Epilogue(BaseModel):
    endDate: str                            # 게임 마지막 라운드 날짜
    points: List[EpiloguePoint]

class BacktestResponse(BaseModel):
    totalCombinations: int
    cardPoolSize: int                       # 시작일에 사용 가능한 카드 수 (상장 전 종목 카드 제외)
    topCombos: List[BacktestCombo]
    playerResult: BacktestPlayerResult
    offeredAnalysis: Optional[OfferedAnalysis] = None   # (11주차) 후보 정보가 없으면 null
    # (#125)
    grade: str = ''                                     # S / A / B / C / D (전체 조합 순위 기준)
    risk: Optional[RiskInfo] = None
    cardReport: List[CardReportItem] = []
    decisionReview: Optional[DecisionReview] = None     # 위기 대응이 없으면 null
    epilogue: Optional[Epilogue] = None                 # 게임 종료 뒤 데이터가 없으면 null

# (#125) 미리 계산 요청/응답
class PrewarmRequest(BaseModel):
    startDate: str
    decisions: Optional[Dict[str, str]] = None
    baseTicker: Optional[str] = None

class PrewarmResponse(BaseModel):
    status: str                             # 'ready' | 'started'

# (#125) AI 코치 한마디 응답 — 요청은 BacktestRequest와 같다
class CoachResponse(BaseModel):
    comment: str                            # 줄 머리말로 나뉜 글: 요약 / 잘한 점 / 아쉬운 점 / 위기 대응 / 다음엔
    verified: Optional[bool] = None         # True: 검사 통과한 LLM 문장 / False: 검사 실패 → 규칙 문장 / None: LLM 호출 실패
    status: str = ''                        # 'llm' | 'fallback' | 'failed'


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


# (12주차) 초보자용 카드 한 줄 설명 — 숫자는 넣지 않는다 (정확한 규칙은 CARD_FACTS가 따로 표시)
CARD_EASY = {
    1:  '미국 대표 주식(S&P500)을 한 번에 크게 사요',
    2:  '금을 매일 조금씩 사 모아요',
    3:  '주식이 크게 떨어진 날에 싸게 사요',
    4:  '주식이 폭락한 날 금으로 피해요',
    5:  '기술주가 오르는 날 따라 사요',
    6:  '기술주가 크게 떨어진 날 싸게 사요',
    7:  '원유를 한 번에 사요',
    8:  '주식이 크게 오른 날 일부를 팔아 현금을 챙겨요',
    9:  '애플이 크게 떨어진 날 조금씩 사요',
    10: '주식과 다르게 움직이는 채권을 매일 조금씩 사요',
    11: '기술주를 며칠 간격으로 나눠 사요',
}


def market_line(req) -> str:
    """지금 시장 한 줄 — 서버 값으로 프로그램이 직접 만든다 (LLM이 틀릴 수 없음)"""
    r = req.spxReturnSoFar
    if abs(r) < 0.5:
        move = '시작 때와 비슷해요'
    else:
        move = f'시작 후 {abs(r):.1f}% {"하락" if r < 0 else "상승"}'
    return f'{move} · 하루 등락은 {volatility_words(req.spxVolatilitySoFar)}'


def default_reason(req) -> str:
    """LLM 문장을 못 쓸 때의 '그래서' 한 줄 — 확인된 사실만"""
    return f'AI는 후보 {len(req.rankings)}장 중 이 카드가 평균보다 가장 나을 것으로 예측했어요.'


def compose_feedback(req, reason: str) -> str:
    """
    (12주차) 화면용 3줄 구조. 앱은 줄 머리말로 나눠서 보여준다.
      지금 시장: (프로그램)   이 카드는: (프로그램)   그래서: (LLM 또는 기본 문장)
      카드 규칙 · (프로그램, CARD_FACTS)
    """
    ranked = sorted(req.rankings, key=lambda r: r.rank)
    if not ranked:
        return ''
    top = ranked[0].cardId
    lines = [
        f'지금 시장: {market_line(req)}',
        f'이 카드는: {CARD_EASY.get(top, "")}' if CARD_EASY.get(top) else '',
        f'그래서: {reason}',
        card_rule_header(top),
    ]
    return '\n'.join(x for x in lines if x)


def volatility_words(vol: float) -> str:
    """일별 수익률 표준편차(%)를 쉬운 말로 (S&P500 장기 평균은 약 1%)"""
    v = abs(vol)
    if v < 0.8:
        return '잠잠한 편'
    if v < 1.5:
        return '보통'
    return '크게 출렁이는 편'


def build_prompt(req: V2FeedbackRequest) -> str:
    """
    (v8.0) LLM은 "왜 지금 이 카드인지"만 설명하고, 카드 규칙(발동 조건·비율·횟수)은 쓰지 않는다.
    카드 규칙은 응답에 프로그램이 CARD_FACTS 값으로 직접 붙인다 (card_rule_header).
    LLM이 쓸 수 있는 숫자는 allowed_numbers()에 있는 값(시장 지표, V2 예측 기여도, 라운드)뿐이다.
    (12주차) 게임 화면용으로 짧고 쉬운 해요체. 시장 값은 소수 1자리로 넘기고,
    변동성은 숫자 대신 쉬운 말로 쓰게 한다.
    """
    rankings_text = format_rankings(req.rankings)
    already_text = format_already(req.alreadyCards)
    return (
        f'현재 시장: S&P500이 게임 시작 후 {req.spxReturnSoFar:.1f}%, '
        f'고점 대비 최대 {req.spxMddSoFar:.1f}%까지 떨어진 적 있음, '
        f'하루 등락폭은 {volatility_words(req.spxVolatilitySoFar)}\n'
        f'현재 라운드: {req.currentRound}\n\n'
        f'이미 보유한 카드(참고용 발동 조건):\n{already_text}\n\n'
        f'후보 카드 순위(참고용 발동 조건, 기여도는 V2 모델의 예측값):\n{rankings_text}\n\n'
        f'게임을 처음 하는 사람에게, 그래서 지금 왜 1위 카드가 유리할 수 있는지 딱 한 문장으로 말해줘.\n'
        f'(시장 상황과 카드 성격은 화면에 따로 표시되니 반복하지 말고, 둘을 잇는 이유만.)\n'
        f'규칙:\n'
        f'- 한 문장, 45자 안팎. 해요체(~해요, ~있어요)로 써.\n'
        f'- 숫자는 쓰지 마.\n'
        f'- "MDD", "변동성", "기여도", "SPX" 같은 용어 대신 쉬운 말을 써.\n'
        f'- 단정하지 마. "기대됩니다", "확실" 대신 "~할 수 있어요"로 써.\n'
        f'- 카드의 발동 조건, 매수·매도 비율, 최대 횟수는 쓰지 마.\n'
        f'- 마크다운(#, **, 목록 기호)은 쓰지 마.\n'
        f'- 카드 로직에 없는 내용은 지어내지 마.'
    )


# (v8.0) 카드 규칙 문장은 프로그램이 붙인다 — 검증기와 같은 원천(CARD_FACTS)
def card_rule_header(card_id: int) -> str:
    fact = CARD_FACTS.get(card_id)
    if not fact:
        return ''
    return f'카드 규칙 · {fact.name}: {fact.condition_desc}'


def allowed_numbers(req: V2FeedbackRequest) -> List[float]:
    """LLM 설명에 써도 되는 숫자 = 서버가 준 값 (부호 유지 — 방향 검사에 사용)"""
    vals = [req.spxReturnSoFar, req.spxVolatilitySoFar, req.spxMddSoFar, req.currentRound]
    vals += [r.contribution for r in req.rankings]
    return [float(v) for v in vals]


# 단위가 붙은 숫자만 검사 (%, %p, 회, 번, 배, 라운드) — "1위", "2~3문장" 같은 표현은 제외
# 앞의 부호(+, -, −)도 함께 잡는다
_NUM_RE = re.compile(r'([+\-−]?)(\d+(?:\.\d+)?)\s*(%p|%|회|번|배|라운드)')

# (12주차) 숫자 바로 뒤에 오는 방향 표현 — 서버 값의 부호와 반대면 막는다 (교수님 피드백 1)
_DOWN_WORDS = ('하락', '떨어', '빠졌', '빠진', '내려', '내린', '감소', '줄어', '손실', '마이너스')
_UP_WORDS = ('상승', '올랐', '오른', '올라', '증가', '늘어', '플러스')


def _claimed_sign(text: str, m: re.Match) -> int:
    """문장이 말하는 방향: -1(하락), +1(상승), 0(알 수 없음)"""
    sign = m.group(1)
    if sign in ('-', '−'):
        return -1
    if sign == '+':
        return 1
    window = text[m.end(): m.end() + 8]
    for stop in ('.', ',', '\n'):
        window = window.split(stop)[0]
    down = any(w in window for w in _DOWN_WORDS)
    up = any(w in window for w in _UP_WORDS)
    if down and not up:
        return -1
    if up and not down:
        return 1
    return 0


def unexpected_numbers(text: str, req: V2FeedbackRequest) -> List[str]:
    """
    LLM 설명에 나온 (단위가 붙은) 숫자 중 서버가 준 값이 아닌 것.
    카드 조건 %·비율·횟수를 LLM이 지어내거나 틀리게 옮기면 여기서 걸린다 (GAP 1~5).
    서버 값(소수 4자리)을 LLM이 소수 1~4자리로 반올림해 쓴 경우는 허용한다
    (-13.1912 → 13.19, 13.2). 정수로 쓴 경우는 정확히 같을 때만 허용한다
    — 정수 반올림까지 허용하면 카드 조건(-3%, -5% 등)이 우연히 통과할 수 있음 (GAP 1~5).
    (12주차) 크기가 맞아도 방향이 반대면 막는다: 서버 값 -13.19인데 "13.2% 상승" → 걸림.
    """
    allowed = allowed_numbers(req)
    bad = []
    for m in _NUM_RE.finditer(text):
        raw = m.group(2)
        v = float(raw)
        digits = len(raw.split('.')[1]) if '.' in raw else 0
        claimed = _claimed_sign(text, m)
        ok = False
        for a in allowed:
            same_size = abs(v - abs(a)) < 1e-9 or (
                digits >= 1 and abs(v - round(abs(a), digits)) < 1e-9)
            if not same_size:
                continue
            actual = 0 if a == 0 else (1 if a > 0 else -1)
            if claimed == 0 or actual == 0 or claimed == actual:
                ok = True
                break
        if not ok:
            bad.append(m.group(0).strip())
    return bad


# 무조건부/1회성/정기 카드를 "~할 때 매수"처럼 조건부로 설명했는지 (GAP 6)
_COND_WORDS = ('때', '경우', '면 ')
_TRADE_WORDS = ('매수', '매도', '사들', '산다', '사는', '팔', '발동')


def unconditional_misdescribed(text: str) -> List[str]:
    issues = []
    for fact in CARD_FACTS.values():
        if fact.trigger_type not in ('UNCONDITIONAL', 'PERIODIC', 'ONCE'):
            continue
        for m in re.finditer(re.escape(fact.name), text):
            window = text[m.end(): m.end() + 30]
            if any(w in window for w in _COND_WORDS) and any(w in window for w in _TRADE_WORDS):
                issues.append(f"'{fact.name}'은 조건 없는 카드인데 조건부처럼 서술됨 → \"{fact.name}{window}\"")
    return issues


def strip_markdown(text: str) -> str:
    text = re.sub(r'^\s*#+\s*', '', text, flags=re.MULTILINE)
    return text.replace('**', '').replace('__', '').strip()


def llm_text(prompt: str, max_tokens: int = 500) -> str:
    """
    (#125) LLM을 한 번 호출해 글만 꺼낸다. 실패하면 예외 (부르는 쪽에서 기본 문장으로 응답).
    응답의 첫 블록이 글이 아닐 수 있어(생각 블록 등) 글 블록만 모은다.
    글 블록이 하나도 없으면(응답 거절 등) 실패로 본다.
    """
    msg = client.messages.create(
        model=LLM_MODEL,
        max_tokens=max_tokens,
        messages=[{'role': 'user', 'content': prompt}],
    )
    parts = [b.text for b in msg.content
             if getattr(b, 'type', 'text') == 'text' and getattr(b, 'text', None)]
    if not parts:
        raise RuntimeError(f'LLM 응답에 글이 없습니다 (stop_reason={getattr(msg, "stop_reason", None)})')
    return ''.join(parts)


# =============================================
# 엔드포인트
# =============================================

def _game_end_date(start_date: str) -> Optional[pd.Timestamp]:
    """시작일 기준 100번째 SPX 거래일 (게임 마지막 라운드 날짜)"""
    spx = load_all().get('^SPX', pd.DataFrame())
    if spx.empty:
        return None
    dates = pd.DatetimeIndex(spx['Date']).sort_values()
    i = dates.searchsorted(pd.Timestamp(start_date), side='left') + (GAME_ROUNDS - 1)
    return dates[i] if i < len(dates) else dates[-1]


def select_v2_model(start_date: Optional[str]):
    """
    게임 기간에 맞는 V2 모델 선택 → (모델, 버전 이름)
      - 게임 기간이 리먼 제외 구간과 겹치면 모델 B (그 구간을 학습하지 않은 모델)
      - 그 외(닷컴·코로나 등)는 모델 A
      - A/B 파일이 없으면 기존 model_v2.pkl로 대체
    """
    use_b = False
    if start_date:
        start = pd.Timestamp(start_date)
        end = _game_end_date(start_date) or start
        use_b = start <= LEHMAN_EXCLUDE_END and end >= LEHMAN_EXCLUDE_START

    if use_b and model_v2_b is not None:
        return model_v2_b, 'v2_B'
    if not use_b and model_v2_a is not None:
        return model_v2_a, 'v2_A'
    return model_v2, 'v2_legacy'


@app.get('/')
def health_check():
    return {
        'status': 'ok',
        'v15_model': model_v15 is not None,
        'v2_model':  model_v2  is not None,
        'v2_model_A': model_v2_a is not None,
        'v2_model_B': model_v2_b is not None,
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
    model, model_version = select_v2_model(req.startDate)
    if model is None:
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

        predictions = model.predict(features)

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
            rankings=rankings,
            modelVersion=model_version,
        )

    except Exception as e:
        raise HTTPException(status_code=500, detail=f'V2 추천 오류: {str(e)}')


def build_fallback_feedback(req: V2FeedbackRequest) -> str:
    """
    검증 실패 시 대체 피드백 (v7.0)
    LLM 문장을 쓰지 않고, 확인된 정보만으로 만든다.
      - 카드 규칙: verify_feedback.CARD_FACTS (검증기와 같은 원천)
      - 순위·기여도: V2 출력값 그대로
    """
    ranked = sorted(req.rankings, key=lambda r: r.rank)
    if not ranked:
        return ''
    return compose_feedback(req, default_reason(req))


@app.post('/ai/v2/feedback', response_model=V2FeedbackResponse)
def generate_feedback(req: V2FeedbackRequest):
    """
    V2 LLM 자연어 피드백 (v5.0 신규, v8.0 출력 통제)
    /ai/v2/recommend 결과(rankings) + 시장 상황 → Claude API로 "왜 이 카드인지" 설명 생성

    v8.0 출력 구조
      - 카드 규칙(조건·비율·횟수): 프로그램이 CARD_FACTS 값으로 직접 붙임 → LLM이 틀릴 수 없음
      - LLM 설명: 카드 규칙 숫자를 쓰지 않도록 지시 + 검사 3가지(검증기 v3, 숫자 출처, 무조건부 카드 조건화)
      - 검사 실패 → 확인된 정보만으로 만든 대체 문장 (status='fallback')
      - LLM 호출 실패 → 기본 문장 + 카드 규칙 (status='failed'), 200 반환 (게임 진행에 영향 없음)
    (12주차) 응답은 3줄 구조(compose_feedback): 지금 시장 / 이 카드는 / 그래서. LLM은 '그래서' 한 줄만 쓴다.
    """
    try:
        text = strip_markdown(llm_text(build_prompt(req)))
    except Exception as e:
        # (v8.0) 빈 문자열 대신 "생성 실패" 상태를 알리고, 카드 규칙은 그대로 보여준다
        print(f'⚠️  LLM 피드백 생성 실패: {e}')
        return V2FeedbackResponse(feedback=compose_feedback(req, default_reason(req)), verified=None, status='failed')

    # 사용자에게 보내기 전 검사 3가지
    #   1) 규칙 기반 검증기 v3 (조건 %·미포함 카드·무제한 등)
    #   2) 숫자 출처 검사: 서버가 준 값이 아닌 숫자 → 카드 규칙을 지어내거나 틀리게 옮긴 것 (GAP 1~5)
    #   3) 조건 없는 카드를 조건부로 서술 (GAP 6)
    result = verify_feedback(
        text,
        already_cards=req.alreadyCards,
        ranking_card_ids=[r.cardId for r in req.rankings],
    )
    issues = list(result.issues)
    bad_nums = unexpected_numbers(text, req)
    if bad_nums:
        issues.append(f'[숫자 출처 불명] 서버가 준 값이 아닌 숫자: {bad_nums}')
    issues += [f'[조건부로 오기재] {x}' for x in unconditional_misdescribed(text)]

    if not issues:
        feedback = compose_feedback(req, ' '.join(text.split()))
        return V2FeedbackResponse(feedback=feedback, verified=True, status='llm')

    print('⚠️  LLM 피드백 검사 실패 → 대체 문장으로 응답')
    print(f'    원문: {text}')
    for issue in issues:
        print(f'    - {issue}')
    return V2FeedbackResponse(feedback=build_fallback_feedback(req), verified=False, status='fallback')


@app.post('/ai/analysis/backtest', response_model=BacktestResponse)
def analysis_backtest(req: BacktestRequest):
    """
    사후 분석 (v6.0 신규)
    같은 시작일에서 사용 가능한 카드로 만든 4장 전체 순열을 실제 게임 로직으로 시뮬레이션하고,
    플레이어 조합의 최종 자산 순위/백분위를 반환한다.
    (11주차) offeredCards를 주면 "받은 후보 안 최선 조합"과 라운드별 대안(offeredAnalysis)도 반환한다.
    def(동기)로 선언해 FastAPI가 별도 스레드에서 실행 → 계산 중에도 다른 요청이 막히지 않음.
    (#125) decisions(위기 대응)를 주면 모든 조합을 같은 위기 대응으로 계산한다.
           등급·최대 낙폭·카드별 성적표·위기 대응 돌아보기·그 후 이야기를 함께 반환한다.
           전체 조합 결과는 (시작일, 위기 대응)별로 캐시된다.
    """
    return _run_analysis(req)


def _run_analysis(req: BacktestRequest) -> dict:
    if not 1 <= req.topN <= 20:
        raise HTTPException(status_code=400, detail='topN은 1~20 사이여야 합니다')
    try:
        return run_backtest(req.startDate, req.playerCardSelections, req.topN,
                            offered_cards=req.offeredCards,
                            decisions=req.decisions,
                            base_ticker=req.baseTicker or '^SPX')
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f'백테스팅 오류: {str(e)}')


@app.post('/ai/analysis/prewarm', response_model=PrewarmResponse)
def analysis_prewarm(req: PrewarmRequest):
    """
    (#125) 전체 조합 결과를 백그라운드에서 미리 계산해 둔다. 바로 응답한다.
    게임 서버가 마지막 위기 대응이 정해진 뒤 호출 → 결과 화면에 들어왔을 때 계산이 이미 끝나 있다.
    계산 중에 결과 화면 요청이 오면 같은 계산이 끝나기를 기다려 그 결과를 쓴다 (두 번 계산하지 않음).
    """
    try:
        return PrewarmResponse(status=prewarm(req.startDate, req.decisions, req.baseTicker or '^SPX'))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.post('/ai/analysis/coach', response_model=CoachResponse)
def analysis_coach(req: BacktestRequest):
    """
    (#125) 사후 분석 AI 코치 한마디. 요청은 /ai/analysis/backtest와 같다 (분석 결과는 캐시에서 다시 가져옴).
      - 요약·잘한 점·아쉬운 점·위기 대응: 프로그램이 사후 분석 숫자로 직접 작성 → LLM이 틀릴 수 없음
      - 다음엔: LLM 한 문장. 검사(숫자·단정 표현·없는 카드·카드 조건 오기재·무조건부 카드 조건화)에 걸리면
                규칙 기반 문장으로 바꾼다 (status='fallback')
      - LLM 호출 실패 → 규칙 기반 문장 (status='failed'), 200 반환 (결과 화면에 영향 없음)
    """
    analysis = _run_analysis(req)
    lines = result_coach.fact_lines(analysis)
    fallback_tip = result_coach.rule_based_tip(analysis)

    try:
        text = ' '.join(strip_markdown(llm_text(result_coach.build_prompt(analysis), max_tokens=300)).split())
    except Exception as e:
        print(f'⚠️  LLM 코치 문장 생성 실패: {e}')
        return CoachResponse(comment=result_coach.compose(lines, fallback_tip), verified=None, status='failed')

    player_cards = [int(c) for c in req.playerCardSelections.values()]
    issues = result_coach.check_tip(text, player_cards)
    issues += [f'[조건부로 오기재] {x}' for x in unconditional_misdescribed(text)]
    if not issues:
        return CoachResponse(comment=result_coach.compose(lines, text), verified=True, status='llm')

    print('⚠️  LLM 코치 문장 검사 실패 → 규칙 기반 문장으로 응답')
    print(f'    원문: {text}')
    for issue in issues:
        print(f'    - {issue}')
    return CoachResponse(comment=result_coach.compose(lines, fallback_tip), verified=False, status='fallback')


# =============================================
# 실행
# =============================================
if __name__ == '__main__':
    import uvicorn
    uvicorn.run(app, host='0.0.0.0', port=8000)