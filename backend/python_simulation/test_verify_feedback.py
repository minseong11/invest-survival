"""
test_verify_feedback.py — verify_feedback() 자체를 검증하는 자기 테스트 (self-test)

교수님 피드백 ①③을 반영한 스크립트.
  - "99% 통과"라는 숫자는 검증기가 위반을 못 잡았다는 뜻일 뿐, 실제로 옳았다는
    증거가 아니다 → 정답(기대값)을 사람이 미리 정해둔 케이스로 검증기 자체를 검사한다.
  - 규칙 v2에서 추가한 "기여도/수익률/MDD 등 키워드가 있으면 조건 검사 제외" 로직이
    새로운 사각지대(진짜 오류가 숨어도 못 잡음)를 만드는지 TC09에서 직접 확인한다.

각 테스트케이스(TC)는 (feedback_text, already_cards, ranking_card_ids, 기대결과)로 구성되고,
실제 verify_feedback() 결과와 기대결과를 비교해 PASS/FAIL을 출력한다.
여기서 "PASS"는 "검증기가 우리가 예상한 대로 동작했다"는 뜻이지,
"검증기가 항상 옳다"는 뜻이 아니다 (TC09는 일부러 검증기의 한계를 드러내는 케이스).
"""

from verify_feedback import verify_feedback, CARD_FACTS


# 카드 ID 참고 (CARD_FACTS 기준)
# 1 거인의 어깨(ONCE, SPX)         2 황금 적립(UNCONDITIONAL, GLD)
# 3 공포탐욕(CONDITION -3%, SPX)   4 금 피난처(CONDITION -5%, GLD)
# 5 기술의 파도(CONDITION +2%, NDX) 6 낙폭과대 사냥(CONDITION -4%, max3, NDX)
# 7 원유 베팅(ONCE, USO)           8 역발상 투자(CONDITION +3%, SPX)
# 9 애플 줍줍(CONDITION -5%, max5, AAPL) 10 채권 피난처(UNCONDITIONAL, TLT)
# 11 분할매수 장인(PERIODIC 5라운드, NDX)


TEST_CASES = []


def tc(name, feedback_text, already_cards, ranking_card_ids,
       expect_consistent, expect_issue_keywords=None, note=""):
    """expect_issue_keywords: issues 리스트 각 항목에 반드시 포함돼야 하는 부분 문자열 목록(개수 무관, 존재 여부만 체크)"""
    TEST_CASES.append(dict(
        name=name, feedback_text=feedback_text,
        already_cards=already_cards, ranking_card_ids=ranking_card_ids,
        expect_consistent=expect_consistent,
        expect_issue_keywords=expect_issue_keywords or [],
        note=note,
    ))


# ── TC01: PASS — 조건부 카드, % 정확히 일치 ─────────────────────────────
tc(
    "TC01_condition_pct_correct",
    "공포탐욕은 SPX가 -3% 이하일 때마다 SPX를 추가 매수하는 카드입니다.",
    already_cards=[3], ranking_card_ids=[],
    expect_consistent=True,
    note="실제 threshold -3%와 문장의 -3%가 일치 → 위반 없어야 함",
)

# ── TC02: FAIL — 조건부 카드, % 불일치 (진짜 사실 왜곡) ──────────────────
tc(
    "TC02_condition_pct_wrong",
    "금 피난처는 SPX가 -3% 이하일 때 GLD를 매수합니다.",
    already_cards=[4], ranking_card_ids=[],
    expect_consistent=False,
    expect_issue_keywords=["조건 불일치 의심", "금 피난처"],
    note="실제 threshold는 -5%인데 문장은 -3% → [조건 불일치 의심]이 잡혀야 함",
)

# ── TC03: PASS — 무조건부 카드를 무조건부로 정확히 서술 ───────────────────
tc(
    "TC03_unconditional_correct",
    "황금 적립은 조건 없이 매 라운드 현금 5%로 GLD를 꾸준히 매수합니다.",
    already_cards=[2], ranking_card_ids=[],
    expect_consistent=True,
    note="UNCONDITIONAL 카드를 조건 없다고 정확히 서술 → 위반 없어야 함",
)

