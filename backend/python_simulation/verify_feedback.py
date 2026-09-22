"""
verify_feedback.py — LLM 자연어 피드백 사실 왜곡 검증 (방식 A: 규칙 기반)

LLM이 생성한 feedback 문장이 다음 두 가지와 모순되지 않는지 기계적으로 확인한다.
  1) 카드의 실제 발동 조건 (CARD_FACTS 기준)
  2) V2 출력값 (rankings의 contribution, 시장 지표 등)

v3 변경 사항 (test_verify_feedback.py 자기 테스트로 발견한 문제 수정):
  - CARD_FACTS[11](분할매수 장인) buy_ratio_pct가 None으로 비어 있었음 →
    실제 game_logic.py CARDS[11]['ratio']=0.10 확인 후 10으로 수정 (교수님 지적 ③: 데이터 드리프트 실사례)
  - "조건 % 검사"를 절(clause) 단위 + 제외 키워드 방식에서, 카드 이름 등장 위치 기준
    근접 윈도우(앞 5자~뒤 25자) 방식으로 교체:
    * 기존 방식은 "기여도/수익률/MDD" 같은 키워드가 절에 있으면 조건 검사 자체를 건너뛰어서
      그 안에 숨은 진짜 오류를 못 잡는 사각지대가 있었음 (교수님 지적 ②, TC09로 재현)
    * 기존 방식은 한 절에 카드 이름이 2개 이상 있으면 %가 엉뚱한 카드 것으로 오귀속되는
      문제도 있었음 (PR #66 알려진 한계, TC10으로 재현)
    * 새 방식은 카드 이름 "근처"에 있는 %만 그 카드의 조건 후보로 보므로 두 문제를 동시에 해결
"""
import re
from dataclasses import dataclass, field
from typing import List, Dict, Optional


# =============================================
# 카드 사실 정보 (구조화) — game_logic.py CARDS 기준
# CARD_LOGIC(사람이 읽는 문장)은 이 구조에서 자동 생성해서 쓰는 걸 권장.
# 문장과 구조가 따로 놀면 검증 자체가 무의미해지기 때문.
# =============================================
@dataclass
class CardFact:
    id: int
    name: str
    ticker: str
    trigger_type: str          # ONCE / UNCONDITIONAL / CONDITION / PERIODIC
    condition_desc: str        # 사람이 읽는 조건 설명 (예: "SPX -5% 이하")
    threshold_pcts: List[float] = field(default_factory=list)   # 조건에 쓰이는 %(들)
    buy_ratio_pct: Optional[float] = None   # 매수/매도 비율(%)
    max_trigger: Optional[int] = None        # 최대 발동 횟수 (없으면 무제한/1회성 등으로 표현)
    period_rounds: Optional[int] = None      # 정기 매수 주기(라운드)


CARD_FACTS: Dict[int, CardFact] = {
    1: CardFact(1, '거인의 어깨', '^SPX', 'ONCE',
                '1라운드 즉시 현금 30% SPX 매수 (1회성)',
                threshold_pcts=[], buy_ratio_pct=30, max_trigger=1),
    2: CardFact(2, '황금 적립', 'GLD', 'UNCONDITIONAL',
                '매 라운드 조건 없이 현금 5%씩 GLD 매수 (무제한)',
                threshold_pcts=[], buy_ratio_pct=5, max_trigger=None),
    3: CardFact(3, '공포탐욕', '^SPX', 'CONDITION',
                'SPX 전일대비 -3% 이하일 때마다 현금 20% SPX 매수',
                threshold_pcts=[-3], buy_ratio_pct=20, max_trigger=None),
    4: CardFact(4, '금 피난처', 'GLD', 'CONDITION',
                'SPX 전일대비 -5% 이하일 때마다 현금 15% GLD 매수',
                threshold_pcts=[-5], buy_ratio_pct=15, max_trigger=None),
    5: CardFact(5, '기술의 파도', '^NDX', 'CONDITION',
                'NDX 전일대비 +2% 이상일 때마다 현금 10% NDX 매수',
                threshold_pcts=[2], buy_ratio_pct=10, max_trigger=None),
    6: CardFact(6, '낙폭과대 사냥', '^NDX', 'CONDITION',
                'NDX -4% 이하일 때 현금 25% NDX 매수 (최대 3회)',
                threshold_pcts=[-4], buy_ratio_pct=25, max_trigger=3),
    7: CardFact(7, '원유 베팅', 'USO', 'ONCE',
                '1라운드 즉시 현금 20% USO 매수 (1회성)',
                threshold_pcts=[], buy_ratio_pct=20, max_trigger=1),
    8: CardFact(8, '역발상 투자', '^SPX', 'CONDITION',
                'SPX +3% 이상일 때마다 보유 SPX 물량 15% 매도',
                threshold_pcts=[3], buy_ratio_pct=15, max_trigger=None),
    9: CardFact(9, '애플 줍줍', 'AAPL', 'CONDITION',
                'AAPL -5% 이하일 때마다 현금 10% AAPL 매수 (최대 5회)',
                threshold_pcts=[-5], buy_ratio_pct=10, max_trigger=5),
    10: CardFact(10, '채권 피난처', 'TLT', 'UNCONDITIONAL',
                 '매 라운드 조건 없이 현금 3%씩 TLT 매수 (무제한)',
                 threshold_pcts=[], buy_ratio_pct=3, max_trigger=None),
    11: CardFact(11, '분할매수 장인', '^NDX', 'PERIODIC',
                 '조건 없이 5라운드마다 현금 10% NDX 매수',
                 threshold_pcts=[], buy_ratio_pct=10, max_trigger=None, period_rounds=5),
}

