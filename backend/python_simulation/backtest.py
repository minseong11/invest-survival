"""
backtest.py — 사후 분석용 백테스팅
같은 시작일에서 카드 4장(1/25/50/75라운드) 전체 순열(11×10×9×8 = 7,920개)을 실제 게임 로직(run_game)으로
돌려 최종 자산 기준 순위를 매기고, 플레이어 조합의 순위/백분위를 계산한다.
"""
import time
from itertools import permutations

from game_logic import run_game, load_price_data, CARDS, CARD_SELECT_ROUNDS

ALL_CARD_IDS = sorted(CARDS.keys())


def _to_selection(combo) -> dict:
    """(1, 4, 5, 9) → {1: 1, 25: 4, 50: 5, 75: 9}"""
    return dict(zip(CARD_SELECT_ROUNDS, combo))


def _selection_to_json(selection: dict) -> dict:
    return {str(r): c for r, c in selection.items()}


def run_backtest(start_date: str, player_selections: dict, top_n: int = 3) -> dict:
    """
    :param start_date: 게임 시작일 ("2008-09-02")
    :param player_selections: {라운드: 카드ID}. 키는 int/str 모두 허용
    :param top_n: 반환할 상위 조합 수
    """
    player = {int(r): int(c) for r, c in player_selections.items()}
    if sorted(player.keys()) != CARD_SELECT_ROUNDS:
        raise ValueError(f'카드 선택 라운드는 {CARD_SELECT_ROUNDS} 4개여야 합니다: {sorted(player.keys())}')
    player_combo = tuple(player[r] for r in CARD_SELECT_ROUNDS)
    if len(set(player_combo)) != 4 or any(c not in CARDS for c in player_combo):
        raise ValueError(f'유효하지 않은 카드 조합입니다: {player_combo}')

    price_data = load_price_data(start_date)   # 한 번만 로드해서 7,920번 재사용

    results = []   # (combo, final_asset, final_return_rate)
    for combo in permutations(ALL_CARD_IDS, 4):
        r = run_game(start_date, _to_selection(combo), price_data=price_data)
        results.append((combo, r['final_asset'], r['final_return_rate']))

    total = len(results)
    results.sort(key=lambda x: -x[1])          # 최종 자산 내림차순

    player_asset = next(a for c, a, _ in results if c == player_combo)
    player_rate = next(rt for c, _, rt in results if c == player_combo)
    # 동점이면 같은 순위 (자신보다 최종 자산이 큰 조합 수 + 1)
    rank = 1 + sum(1 for _, a, _ in results if a > player_asset)
    percentile = round((1 - rank / total) * 100, 1)

    return {
        'totalCombinations': total,
        'topCombos': [
            {
                'rank': i + 1,
                'cardSelections': _selection_to_json(_to_selection(c)),
                'finalAsset': a,
                'finalReturnRate': rt,
            }
            for i, (c, a, rt) in enumerate(results[:top_n])
        ],
        'playerResult': {
            'cardSelections': _selection_to_json(player),
            'finalAsset': player_asset,
            'finalReturnRate': player_rate,
            'rank': rank,
            'percentile': percentile,
        },
    }


if __name__ == '__main__':
    # 실행 시간 측정: python3 backtest.py
    start_date = '2008-09-02'
    player = {1: 1, 25: 4, 50: 5, 75: 9}

    t0 = time.time()
    res = run_backtest(start_date, player, top_n=3)
    elapsed = time.time() - t0

    print(f'전체 조합: {res["totalCombinations"]}')
    print(f'실행 시간: {elapsed:.2f}초')
    print('상위 3개:')
    for t in res['topCombos']:
        print(f'  {t["rank"]}위 {t["cardSelections"]} → {t["finalAsset"]:,}원 ({t["finalReturnRate"]}%)')
    p = res['playerResult']
    print(f'내 조합 {p["cardSelections"]} → {p["finalAsset"]:,}원 ({p["finalReturnRate"]}%), '
          f'{p["rank"]}위 / 백분위 {p["percentile"]}')
