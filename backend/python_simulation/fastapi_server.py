"""
FastAPI AI 추천 서버
포트: 8000

엔드포인트:
  POST /ai/v1/recommend — V1.5 사전 추천 (게임 시작 시)
  POST /ai/v2/recommend — V2 실시간 추천 (25·50라운드)
  POST /ai/v2/feedback  — V2 LLM 자연어 피드백 (25·50라운드, v5.0 신규)
  POST /ai/analysis/backtest — 사후 분석: 전체 조합 백테스팅 (v6.0 신규, 사용 가능 카드 기준)

Java Spring Boot가 내부적으로 호출. Flutter는 직접 호출하지 않음.
"""
import os
import re
import pickle
import numpy as np
from itertools import permutations
from typing import Dict, List, Optional
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import anthropic
from backtest import run_backtest
from verify_feedback import verify_feedback, CARD_FACTS
from data_loader import load_all
import pandas as pd

client = anthropic.Anthropic()

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
app = FastAPI(title='투자 서바이벌 AI 추천 서버', version='6.0')

model_v15 = None
model_v2  = None   # 기존 V2
model_v2_a = None
model_v2_b = None

@app.on_event('startup')
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

class BacktestResponse(BaseModel):
    totalCombinations: int
    cardPoolSize: int                       # 시작일에 사용 가능한 카드 수 (상장 전 종목 카드 제외)
    topCombos: List[BacktestCombo]
    playerResult: BacktestPlayerResult


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
    """
    (v8.0) LLM은 "왜 지금 이 카드인지"만 설명하고, 카드 규칙(발동 조건·비율·횟수)은 쓰지 않는다.
    카드 규칙은 응답에 프로그램이 CARD_FACTS 값으로 직접 붙인다 (card_rule_header).
    LLM이 쓸 수 있는 숫자는 allowed_numbers()에 있는 값(시장 지표, V2 예측 기여도, 라운드)뿐이다.
    """
    rankings_text = format_rankings(req.rankings)
    already_text = format_already(req.alreadyCards)
    return (
        f'현재 시장: SPX 누적수익률 {req.spxReturnSoFar}%, '
        f'변동성 {req.spxVolatilitySoFar}, MDD {req.spxMddSoFar}%\n'
        f'현재 라운드: {req.currentRound}\n\n'
        f'이미 보유한 카드(참고용 발동 조건):\n{already_text}\n\n'
        f'후보 카드 순위(참고용 발동 조건, 기여도는 V2 모델의 예측값):\n{rankings_text}\n\n'
        f'1위 카드가 지금 시장 상황에서 왜 유리할 수 있는지 2~3문장의 한국어 평문으로 설명해줘.\n'
        f'규칙:\n'
        f'- 카드의 발동 조건, 매수·매도 비율, 최대 횟수는 쓰지 마. 카드 규칙은 화면에 따로 정확하게 표시돼.\n'
        f'- 숫자는 위에 나온 시장 수치와 예측 기여도만 그대로 쓸 수 있어. 기여도를 쓸 때는 "예측"이라고 밝혀.\n'
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
    """LLM 설명에 써도 되는 숫자 = 서버가 준 값 (부호 무시)"""
    vals = [req.spxReturnSoFar, req.spxVolatilitySoFar, req.spxMddSoFar, req.currentRound]
    vals += [r.contribution for r in req.rankings]
    return [abs(float(v)) for v in vals]


# 단위가 붙은 숫자만 검사 (%, %p, 회, 번, 배, 라운드) — "1위", "2~3문장" 같은 표현은 제외
_NUM_RE = re.compile(r'(\d+(?:\.\d+)?)\s*(%p|%|회|번|배|라운드)')


def unexpected_numbers(text: str, req: V2FeedbackRequest) -> List[str]:
    """
    LLM 설명에 나온 (단위가 붙은) 숫자 중 서버가 준 값이 아닌 것.
    카드 조건 %·비율·횟수를 LLM이 지어내거나 틀리게 옮기면 여기서 걸린다 (GAP 1~5).
    소수 첫째 자리 반올림 표기(-17.27 → -17.3)까지만 허용.
    """
    allowed = allowed_numbers(req)
    bad = []
    for m in _NUM_RE.finditer(text):
        v = float(m.group(1))
        ok = any(abs(v - a) < 1e-9 or abs(v - round(a, 1)) < 1e-9 for a in allowed)
        if not ok:
            bad.append(m.group(0))
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
    top = ranked[0]
    top_fact = CARD_FACTS.get(top.cardId)
    top_name = top_fact.name if top_fact else CARD_NAMES.get(top.cardId, f'카드{top.cardId}')
    lines = [
        f'AI 추천: {top_name}',
        card_rule_header(top.cardId),
        'V2 예측 기여도(실측 아님): ' + ', '.join(
            f'{CARD_FACTS[r.cardId].name if r.cardId in CARD_FACTS else r.cardId} {r.contribution:+.2f}%'
            for r in ranked
        ),
        '(AI 설명을 검증하지 못해 확인된 카드 규칙과 예측값만 표시해요)',
    ]
    return '\n'.join(lines)


@app.post('/ai/v2/feedback', response_model=V2FeedbackResponse)
def generate_feedback(req: V2FeedbackRequest):
    """
    V2 LLM 자연어 피드백 (v5.0 신규, v8.0 출력 통제)
    /ai/v2/recommend 결과(rankings) + 시장 상황 → Claude API로 "왜 이 카드인지" 설명 생성

    v8.0 출력 구조
      - 카드 규칙(조건·비율·횟수): 프로그램이 CARD_FACTS 값으로 직접 붙임 → LLM이 틀릴 수 없음
      - LLM 설명: 카드 규칙 숫자를 쓰지 않도록 지시 + 검사 3가지(검증기 v3, 숫자 출처, 무조건부 카드 조건화)
      - 검사 실패 → 확인된 정보만으로 만든 대체 문장 (status='fallback')
      - LLM 호출 실패 → "생성 실패" 문구 + 카드 규칙 (status='failed'), 200 반환 (게임 진행에 영향 없음)
    """
    ranked = sorted(req.rankings, key=lambda r: r.rank)
    header = card_rule_header(ranked[0].cardId) if ranked else ''

    try:
        msg = client.messages.create(
            model='claude-sonnet-4-6',
            max_tokens=500,
            messages=[{'role': 'user', 'content': build_prompt(req)}]
        )
        text = strip_markdown(msg.content[0].text)
    except Exception as e:
        # (v8.0) 빈 문자열 대신 "생성 실패" 상태를 알리고, 카드 규칙은 그대로 보여준다
        print(f'⚠️  LLM 피드백 생성 실패: {e}')
        failed = '\n'.join(x for x in [header, '(AI 설명 생성에 실패했어요. 카드 규칙만 표시해요)'] if x)
        return V2FeedbackResponse(feedback=failed, verified=None, status='failed')

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
        feedback = '\n\n'.join(x for x in [header, text] if x)
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
    def(동기)로 선언해 FastAPI가 별도 스레드에서 실행 → 계산 중에도 다른 요청이 막히지 않음.
    """
    if not 1 <= req.topN <= 20:
        raise HTTPException(status_code=400, detail='topN은 1~20 사이여야 합니다')
    try:
        return run_backtest(req.startDate, req.playerCardSelections, req.topN)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f'백테스팅 오류: {str(e)}')


# =============================================
# 실행
# =============================================
if __name__ == '__main__':
    import uvicorn
    uvicorn.run(app, host='0.0.0.0', port=8000)