# ── TC04: FAIL — 무조건부 카드를 조건부처럼 서술 ─────────────────────────
tc(
    "TC04_unconditional_described_as_condition",
    "황금 적립은 SPX가 -5% 이하일 때 GLD를 매수하는 카드입니다.",
    already_cards=[2], ranking_card_ids=[],
    expect_consistent=False,
    expect_issue_keywords=["조건부로 오기재 의심", "황금 적립"],
    note="UNCONDITIONAL 카드인데 '-5% 이하일 때'로 조건부처럼 서술 → 잡혀야 함",
)

# ── TC05: PASS — 최대 발동 횟수 있는 카드를 정확히 서술 ───────────────────
tc(
    "TC05_max_trigger_correct",
    "낙폭과대 사냥은 NDX가 -4% 이하일 때 매수하며, 최대 3회까지만 발동합니다.",
    already_cards=[6], ranking_card_ids=[],
    expect_consistent=True,
    note="max_trigger=3인 카드를 '최대 3회'로 정확히 서술 → 위반 없어야 함",
)

# ── TC06: FAIL — 최대 횟수 제한 있는 카드를 '무제한'으로 오기재 ───────────
tc(
    "TC06_max_trigger_wrong",
    "애플 줍줍은 무제한으로 AAPL을 매수할 수 있어 장기적으로 유리합니다.",
    already_cards=[9], ranking_card_ids=[],
    expect_consistent=False,
    expect_issue_keywords=["최대 횟수 오기재", "애플 줍줍"],
    note="실제로는 max_trigger=5인데 '무제한'으로 서술 → 잡혀야 함",
)

# ── TC07: FAIL — 요청에 없는 카드를 지어내서 언급(환각) ──────────────────
tc(
    "TC07_hallucinated_card_not_in_request",
    "이번 판은 원유 베팅 덕분에 초반 수익률이 좋았습니다.",
    already_cards=[2, 10], ranking_card_ids=[3, 4],
    expect_consistent=False,
    expect_issue_keywords=["미포함 카드 언급", "원유 베팅"],
    note="already_cards/rankings 어디에도 없는 '원유 베팅'(id=7)을 언급 → 잡혀야 함",
)

# ── TC08: PASS — 여러 카드가 각각 다른 절(clause)에서 모두 정확히 서술 ────
tc(
    "TC08_multiple_cards_all_correct",
    "공포탐욕은 -3% 이하 하락 시 매수하고, 채권 피난처는 조건 없이 매 라운드 TLT를 3%씩 매수합니다.",
    already_cards=[10], ranking_card_ids=[3],
    expect_consistent=True,
    note="조건부(공포탐욕)와 무조건부(채권 피난처) 모두 정확히 서술 → 위반 없어야 함",
)

# ── TC09: 교수님 지적 ②의 사각지대 — v3에서 수정됐는지 확인 ──
tc(
    "TC09_blind_spot_now_fixed_by_v3",
    "공포탐욕은 SPX가 -2% 이하일 때 매수 조건이 충족되며 이후 수익률이 개선되는 경향을 보입니다.",
    already_cards=[3], ranking_card_ids=[],
    expect_consistent=False,  # v3: 이제는 제대로 잡혀야 함
    expect_issue_keywords=["조건 불일치 의심", "공포탐욕"],
    note=(
        "v2에서는 같은 절에 '수익률'이라는 제외 키워드가 있어서 조건 검사 자체가 스킵되고 "
        "틀린 %(-2% vs 실제 -3%)가 그냥 통과됐던 케이스(교수님 지적 ②). v3는 절 전체가 아니라 "
        "카드 이름 근처(앞5자~뒤25자)의 %만 보고, 그 %가 트리거 단어(이하/이상 등)와 붙어 "
        "있으면 무조건 검사하므로 이제 제대로 잡힘. 이 테스트가 PASS면 v3 수정이 유효하다는 뜻."
    ),
)

