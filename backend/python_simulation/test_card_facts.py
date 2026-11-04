"""
test_card_facts.py — 카드 규칙 단일 원천(CARD_FACTS)이 실제 게임 로직(game_logic.CARDS)과 같은지 확인 (10주차)

교수님 3주차 피드백: 카드 정보가 game_logic.py·CARD_LOGIC·CARD_FACTS 세 곳에 흩어져 있어 어긋날 위험이 있다.
10주차에 CARD_LOGIC을 없애고 CARD_FACTS 하나로 합쳤으므로, 남은 두 곳(게임 로직 ↔ CARD_FACTS)이
같은지를 이 테스트로 매번 확인한다. 서버·DB·API 키 없이 실행 가능.

실행: python3 test_card_facts.py
"""
import re

from game_logic import CARDS
from verify_feedback import CARD_FACTS

# game_logic 타입 → CARD_FACTS 타입
TYPE_MAP = {
    'BUY_ONCE': 'ONCE',
    'BUY_SPLIT': 'UNCONDITIONAL',
    'BUY_ON_CONDITION': 'CONDITION',
    'SELL_ON_CONDITION': 'CONDITION',
    'BUY_EVERY_N': 'PERIODIC',
}


def check(card_id):
    g, f = CARDS[card_id], CARD_FACTS[card_id]
    errs = []
    if g['name'] != f.name:
        errs.append(f'이름 {g["name"]} ≠ {f.name}')
    if g['ticker'] != f.ticker:
        errs.append(f'종목 {g["ticker"]} ≠ {f.ticker}')
    if TYPE_MAP[g['type']] != f.trigger_type:
        errs.append(f'종류 {g["type"]} ≠ {f.trigger_type}')
    if round(g['ratio'] * 100, 6) != f.buy_ratio_pct:
        errs.append(f'비율 {g["ratio"] * 100}% ≠ {f.buy_ratio_pct}%')
    # 조건 % (예: 'SPX_CHANGE <= -3' → -3)
    g_th = [float(x) for x in re.findall(r'(-?\d+(?:\.\d+)?)', g['condition'] or '')]
    if g_th != [float(x) for x in f.threshold_pcts]:
        errs.append(f'조건 {g_th} ≠ {f.threshold_pcts}')
    # 최대 횟수 (1회성 카드는 CARD_FACTS에서 1로 표기)
    expected_max = 1 if g['type'] == 'BUY_ONCE' else g['max_trigger']
    if expected_max != f.max_trigger:
        errs.append(f'최대 횟수 {expected_max} ≠ {f.max_trigger}')
    # 사람이 읽는 설명에 비율·조건 숫자가 그대로 들어 있는지
    if f'{f.buy_ratio_pct:g}%' not in f.condition_desc:
        errs.append(f'설명에 비율 {f.buy_ratio_pct:g}% 없음: {f.condition_desc}')
    for th in f.threshold_pcts:
        if f'{abs(th):g}%' not in f.condition_desc:
            errs.append(f'설명에 조건 {th:g}% 없음: {f.condition_desc}')
    if '1라운드' in f.condition_desc:
        errs.append(f'"1라운드" 표현 (카드는 고른 라운드에 적용됨): {f.condition_desc}')
    return errs


def main():
    fail = 0
    assert set(CARDS) == set(CARD_FACTS), f'카드 ID 불일치: {set(CARDS) ^ set(CARD_FACTS)}'
    for cid in sorted(CARDS):
        errs = check(cid)
        fail += bool(errs)
        print(f"[{'PASS' if not errs else 'FAIL'}] {cid:2d} {CARD_FACTS[cid].name}: {CARD_FACTS[cid].condition_desc}")
        for e in errs:
            print(f'      - {e}')
    print('=' * 60)
    print(f'결과: {len(CARDS) - fail}/{len(CARDS)} 일치')


if __name__ == '__main__':
    main()