CARD_NAME_TO_ID = {c.name: c.id for c in CARD_FACTS.values()}


# =============================================
# 검증 결과 구조
# =============================================
@dataclass
class VerificationResult:
    consistent: bool
    issues: List[str]
    mentioned_cards: List[str]


def _split_sentences(text: str) -> List[str]:
    # 한국어 문장 분리는 완벽할 수 없으니, 마침표/느낌표/물음표 기준의 단순 분리로 충분
    return [s.strip() for s in re.split(r'(?<=[.!?])\s+', text) if s.strip()]


def _split_clauses(sentence: str) -> List[str]:
    """
    문장 하나에 여러 카드/지표가 쉼표로 나열되는 경우가 많아서
    (예: "A는 ..., B는 -1.89%로 손실 가능성이 높고, C는 ...")
    쉼표 기준으로 더 잘게 쪼개서 검사 단위를 좁힌다.
    """
    return [c.strip() for c in re.split(r'[,，]', sentence) if c.strip()]


# 카드 자체의 발동 조건(임계값 %)을 서술할 때 실제로 같이 쓰이는 표현.
# %값 주변에 이 표현이 없으면 %가 있어도 "조건 서술"로 보지 않는다.
_CONDITION_TRIGGER_KEYWORDS = [
    '이하', '이상', '급락', '상승', '반등',
]

# 카드 이름 등장 위치 기준 근접 윈도우 (문자 수).
# "카드이름은 SPX가 -3% 이하일 때 ..." 같은 한국어 어순에서
# 조건 서술은 보통 카드 이름 뒤에 붙으므로 뒤쪽을 더 넓게 잡는다.
_NAME_WINDOW_BEFORE = 5
_NAME_WINDOW_AFTER = 25

# %값이 "조건성"인지 판단할 때, 그 % 주변 몇 자 이내에 트리거 단어가 있어야 하는지
_TRIGGER_NEARBY_SPAN = 10


def _extract_percentages(text: str) -> List[float]:
    """텍스트에서 '+2%', '-5%', '30%' 같은 퍼센트 숫자를 부호 포함으로 추출"""
    found = re.findall(r'([+-]?\d+(?:\.\d+)?)\s*%', text)
    return [float(f) for f in found]


def _extract_condition_percentages_near_name(sentence: str, name: str) -> List[float]:
    """
    문장에서 카드 이름이 등장한 위치 '근처'에 있는 조건성 %만 추출한다.

    - 근접 윈도우: 이름 등장 위치의 앞 5자 ~ 뒤 25자. 한 절/문장에 카드가
      여러 개 나열돼도, 이름과 멀리 떨어진 다른 카드의 %를 끌어와
      잘못 대조하는 오귀속을 막기 위함 (예: TC10).
    - 조건성 판단: %값 주변(앞뒤 10자 이내)에 이하/이상/급락/상승/반등 같은
      조건 서술어가 있는 경우만 "이 카드의 조건 %"로 인정한다. 절 전체에
      '기여도/수익률/MDD' 같은 무관한 키워드가 섞여 있어도, %값 바로 옆에
      조건 서술어가 붙어 있으면 정상적으로 검사 대상에 포함된다 (예: TC09).
    """
    results: List[float] = []
    for name_match in re.finditer(re.escape(name), sentence):
        win_start = max(0, name_match.start() - _NAME_WINDOW_BEFORE)
        win_end = min(len(sentence), name_match.end() + _NAME_WINDOW_AFTER)
        window_text = sentence[win_start:win_end]

        for pct_match in re.finditer(r'([+-]?\d+(?:\.\d+)?)\s*%', window_text):
            pct_pos = pct_match.start()
            nearby = window_text[max(0, pct_pos - _TRIGGER_NEARBY_SPAN): pct_pos + _TRIGGER_NEARBY_SPAN]
            if any(t in nearby for t in _CONDITION_TRIGGER_KEYWORDS):
                results.append(float(pct_match.group(1)))
    return results