# ── TC10: PR에 기록된 기존 한계 — v3에서 오귀속(오탐)이 수정됐는지 확인 ──
tc(
    "TC10_misattribution_now_fixed_by_v3",
    "낙폭과대 사냥은 NDX -4% 이하 조건으로 이미 보유한 기술의 파도와 궁합이 좋습니다.",
    already_cards=[5], ranking_card_ids=[6],
    expect_consistent=True,  # v3: 오귀속이 고쳐져서 더 이상 오탐이 나면 안 됨
    note=(
        "v2(clause 단위)에서는 '기술의 파도'가 들어있는 절에 있는 '-4%'(사실은 낙폭과대 사냥 것)를 "
        "잘못 끌어와 기술의 파도의 실제 조건(+2%)과 비교해버려 [조건 불일치 의심]이라는 "
        "'가짜' 오류를 만들어냈다 (PR #66 알려진 한계보다 실제 위험 범위가 더 넓다는 것도 "
        "이 과정에서 확인됨: %가 카드마다 하나씩 없어도, 절에 하나만 있고 카드 이름이 "
        "2개 이상이면 이미 오귀속이 발생했음). v3는 카드 이름 근처(앞5자~뒤25자) 윈도우로 "
        "%를 스코핑하므로, '기술의 파도'와 멀리 떨어진 '-4%'는 애초에 후보에서 제외되고, "
        "'낙폭과대 사냥' 근처의 '-4%'만 그 카드 자신의 조건과 정확히 비교된다. "
        "이 테스트가 PASS면 v3의 오귀속 수정이 유효하다는 뜻."
    ),
)

# =============================================================
# TC11~TC30: 표현 다양성 / 경계값 / 다중 카드 / 알려진 미해결 사각지대 확장
# "손수 만든 테스트를 늘려도 되냐"는 질문에 대한 답으로 추가.
# 여기서부터는 두 종류로 나뉜다.
#   (A) 기존 규칙이 '다른 상황'에서도 여전히 정확한지 재확인하는 케이스
#   (B) [GAP] 표시가 붙은, 아직 못 고친 진짜 사각지대를 "문서화"하는 케이스
#       → expect_consistent=True로 돼 있어도 "검증기가 옳다"는 뜻이 아니라
#         "지금 코드가 실제로 이렇게 놓친다"는 걸 기록해두는 것.
# =============================================================

# ── TC11 [GAP]: '이하/이상/급락/상승/반등'이 아닌 다른 표현("빠지면")은 아예 검사 안 됨 ──
tc(
    "TC11_GAP_paraphrase_not_recognized_1",
    "공포탐욕은 SPX가 -2%나 빠지면 매수하는 카드입니다.",
    already_cards=[3], ranking_card_ids=[],
    expect_consistent=True,  # ⚠ 실제로는 -2%가 틀림(정답 -3%)이지만 트리거 단어가 없어 검사 자체가 안 됨
    note="[GAP] '빠지면'은 트리거 단어 목록(이하/이상/급락/상승/반등)에 없어서 %가 틀려도 못 잡음.",
)

# ── TC12 [GAP]: '초과하면' 표현도 마찬가지로 인식 안 됨 ──
tc(
    "TC12_GAP_paraphrase_not_recognized_2",
    "기술의 파도는 NDX가 +5%를 초과하면 매수합니다.",
    already_cards=[5], ranking_card_ids=[],
    expect_consistent=True,  # 실제 정답은 +2%인데 틀린 +5%가 그냥 통과됨
    note="[GAP] '초과하면'도 트리거 단어에 없어서 실제 조건(+2%)과 다른 +5%를 못 잡음.",
)

# ── TC13 [GAP]: '밑돌면' 표현도 인식 안 됨 ──
tc(
    "TC13_GAP_paraphrase_not_recognized_3",
    "금 피난처는 SPX가 -2%를 밑돌면 매수하는 카드입니다.",
    already_cards=[4], ranking_card_ids=[],
    expect_consistent=True,  # 실제 정답은 -5%인데 틀린 -2%가 그냥 통과됨
    note="[GAP] '밑돌면'도 트리거 단어에 없어서 실제 조건(-5%)과 다른 -2%를 못 잡음.",
)

