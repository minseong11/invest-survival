"""
backtest.py — 사후 분석용 백테스팅
같은 시작일에서 카드 4장(1/25/50/75라운드) 전체 순열을 실제 게임 로직(run_game)으로
돌려 최종 자산 기준 순위를 매기고, 플레이어 조합의 순위/백분위를 계산한다.
조합은 시작일에 사용 가능한 카드(상장된 종목)로만 만든다.
  - 11장 모두 사용 가능: 11×10×9×8 = 7,920개 (리먼·코로나)
  -  9장 사용 가능     :  9×8×7×6 = 3,024개 (닷컴 — 원유 베팅·채권 피난처 제외)

(11주차) 받은 후보 안 분석 — offered_cards를 주면 추가로 계산
  - 라운드별로 실제 제시된 후보 3장 안에서만 만든 조합 (최대 3×3×3×3 = 81개, 같은 카드 중복 조합 제외)
  - 그 안의 최선 조합과 내 순위
  - 라운드별 대안: "이 라운드만 다른 후보를 골랐다면" (나머지 라운드 선택은 그대로)
    ※ 실제 게임에서는 앞 라운드 선택에 따라 뒤 라운드 후보가 달라질 수 있지만,
      여기서는 플레이어가 실제로 받은 후보를 그대로 쓴 반사실 비교다.
"""
import time
from itertools import permutations, product

from game_logic import run_game, load_price_data, available_card_ids, CARDS, CARD_SELECT_ROUNDS


def _to_selection(combo) -> dict:
    """(1, 4, 5, 9) → {1: 1, 25: 4, 50: 5, 75: 9}"""
    return dict(zip(CARD_SELECT_ROUNDS, combo))


def _selection_to_json(selection: dict) -> dict:
    return {str(r): c for r, c in selection.items()}


def _rank_results(results: list):
    """
    results: [(combo, final_asset, final_return_rate)] — 최종 자산 내림차순으로 정렬해 둔다.
    반환: (ranks, groups, tied_count_by_asset)
      - ranks : 최종 자산이 같으면 같은 순위 (동률 다음 순위는 건너뜀: 1, 1, 1, 4 ...)
      - groups: [시작 인덱스, 묶인 조합 수] — 같은 자산은 정렬 후 연속으로 붙어 있음
    """
    results.sort(key=lambda x: -x[1])
    ranks, groups = [], []
    for i, (_, a, _) in enumerate(results):
        if i == 0 or a != results[i - 1][1]:
            ranks.append(i + 1)
            groups.append([i, 1])
        else:
            ranks.append(ranks[i - 1])
            groups[-1][1] += 1
    tied_count_by_asset = {results[start][1]: count for start, count in groups}
    return ranks, groups, tied_count_by_asset


def _offered_analysis(start_date: str, player: dict, offered_cards: dict,
                      card_pool: list, price_data) -> dict:
    """
    받은 후보 안 분석. 후보 정보가 잘못됐으면 ValueError (호출부에서 None 처리).
    :param player: {라운드(int): 카드ID}
    :param offered_cards: {라운드: [후보 카드ID, ...]} — 키는 int/str 모두 허용
    """
    offered = {int(r): [int(c) for c in cards] for r, cards in offered_cards.items()}

    pools = {}
    for r in CARD_SELECT_ROUNDS:
        cards = offered.get(r)
        if not cards:
            raise ValueError(f'{r}라운드 후보가 없습니다')
        # 중복 제거(순서 유지) + 시작일에 사용 가능한 카드만
        pool = [c for c in dict.fromkeys(cards) if c in card_pool and c in CARDS]
        if player[r] not in pool:
            raise ValueError(f'{r}라운드 선택 카드 {player[r]}가 제시 후보 {cards}에 없습니다')
        pools[r] = pool

    results = []          # (combo, final_asset, final_return_rate)
    by_combo = {}         # combo → (final_asset, final_return_rate)
    for combo in product(*(pools[r] for r in CARD_SELECT_ROUNDS)):
        if len(set(combo)) != 4:   # 같은 카드를 두 번 고르는 조합은 게임에서 불가능
            continue
        g = run_game(start_date, _to_selection(combo), price_data=price_data)
        results.append((combo, g['final_asset'], g['final_return_rate']))
        by_combo[combo] = (g['final_asset'], g['final_return_rate'])

    total = len(results)
    ranks, groups, tied_count_by_asset = _rank_results(results)

    player_combo = tuple(player[r] for r in CARD_SELECT_ROUNDS)
    player_idx = next(i for i, (c, _, _) in enumerate(results) if c == player_combo)
    player_asset, player_rate = results[player_idx][1], results[player_idx][2]
    player_rank = ranks[player_idx]

    # 최선 조합: 1위 그룹 대표. 내 조합이 1위 동점이면 내 조합을 대표로 보여준다
    best_start, best_count = groups[0]
    best_combo = player_combo if player_rank == 1 else results[best_start][0]
    best_asset, best_rate = by_combo[best_combo]

    # 라운드별 대안: 그 라운드만 다른 후보로 바꾼 조합 (위에서 이미 계산돼 있음)
    round_alternatives = []
    for idx, r in enumerate(CARD_SELECT_ROUNDS):
        alternatives = []
        for c in pools[r]:
            if c == player[r]:
                continue
            alt_combo = player_combo[:idx] + (c,) + player_combo[idx + 1:]
            if alt_combo not in by_combo:   # 다른 라운드에서 이미 고른 카드와 겹치면 불가능 → 제외
                continue
            alt_asset, alt_rate = by_combo[alt_combo]
            alternatives.append({
                'cardId': c,
                'finalAsset': alt_asset,
                'finalReturnRate': alt_rate,
                'diffReturnRate': round(alt_rate - player_rate, 2),   # +면 대안이 더 좋았음 (%p)
            })
        alternatives.sort(key=lambda a: -a['finalAsset'])
        round_alternatives.append({
            'round': r,
            'offeredCards': pools[r],
            'playerCardId': player[r],
            'alternatives': alternatives,
        })

    return {
        'totalCombinations': total,
        'bestCombo': {
            'rank': 1,
            'tiedCount': best_count,
            'cardSelections': _selection_to_json(_to_selection(best_combo)),
            'finalAsset': best_asset,
            'finalReturnRate': best_rate,
        },
        'playerResult': {
            'cardSelections': _selection_to_json(player),
            'finalAsset': player_asset,
            'finalReturnRate': player_rate,
            'rank': player_rank,
            'tiedCount': tied_count_by_asset[player_asset],
            'topPercent': round(player_rank / total * 100, 1),
        },
        'roundAlternatives': round_alternatives,
    }