def verify_feedback(
    feedback_text: str,
    already_cards: List[int],
    ranking_card_ids: List[int],
) -> VerificationResult:
    """
    feedback_text: LLM이 생성한 자연어 피드백
    already_cards: 요청에 실제로 포함된 이미 보유한 카드 ID
    ranking_card_ids: 요청에 실제로 포함된 rankings의 카드 ID 목록
    """
    issues: List[str] = []
    valid_ids = set(already_cards) | set(ranking_card_ids)
    mentioned_cards: List[str] = []

    if not feedback_text:
        return VerificationResult(consistent=True, issues=[], mentioned_cards=[])

    sentences = _split_sentences(feedback_text)

    # 카드 이름이 등장하는 문장 단위로 검사 (이름이 겹치는 경우 방지 위해 exact match)
    for sentence in sentences:
        for name, cid in CARD_NAME_TO_ID.items():
            if name not in sentence:
                continue
            mentioned_cards.append(name)
            fact = CARD_FACTS[cid]

            # 1) 입력에 없는 카드를 언급했는가 (지어낸 카드 근거)
            if cid not in valid_ids:
                issues.append(
                    f"[미포함 카드 언급] '{name}'은 이번 요청의 alreadyCards/rankings에 없는데 언급됨"
                )
                continue  # 애초에 관련 없는 카드면 아래 조건 대조는 의미 없음

            # 2) 조건부 카드인데 엉뚱한 %가 붙었는가
            #    - 카드 "이름 근처"에 있는 조건성 %만 검사 대상으로 삼는다 (v3)
            #      → 절 전체를 보지 않으므로, 무관한 키워드에 가려 놓치는 사각지대(TC09)와
            #        절 안의 다른 카드 %를 잘못 끌어오는 오귀속(TC10)을 동시에 방지
            if fact.trigger_type == 'CONDITION' and fact.threshold_pcts:
                near_pcts = _extract_condition_percentages_near_name(sentence, name)
                if near_pcts:
                    match = any(
                        abs(p - t) < 0.5  # 반올림 오차 허용
                        for p in near_pcts
                        for t in fact.threshold_pcts
                    )
                    if not match:
                        issues.append(
                            f"[조건 불일치 의심] '{name}' 근처에 등장한 %({near_pcts})가 "
                            f"실제 발동 조건({fact.threshold_pcts}%)과 다름 → 문장: \"{sentence}\""
                        )

            clauses_with_name_all = [c for c in _split_clauses(sentence) if name in c]

            # 3) 무조건부/정기 카드인데 조건부처럼 서술했는가 (예: "-5% 이하일 때" 같은 조건어 사용)
            if fact.trigger_type in ('UNCONDITIONAL', 'PERIODIC'):
                for clause in clauses_with_name_all:
                    if re.search(r'(이하|이상|급락|상승)\s*(일|할)\s*때', clause):
                        issues.append(
                            f"[조건부로 오기재 의심] '{name}'은 무조건부/정기 매수 카드인데 "
                            f"조건부처럼 서술됨 → 절: \"{clause}\""
                        )

            # 4) 최대 발동 횟수 오기재 (예: "무제한"이라 했는데 실제로는 최대 N회)
            if fact.max_trigger is not None:
                for clause in clauses_with_name_all:
                    if '무제한' in clause:
                        issues.append(
                            f"[최대 횟수 오기재] '{name}'은 최대 {fact.max_trigger}회 제한이 있는데 "
                            f"'무제한'으로 서술됨 → 절: \"{clause}\""
                        )

    return VerificationResult(
        consistent=len(issues) == 0,
        issues=issues,
        mentioned_cards=list(dict.fromkeys(mentioned_cards)),  # 중복 제거, 순서 유지
    )