# ── TC14 [GAP]: '웃돌면' 표현도 인식 안 됨 (매도 카드) ──
tc(
    "TC14_GAP_paraphrase_not_recognized_4",
    "역발상 투자는 SPX가 +10%를 웃돌면 매도합니다.",
    already_cards=[8], ranking_card_ids=[],
    expect_consistent=True,  # 실제 정답은 +3%인데 틀린 +10%가 그냥 통과됨
    note="[GAP] '웃돌면'도 트리거 단어에 없어서 실제 조건(+3%)과 다른 +10%를 못 잡음.",
)

# ── TC15: 반올림 오차 허용 범위(0.5 미만) 경계 — 통과해야 함 ──
tc(
    "TC15_tolerance_boundary_pass",
    "공포탐욕은 SPX가 -3.4% 이하일 때 매수합니다.",
    already_cards=[3], ranking_card_ids=[],
    expect_consistent=True,
    note="실제 -3%와 차이 0.4 (<0.5) → 반올림 오차로 허용돼서 통과해야 함",
)

# ── TC16: 반올림 오차 허용 범위(0.5 미만) 경계 밖 — 잡혀야 함 ──
tc(
    "TC16_tolerance_boundary_fail",
    "공포탐욕은 SPX가 -3.6% 이하일 때 매수합니다.",
    already_cards=[3], ranking_card_ids=[],
    expect_consistent=False,
    expect_issue_keywords=["조건 불일치 의심", "공포탐욕"],
    note="실제 -3%와 차이 0.6 (>=0.5) → 오차 허용 범위 밖이라 잡혀야 함",
)

# ── TC17: %가 아예 없는 카드 언급 — 검사할 게 없으니 통과 ──
tc(
    "TC17_no_percentage_mentioned",
    "거인의 어깨는 게임 시작과 동시에 SPX를 매수하는 카드입니다.",
    already_cards=[1], ranking_card_ids=[],
    expect_consistent=True,
    note="%가 아예 없어서 조건 대조 자체가 발생하지 않음 → 통과해야 함",
)

# ── TC18: 같은 카드가 두 문장에서 각각 다르게 서술 (하나는 맞고 하나는 틀림) ──
tc(
    "TC18_same_card_twice_one_wrong",
    "공포탐욕은 -3% 이하에서 매수합니다. 공포탐욕은 -1% 이하에서도 발동한 적 있습니다.",
    already_cards=[3], ranking_card_ids=[],
    expect_consistent=False,
    expect_issue_keywords=["조건 불일치 의심", "공포탐욕"],
    note="두 번째 문장의 -1%가 틀림(정답 -3%) → 문장 단위로 각각 검사되어 잡혀야 함",
)

# ── TC19: 매도 카드(역발상 투자) 조건 정확 ──
tc(
    "TC19_sell_card_correct",
    "역발상 투자는 SPX가 +3% 이상일 때 보유 물량을 매도하는 카드입니다.",
    already_cards=[8], ranking_card_ids=[],
    expect_consistent=True,
    note="SELL_ON_CONDITION 카드도 BUY 카드와 동일한 로직으로 정확히 검사되는지 확인",
)

# ── TC20: 매도 카드(역발상 투자) 조건 오류 ──
tc(
    "TC20_sell_card_wrong",
    "역발상 투자는 SPX가 +7% 이상일 때 보유 물량을 매도하는 카드입니다.",
    already_cards=[8], ranking_card_ids=[],
    expect_consistent=False,
    expect_issue_keywords=["조건 불일치 의심", "역발상 투자"],
    note="실제 조건 +3%인데 +7%로 틀림 → 매도 카드에서도 잡혀야 함",
)

# ── TC21: PERIODIC 카드(분할매수 장인)를 조건부처럼 서술 — 잡혀야 함 ──
tc(
    "TC21_periodic_described_as_condition",
    "분할매수 장인은 NDX가 -4% 이하일 때 매수하는 카드입니다.",
    already_cards=[11], ranking_card_ids=[],
    expect_consistent=False,
    expect_issue_keywords=["조건부로 오기재 의심", "분할매수 장인"],
    note="PERIODIC(5라운드마다 정기매수) 카드인데 조건부(-4% 이하일 때)처럼 서술됨 → 잡혀야 함",
)