def run_backtest(start_date: str, player_selections: dict, top_n: int = 3,
                 offered_cards: dict = None) -> dict:
    """
    :param start_date: 게임 시작일 ("2008-09-02")
    :param player_selections: {라운드: 카드ID}. 키는 int/str 모두 허용
    :param top_n: 반환할 상위 조합 수
    :param offered_cards: (11주차) {라운드: [제시 후보 카드ID]}. 주면 offeredAnalysis 추가
    """
    player = {int(r): int(c) for r, c in player_selections.items()}
    if sorted(player.keys()) != CARD_SELECT_ROUNDS:
        raise ValueError(f'카드 선택 라운드는 {CARD_SELECT_ROUNDS} 4개여야 합니다: {sorted(player.keys())}')
    player_combo = tuple(player[r] for r in CARD_SELECT_ROUNDS)
    if len(set(player_combo)) != 4 or any(c not in CARDS for c in player_combo):
        raise ValueError(f'유효하지 않은 카드 조합입니다: {player_combo}')

    price_data = load_price_data(start_date)   # 한 번만 로드해서 모든 조합에 재사용
    card_pool = available_card_ids(price_data)  # 시작일에 사용 가능한 카드 (상장 전 종목 제외)
    if any(c not in card_pool for c in player_combo):
        raise ValueError(f'이 시작일에는 사용할 수 없는 카드가 포함되어 있습니다: {player_combo}')

    results = []   # (combo, final_asset, final_return_rate)
    for combo in permutations(card_pool, 4):
        r = run_game(start_date, _to_selection(combo), price_data=price_data)
        results.append((combo, r['final_asset'], r['final_return_rate']))

    total = len(results)
    ranks, groups, tied_count_by_asset = _rank_results(results)

    player_idx = next(i for i, (c, _, _) in enumerate(results) if c == player_combo)
    player_asset, player_rate = results[player_idx][1], results[player_idx][2]
    rank = ranks[player_idx]
    top_percent = round(rank / total * 100, 1)   # 상위 몇 % (작을수록 좋음)

    # (11주차) 받은 후보 안 분석 — 실패해도 기존 전체 조합 결과는 그대로 반환
    offered_analysis = None
    if offered_cards:
        try:
            offered_analysis = _offered_analysis(start_date, player, offered_cards, card_pool, price_data)
        except ValueError as e:
            print(f'⚠️  받은 후보 안 분석 생략: {e}')

    return {
        'totalCombinations': total,
        'cardPoolSize': len(card_pool),   # 사용 가능한 카드 수 (화면 문구 "N장 전체 조합 기준"용)
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
        'offeredAnalysis': offered_analysis,   # (11주차) 후보 정보가 없거나 잘못되면 None
    }


if __name__ == '__main__':
    # 실행 시간 측정: python3 backtest.py
    start_date = '2008-09-02'
    player = {1: 1, 25: 4, 50: 5, 75: 9}
    offered = {1: [1, 3, 10], 25: [4, 7, 8], 50: [5, 2, 11], 75: [9, 6, 3]}   # 예시 후보

    t0 = time.time()
    res = run_backtest(start_date, player, top_n=3, offered_cards=offered)
    elapsed = time.time() - t0

    print(f'전체 조합: {res["totalCombinations"]} (사용 가능 카드 {res["cardPoolSize"]}장)')
    print(f'실행 시간: {elapsed:.2f}초')
    print('상위 3개:')
    for t in res['topCombos']:
        print(f'  {t["rank"]}위 {t["cardSelections"]} → {t["finalAsset"]:,}원 ({t["finalReturnRate"]}%), 같은 결과 {t["tiedCount"]}개')
    p = res['playerResult']
    print(f'내 조합 {p["cardSelections"]} → {p["finalAsset"]:,}원 ({p["finalReturnRate"]}%), '
          f'{p["rank"]}위 / 상위 {p["topPercent"]}% / 같은 결과 {p["tiedCount"]}개')

    oa = res['offeredAnalysis']
    if oa:
        b, op = oa['bestCombo'], oa['playerResult']
        print(f'\n[받은 후보 안] 조합 {oa["totalCombinations"]}개')
        print(f'  최선 {b["cardSelections"]} → {b["finalAsset"]:,}원 ({b["finalReturnRate"]}%)')
        print(f'  내 순위 {op["rank"]}위 / {oa["totalCombinations"]}개')
        for ra in oa['roundAlternatives']:
            alts = ', '.join(f'{a["cardId"]}번 {a["diffReturnRate"]:+.2f}%p' for a in ra['alternatives'])
            print(f'  {ra["round"]}R 내 선택 {ra["playerCardId"]}번 / 대안: {alts or "(없음)"}')
