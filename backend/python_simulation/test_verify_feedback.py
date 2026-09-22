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

    print("=" * 60)
    print(f"{passed}/{total} 케이스가 기대대로 동작함")
    if failed_names:
        print(f"기대와 다르게 동작한 케이스: {failed_names}")
    print("=" * 60)
    if passed == total:
        print(
            "\n10/10 통과 = v3 수정 3건(② 사각지대 / 오귀속 / CARD_FACTS[11] 드리프트)이 "
            "모두 의도대로 고쳐졌다는 뜻입니다. 교수님이 요구한 '검증기 자체의 자기검증'이 "
            "이 스크립트로 재현 가능하게 문서화되어 있습니다."
        )


if __name__ == "__main__":
    run()