# ── TC22: PERIODIC 카드를 정확히 서술 ──
tc(
    "TC22_periodic_described_correctly",
    "분할매수 장인은 조건 없이 5라운드마다 NDX를 매수하는 카드입니다.",
    already_cards=[11], ranking_card_ids=[],
    expect_consistent=True,
    note="정기 매수 카드를 정확히 서술 → 위반 없어야 함",
)

# ── TC23: 카드 3개, 문장을 나눠서 각각 서술 — 전부 정답 ──
tc(
    "TC23_three_cards_separate_sentences_all_correct",
    "공포탐욕은 -3% 이하일 때 매수합니다. 금 피난처는 -5% 이하일 때 매수합니다. "
    "낙폭과대 사냥은 -4% 이하일 때 매수합니다.",
    already_cards=[3, 4, 6], ranking_card_ids=[],
    expect_consistent=True,
    note="문장을 나눠서 서술하면 카드 이름 근처 윈도우가 서로 안 겹침 → 3개 다 정확히 검사돼야 함",
)

# ── TC24: 카드 2개, 문장을 나눠서 서술 — 하나만 오답 ──
tc(
    "TC24_two_cards_separate_sentences_one_wrong",
    "공포탐욕은 -3% 이하일 때 매수합니다. 금 피난처는 -2% 이하일 때 매수합니다.",
    already_cards=[3, 4], ranking_card_ids=[],
    expect_consistent=False,
    expect_issue_keywords=["조건 불일치 의심", "금 피난처"],
    note="금 피난처 조건이 -2%로 틀림(정답 -5%) → 공포탐욕은 정상, 금 피난처만 잡혀야 함",
)

# ── TC25 [GAP]: 최대 발동 횟수를 숫자로 잘못 서술해도 못 잡음 ('무제한' 아닐 때) ──
tc(
    "TC25_GAP_max_trigger_wrong_number_not_caught",
    "낙폭과대 사냥은 최대 5회까지만 발동합니다.",
    already_cards=[6], ranking_card_ids=[],
    expect_consistent=True,  # ⚠ 실제 정답은 최대 3회인데 5회라고 틀리게 써도 안 잡힘
    note=(
        "[GAP] 최대 횟수 검사 규칙(4번)은 '무제한'이라는 단어만 찾지, 숫자 자체가 "
        "맞는지는 대조하지 않음. 그래서 실제로는 최대 3회인데 '5회'라고 써도 통과됨."
    ),
)

# ── TC26: 여러 문장에 걸쳐 요청에 없는 카드를 언급 (환각) ──
tc(
    "TC26_hallucinated_card_among_valid_ones",
    "공포탐욕은 -3% 이하일 때 매수합니다. 그리고 거인의 어깨도 이번 판에 도움이 됐습니다.",
    already_cards=[3], ranking_card_ids=[],
    expect_consistent=False,
    expect_issue_keywords=["미포함 카드 언급", "거인의 어깨"],
    note="요청에 없는 '거인의 어깨'(id=1)를 두 번째 문장에서 언급 → 잡혀야 함",
)

# ── TC27: 오차 허용 경계값 정확히 0.5 — 미만이 아니므로 잡혀야 함 ──
tc(
    "TC27_tolerance_exact_boundary_fail",
    "공포탐욕은 SPX가 -3.5% 이하일 때 매수합니다.",
    already_cards=[3], ranking_card_ids=[],
    expect_consistent=False,
    expect_issue_keywords=["조건 불일치 의심", "공포탐욕"],
    note="코드가 'abs(차이) < 0.5'로 엄격 부등호를 쓰므로, 차이가 정확히 0.5면 허용 안 됨 → 잡혀야 함",
)

