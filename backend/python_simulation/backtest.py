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

    # 순위: 최종 자산이 같으면 같은 순위 (동률 다음 순위는 건너뜀: 1, 1, 1, 4 ...)
    ranks = []
    for i, (_, a, _) in enumerate(results):
        ranks.append(i + 1 if i == 0 or a != results[i - 1][1] else ranks[i - 1])

    # 최종 자산이 같은 조합끼리 묶기 (정렬된 상태라 같은 자산은 연속으로 붙어 있음)
    # groups: [시작 인덱스, 묶인 조합 수] — 대표 조합은 그룹의 첫 번째 조합
    groups = []
    for i, (_, a, _) in enumerate(results):
        if i == 0 or a != results[i - 1][1]:
            groups.append([i, 1])
        else:
            groups[-1][1] += 1
    tied_count_by_asset = {results[start][1]: count for start, count in groups}

    player_idx = next(i for i, (c, _, _) in enumerate(results) if c == player_combo)
    player_asset, player_rate = results[player_idx][1], results[player_idx][2]
    rank = ranks[player_idx]
    top_percent = round(rank / total * 100, 1)   # 상위 몇 % (작을수록 좋음)

    return {
        'totalCombinations': total,
        # 상위 top_n개 "결과"(동점 그룹) — 같은 결과를 내는 조합은 대표 1개 + tiedCount로 묶음
        'topCombos': [
            {
                'rank': ranks[start],
                'tiedCount': count,
                'cardSelections': _selection_to_json(_to_selection(results[start][0])),
                'finalAsset': results[start][1],
                'finalReturnRate': results[start][2],
            }
            for start, count in groups[:top_n]
        ],
        'playerResult': {
            'cardSelections': _selection_to_json(player),
            'finalAsset': player_asset,
            'finalReturnRate': player_rate,
            'rank': rank,
            'tiedCount': tied_count_by_asset[player_asset],   # 내 조합 포함, 같은 결과를 내는 조합 수
            'topPercent': top_percent,
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
        print(f'  {t["rank"]}위 {t["cardSelections"]} → {t["finalAsset"]:,}원 ({t["finalReturnRate"]}%), 같은 결과 {t["tiedCount"]}개')
    p = res['playerResult']
    print(f'내 조합 {p["cardSelections"]} → {p["finalAsset"]:,}원 ({p["finalReturnRate"]}%), '
          f'{p["rank"]}위 / 상위 {p["topPercent"]}% / 같은 결과 {p["tiedCount"]}개')