# ── TC28: 애플 줍줍, 조건과 최대횟수 둘 다 정확 ──
tc(
    "TC28_apple_condition_and_max_both_correct",
    "애플 줍줍은 AAPL이 -5% 이하일 때 매수하며 최대 5회까지 발동합니다.",
    already_cards=[9], ranking_card_ids=[],
    expect_consistent=True,
    note="조건(-5%)과 최대 횟수(5회) 모두 실제와 일치 → 위반 없어야 함",
)

# ── TC29: 애플 줍줍, 조건만 오답 ──
tc(
    "TC29_apple_condition_wrong",
    "애플 줍줍은 AAPL이 -8% 이하일 때 매수하며 최대 5회까지 발동합니다.",
    already_cards=[9], ranking_card_ids=[],
    expect_consistent=False,
    expect_issue_keywords=["조건 불일치 의심", "애플 줍줍"],
    note="조건이 -8%로 틀림(정답 -5%) → 최대 횟수는 맞지만 조건 불일치로 잡혀야 함",
)

# ── TC30 [GAP]: 무조건부 카드를 '하락할 때만' 같은 표현으로 잘못 조건부화해도 못 잡음 ──
tc(
    "TC30_GAP_unconditional_miswritten_with_unrecognized_word",
    "채권 피난처는 TLT가 하락할 때만 매수하는 카드입니다.",
    already_cards=[10], ranking_card_ids=[],
    expect_consistent=True,  # ⚠ 실제로는 무조건부인데 조건부처럼 틀리게 썼지만 못 잡음
    note=(
        "[GAP] 무조건부/정기 카드를 조건부로 오기재했는지 보는 규칙(3번)은 "
        "'이하/이상/급락/상승 + 일/할 때' 패턴만 찾음. '하락할 때'는 '하락'이 "
        "그 목록에 없어서(급락만 있음) 안 잡힘 — 채권 피난처를 조건부인 것처럼 "
        "틀리게 설명해도 통과됨."
    ),
)


def run():
    total = len(TEST_CASES)
    passed = 0
    failed_names = []

    for case in TEST_CASES:
        result = verify_feedback(
            case["feedback_text"],
            case["already_cards"],
            case["ranking_card_ids"],
        )

        ok = result.consistent == case["expect_consistent"]

        if ok and case["expect_issue_keywords"] and not case["expect_consistent"]:
            # issues 중 최소 하나는 기대 키워드를 전부 포함해야 함
            ok = any(
                all(kw in issue for kw in case["expect_issue_keywords"])
                for issue in result.issues
            )

        status = "PASS" if ok else "FAIL"
        if ok:
            passed += 1
        else:
            failed_names.append(case["name"])

        print(f"[{status}] {case['name']}")
        print(f"    입력 feedback: {case['feedback_text']}")
        print(f"    기대 consistent={case['expect_consistent']}  실제 consistent={result.consistent}")
        if result.issues:
            for issue in result.issues:
                print(f"    - issue: {issue}")
        if case["note"]:
            print(f"    note: {case['note']}")
        print()

    gap_cases = [c for c in TEST_CASES if "_GAP_" in c["name"]]

    print("=" * 60)
    print(f"{passed}/{total} 케이스가 기대대로 동작함")
    if failed_names:
        print(f"기대와 다르게 동작한 케이스: {failed_names}")
    print("=" * 60)
    if passed == total:
        print(
            f"\n{total}/{total} 통과 = 지금 코드가 '내가 기대한 그대로' 동작한다는 뜻입니다.\n"
            f"단, 이 중 {len(gap_cases)}개는 이름에 [GAP]이 붙어있고 expect_consistent=True로 "
            f"되어 있는데, 이건 '검증기가 옳다'가 아니라 '지금 검증기가 이 유형의 오류는 "
            f"아직 못 잡는다'는 걸 의도적으로 고정해둔 것입니다:\n"
        )
        for c in gap_cases:
            print(f"  - {c['name']}: {c['note']}")
        print(
            "\n즉 30개 중 실제로 '이번에 검증기가 정확하다고 확인된' 케이스는 "
            f"{total - len(gap_cases)}개이고, {len(gap_cases)}개는 다음에 고쳐야 할 "
            "구체적인 할 일 목록으로 남겨둔 것입니다."
        )


if __name__ == "__main__":
    run()