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

(#125) 추가
  - 위기 대응 선택(decisions): 모든 조합을 "플레이어와 같은 위기 대응"으로 계산한다
    → 내 결과가 전체 조합 안의 한 점이 되고, 순위는 카드 선택만의 차이를 뜻한다
  - 전체 조합 결과 캐시 + 미리 계산(prewarm): 같은 (시작일, 위기 대응)은 한 번만 계산
  - 등급(S~D), 최대 낙폭(내 자산 vs S&P500)
  - 카드별 성적표: 이 카드를 고르지 않았다면 결과가 얼마나 달랐는지 + 발동 횟수·매매 금액·건너뜀 사유
  - 위기 대응 돌아보기: 그때 다른 선택을 했다면
  - 그 후 이야기: 게임이 끝난 뒤 실제 시장과, 내 포트폴리오를 그대로 뒀을 때의 값
"""
import threading
import time
from collections import OrderedDict
from concurrent.futures import Future
from itertools import permutations, product

from game_logic import (
    run_game, load_price_data, available_card_ids, normalize_decisions,
    CARDS, CARD_SELECT_ROUNDS, DECISION_CHOICES, DECISION_HOLD, GAME_ROUNDS, TICKERS, INITIAL_ASSET,
)

# 그 후 이야기: 게임 종료 후 몇 거래일 뒤를 볼지 (약 6개월, 약 1년)
EPILOGUE_POINTS = [('6개월 뒤', 125), ('1년 뒤', 250)]

# 등급: 전체 조합 중 상위 몇 %까지인지 (이하)
GRADE_BOUNDS = [('S', 5.0), ('A', 20.0), ('B', 50.0), ('C', 80.0)]


def grade_of(top_percent: float) -> str:
    """전체 조합 순위(상위 %)를 등급으로. 상위 5% S / 20% A / 50% B / 80% C / 그 외 D"""
    for grade, bound in GRADE_BOUNDS:
        if top_percent <= bound:
            return grade
    return 'D'


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


# =============================================
# (#125) 캐시 — 가격 데이터, 전체 조합 결과
# =============================================
_lock = threading.Lock()
_price_cache = {}                 # 시작일 → load_price_data() 결과 (등락률·발동 라운드 사전 계산 포함)
_combo_cache = OrderedDict()      # (시작일, 위기 대응, 기준 종목) → Future(전체 조합 결과)
_COMBO_CACHE_MAX = 64


def get_price_data(start_date: str) -> dict:
    with _lock:
        pd_ = _price_cache.get(start_date)
    if pd_ is None:
        pd_ = load_price_data(start_date)
        with _lock:
            pd_ = _price_cache.setdefault(start_date, pd_)
    return pd_


def clear_cache():
    """캐시 비우기 (테스트에서 가격 데이터를 바꿨을 때)"""
    with _lock:
        _price_cache.clear()
        _combo_cache.clear()


def _decision_key(decisions: dict) -> tuple:
    return tuple(sorted(decisions.items()))


def _compute_all_combos(start_date: str, decisions: dict, base_ticker: str) -> dict:
    price_data = get_price_data(start_date)
    card_pool = available_card_ids(price_data)   # 시작일에 사용 가능한 카드 (상장 전 종목 제외)
    results = []   # (combo, final_asset, final_return_rate)
    for combo in permutations(card_pool, 4):
        r = run_game(start_date, _to_selection(combo), price_data=price_data,
                     decisions=decisions, base_ticker=base_ticker, collect_rounds=False)
        results.append((combo, r['final_asset'], r['final_return_rate']))
    ranks, groups, tied = _rank_results(results)
    return {
        'card_pool': card_pool,
        'results': results,
        'ranks': ranks,
        'groups': groups,
        'tied': tied,
        'index': {combo: i for i, (combo, _, _) in enumerate(results)},
    }


def all_combo_results(start_date: str, decisions: dict, base_ticker: str) -> dict:
    """
    전체 조합 결과 (캐시). 같은 키를 다른 요청이 계산 중이면 끝날 때까지 기다렸다가 같은 결과를 쓴다
    (게임 중 미리 계산을 시작해 두면 결과 화면 요청이 그 계산을 이어받는다).
    """
    key = (start_date, _decision_key(decisions), base_ticker)
    with _lock:
        fut = _combo_cache.get(key)
        owner = fut is None
        if owner:
            fut = Future()
            _combo_cache[key] = fut
            while len(_combo_cache) > _COMBO_CACHE_MAX:
                _combo_cache.popitem(last=False)
        else:
            _combo_cache.move_to_end(key)
    if owner:
        try:
            fut.set_result(_compute_all_combos(start_date, decisions, base_ticker))
        except BaseException as e:
            with _lock:
                _combo_cache.pop(key, None)
            fut.set_exception(e)
            raise
    return fut.result()


def is_cached(start_date: str, decisions: dict = None, base_ticker: str = '^SPX') -> bool:
    key = (start_date, _decision_key(normalize_decisions(decisions)), base_ticker)
    with _lock:
        fut = _combo_cache.get(key)
    return fut is not None and fut.done() and fut.exception() is None


def prewarm(start_date: str, decisions: dict = None, base_ticker: str = '^SPX') -> str:
    """
    전체 조합 결과를 미리 계산해 둔다 (게임 서버가 마지막 위기 대응이 정해진 뒤 호출).
    반환: 'ready'(이미 있음) / 'started'(백그라운드 계산 시작)
    """
    decisions = normalize_decisions(decisions)
    if is_cached(start_date, decisions, base_ticker):
        return 'ready'

    def work():
        try:
            all_combo_results(start_date, decisions, base_ticker)
        except Exception as e:      # 미리 계산 실패는 무시 (결과 화면 요청에서 다시 계산·오류 처리)
            print(f'⚠️  전체 조합 미리 계산 실패: {e}')

    threading.Thread(target=work, daemon=True).start()
    return 'started'


# =============================================
# 받은 후보 안 분석 (11주차)
# =============================================
def _offered_analysis(start_date: str, player: dict, offered_cards: dict,
                      card_pool: list, price_data, decisions: dict, base_ticker: str) -> dict:
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
        g = run_game(start_date, _to_selection(combo), price_data=price_data,
                     decisions=decisions, base_ticker=base_ticker, collect_rounds=False)
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


# =============================================
# (#125) 최대 낙폭 · 카드별 성적표 · 위기 대응 돌아보기 · 그 후 이야기
# =============================================
def _max_drawdown(values: list) -> tuple:
    """(최대 낙폭 %, 가장 깊었던 위치) — 고점 대비 가장 크게 떨어진 비율. 값은 0 이하"""
    peak = values[0]
    mdd, at = 0.0, 0
    for i, v in enumerate(values):
        if v > peak:
            peak = v
        dd = (v - peak) / peak * 100 if peak > 0 else 0.0
        if dd < mdd:
            mdd, at = dd, i
    return round(mdd, 2), at


def _risk(player_game: dict, price_data: dict, initial_asset: int) -> dict:
    dates = price_data['dates']
    assets = [initial_asset] + [r['roundAsset'] for r in player_game['rounds']]
    p_mdd, p_at = _max_drawdown(assets)
    spx = price_data['close']['^SPX'][:GAME_ROUNDS]
    m_mdd, m_at = _max_drawdown(spx)
    worst_round = max(p_at, 1)          # assets[0]은 시작 자산이라 라운드 번호는 위치 그대로
    return {
        'playerMdd': p_mdd,
        'playerMddRound': worst_round if p_mdd < 0 else None,
        'playerMddDate': dates[worst_round - 1] if p_mdd < 0 else None,
        'marketMdd': m_mdd,
        'marketMddRound': m_at + 1 if m_mdd < 0 else None,
        'marketMddDate': dates[m_at] if m_mdd < 0 else None,
        'marketReturnRate': round((spx[-1] - spx[0]) / spx[0] * 100, 2),
    }


def _card_report(start_date, player, player_game, price_data, decisions, base_ticker) -> list:
    """
    카드별 성적표 — "이 카드를 고르지 않았다면" 결과와 비교한 효과.
    effectReturnRate = 내 결과 − 그 카드만 뺀 결과 (%p). +면 이 카드가 결과를 끌어올렸다.
    카드를 빼면 그 카드가 쓰던 현금이 다른 카드로 흘러가므로, 카드 4장의 효과를 더해도 전체 수익률과 같지는 않다.
    """
    report = []
    stats = player_game['card_stats']
    for r in CARD_SELECT_ROUNDS:
        cid = player[r]
        without = {rr: c for rr, c in player.items() if rr != r}
        g = run_game(start_date, without, price_data=price_data,
                     decisions=decisions, base_ticker=base_ticker, collect_rounds=False)
        s = stats.get(cid, {'triggers': 0, 'amount': 0, 'skips': {}})
        card = CARDS[cid]
        report.append({
            'round': r,
            'cardId': cid,
            'cardName': card['name'],
            'cardType': card['type'],
            'triggerCount': s['triggers'],
            'tradeAmount': s['amount'],                 # 이 카드가 산(매도 카드는 판) 금액 합계 (원)
            'skips': dict(s['skips']),                  # {사유: 횟수} — CASH_LOW / MAX_REACHED / NO_HOLDINGS / NO_PRICE
            'withoutFinalAsset': g['final_asset'],
            'withoutFinalReturnRate': g['final_return_rate'],
            'effectAsset': player_game['final_asset'] - g['final_asset'],
            'effectReturnRate': round(player_game['final_return_rate'] - g['final_return_rate'], 2),
        })
    return report


def _decision_review(start_date, player, player_game, price_data, decisions, base_ticker) -> dict:
    """
    위기 대응 돌아보기 — 각 대응 라운드에서 다른 선택을 했다면 (나머지 선택은 그대로).
    diffReturnRate = 다른 선택의 결과 − 내 결과 (%p, +면 다른 선택이 더 좋았음)
    """
    if not decisions:
        return None
    dates = price_data['dates']
    player_rate = player_game['final_return_rate']
    traded = {d['round']: d['amount'] for d in player_game['decision_log']}

    rounds = []
    for r in sorted(decisions):
        alternatives = []
        for choice in DECISION_CHOICES:
            if choice == decisions[r]:
                continue
            alt = dict(decisions)
            alt[r] = choice
            g = run_game(start_date, player, price_data=price_data,
                         decisions=alt, base_ticker=base_ticker, collect_rounds=False)
            alternatives.append({
                'choice': choice,
                'finalAsset': g['final_asset'],
                'finalReturnRate': g['final_return_rate'],
                'diffReturnRate': round(g['final_return_rate'] - player_rate, 2),
            })
        alternatives.sort(key=lambda a: -a['finalAsset'])
        rounds.append({
            'round': r,
            'date': dates[r - 1],
            'choice': decisions[r],
            'tradeAmount': traded.get(r, 0),            # 그때 팔거나 산 금액 (원). 버틴다는 0
            'alternatives': alternatives,
        })

    all_hold = {r: DECISION_HOLD for r in decisions}
    g = run_game(start_date, player, price_data=price_data,
                 decisions=all_hold, base_ticker=base_ticker, collect_rounds=False)
    return {
        'rounds': rounds,
        'allHoldFinalAsset': g['final_asset'],
        'allHoldFinalReturnRate': g['final_return_rate'],
        # 위기 대응 전체의 효과 = 내 결과 − 전부 버텼을 때 결과 (%p)
        'effectReturnRate': round(player_rate - g['final_return_rate'], 2),
    }


def _portfolio_value(game: dict, price_data: dict, index: int) -> int:
    """게임이 끝난 뒤 추가 매매 없이 그대로 뒀을 때, index 위치(0부터) 날짜의 평가액"""
    v = 0.0
    for t in TICKERS:
        s = price_data['close'][t]
        p = s[index] if index < len(s) else None
        if p is not None:
            v += game['final_shares'][t] * p
    return game['final_cash'] + int(v)


def _epilogue(player_game, best_game, price_data, initial_asset) -> dict:
    """
    그 후 이야기 — 게임(100라운드)이 끝난 뒤 실제 시장이 어떻게 움직였는지.
    포트폴리오는 게임 종료 시점의 보유 자산을 추가 매매 없이 그대로 들고 있었다고 가정한다.
    데이터가 그 시점까지 없으면 해당 항목은 빠진다 (하나도 없으면 None).
    """
    dates = price_data['dates']
    spx = price_data['close']['^SPX']
    end = GAME_ROUNDS - 1
    points = []
    for label, days in EPILOGUE_POINTS:
        idx = end + days
        if idx >= len(spx):
            continue
        p_asset = _portfolio_value(player_game, price_data, idx)
        b_asset = _portfolio_value(best_game, price_data, idx) if best_game else None
        points.append({
            'label': label,
            'tradingDays': days,
            'date': dates[idx],
            'spxChangeRate': round((spx[idx] - spx[end]) / spx[end] * 100, 2),     # 게임 종료일 대비 S&P500
            'playerAsset': p_asset,
            'playerReturnRate': round((p_asset - initial_asset) / initial_asset * 100, 2),   # 원금 대비
            'bestAsset': b_asset,
            'bestReturnRate': (round((b_asset - initial_asset) / initial_asset * 100, 2)
                               if b_asset is not None else None),
        })
    if not points:
        return None
    return {'endDate': dates[end], 'points': points}


def run_backtest(start_date: str, player_selections: dict, top_n: int = 3,
                 offered_cards: dict = None, decisions: dict = None,
                 base_ticker: str = '^SPX') -> dict:
    """
    :param start_date: 게임 시작일 ("2008-09-02")
    :param player_selections: {라운드: 카드ID}. 키는 int/str 모두 허용
    :param top_n: 반환할 상위 조합 수
    :param offered_cards: (11주차) {라운드: [제시 후보 카드ID]}. 주면 offeredAnalysis 추가
    :param decisions: (#125) 위기 대응 선택 {라운드: 'HOLD'|'SELL_HALF'|'BUY_MORE'}. 모든 조합에 똑같이 적용
    :param base_ticker: (#125) '더 산다'에서 사는 종목 ('^SPX' 또는 '^NDX')
    """
    player = {int(r): int(c) for r, c in player_selections.items()}
    if sorted(player.keys()) != CARD_SELECT_ROUNDS:
        raise ValueError(f'카드 선택 라운드는 {CARD_SELECT_ROUNDS} 4개여야 합니다: {sorted(player.keys())}')
    player_combo = tuple(player[r] for r in CARD_SELECT_ROUNDS)
    if len(set(player_combo)) != 4 or any(c not in CARDS for c in player_combo):
        raise ValueError(f'유효하지 않은 카드 조합입니다: {player_combo}')
    decisions = normalize_decisions(decisions)
    if base_ticker not in TICKERS:
        raise ValueError(f'알 수 없는 기준 종목입니다: {base_ticker}')

    price_data = get_price_data(start_date)     # 한 번만 로드해서 모든 조합에 재사용
    card_pool = available_card_ids(price_data)  # 시작일에 사용 가능한 카드 (상장 전 종목 제외)
    if any(c not in card_pool for c in player_combo):
        raise ValueError(f'이 시작일에는 사용할 수 없는 카드가 포함되어 있습니다: {player_combo}')

    # 전체 조합 (같은 위기 대응 적용) — 캐시
    allc = all_combo_results(start_date, decisions, base_ticker)
    results, ranks, groups = allc['results'], allc['ranks'], allc['groups']
    total = len(results)

    player_idx = allc['index'][player_combo]
    player_asset, player_rate = results[player_idx][1], results[player_idx][2]
    rank = ranks[player_idx]
    top_percent = round(rank / total * 100, 1)   # 상위 몇 % (작을수록 좋음)

    # 내 게임 상세 (라운드별 자산, 카드 통계, 최종 보유 자산)
    player_game = run_game(start_date, player, price_data=price_data,
                           decisions=decisions, base_ticker=base_ticker)

    # (11주차) 받은 후보 안 분석 — 실패해도 기존 전체 조합 결과는 그대로 반환
    offered_analysis = None
    if offered_cards:
        try:
            offered_analysis = _offered_analysis(start_date, player, offered_cards, card_pool,
                                                 price_data, decisions, base_ticker)
        except ValueError as e:
            print(f'⚠️  받은 후보 안 분석 생략: {e}')

    # (#125) 그 후 이야기에 쓸 1위 조합의 최종 보유 자산
    best_combo = results[groups[0][0]][0]
    best_game = run_game(start_date, _to_selection(best_combo), price_data=price_data,
                         decisions=decisions, base_ticker=base_ticker, collect_rounds=False)

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
            'tiedCount': allc['tied'][player_asset],   # 내 조합 포함, 같은 결과를 내는 조합 수
            'topPercent': top_percent,
        },
        'offeredAnalysis': offered_analysis,   # (11주차) 후보 정보가 없거나 잘못되면 None
        # (#125)
        'grade': grade_of(top_percent),
        'risk': _risk(player_game, price_data, player_game['initial_asset']),
        'cardReport': _card_report(start_date, player, player_game, price_data, decisions, base_ticker),
        'decisionReview': _decision_review(start_date, player, player_game, price_data, decisions, base_ticker),
        'epilogue': _epilogue(player_game, best_game, price_data, player_game['initial_asset']),
    }


if __name__ == '__main__':
    # 실행 시간 측정: python3 backtest.py
    start_date = '2008-09-02'
    player = {1: 1, 25: 4, 50: 5, 75: 9}
    offered = {1: [1, 3, 10], 25: [4, 7, 8], 50: [5, 2, 11], 75: [9, 6, 3]}   # 예시 후보
    decisions = {10: 'SELL_HALF', 20: 'HOLD', 60: 'BUY_MORE'}                  # 예시 위기 대응

    t0 = time.time()
    res = run_backtest(start_date, player, top_n=3, offered_cards=offered, decisions=decisions)
    elapsed = time.time() - t0
    t0 = time.time()
    run_backtest(start_date, player, top_n=3, offered_cards=offered, decisions=decisions)
    elapsed_cached = time.time() - t0

    print(f'전체 조합: {res["totalCombinations"]} (사용 가능 카드 {res["cardPoolSize"]}장)')
    print(f'실행 시간: {elapsed:.2f}초 (같은 요청 두 번째: {elapsed_cached:.2f}초)')
    print('상위 3개:')
    for t in res['topCombos']:
        print(f'  {t["rank"]}위 {t["cardSelections"]} → {t["finalAsset"]:,}원 ({t["finalReturnRate"]}%), 같은 결과 {t["tiedCount"]}개')
    p = res['playerResult']
    print(f'내 조합 {p["cardSelections"]} → {p["finalAsset"]:,}원 ({p["finalReturnRate"]}%), '
          f'{p["rank"]}위 / 상위 {p["topPercent"]}% / 등급 {res["grade"]} / 같은 결과 {p["tiedCount"]}개')
    k = res['risk']
    print(f'최대 낙폭: 나 {k["playerMdd"]}% ({k["playerMddDate"]}) / S&P500 {k["marketMdd"]}% ({k["marketMddDate"]})')

    print('\n[카드별 성적표] (이 카드를 고르지 않았다면 대비)')
    for c in res['cardReport']:
        print(f'  {c["round"]}R {c["cardName"]}: 발동 {c["triggerCount"]}회, {c["tradeAmount"]:,}원, '
              f'효과 {c["effectReturnRate"]:+.2f}%p, 건너뜀 {c["skips"]}')

    dr = res['decisionReview']
    if dr:
        print(f'\n[위기 대응] 전체 효과 {dr["effectReturnRate"]:+.2f}%p (전부 버텼다면 {dr["allHoldFinalReturnRate"]}%)')
        for d in dr['rounds']:
            alts = ', '.join(f'{a["choice"]} {a["diffReturnRate"]:+.2f}%p' for a in d['alternatives'])
            print(f'  {d["round"]}R {d["date"]} {d["choice"]} ({d["tradeAmount"]:,}원) / 다른 선택: {alts}')

    ep = res['epilogue']
    if ep:
        print(f'\n[그 후 이야기] 게임 종료 {ep["endDate"]}')
        for pt in ep['points']:
            print(f'  {pt["label"]}({pt["date"]}): S&P500 {pt["spxChangeRate"]:+.2f}%, '
                  f'내 포트폴리오 {pt["playerReturnRate"]:+.2f}%, 1위 조합 {pt["bestReturnRate"]:+.2f}%')

    oa = res['offeredAnalysis']
    if oa:
        b, op = oa['bestCombo'], oa['playerResult']
        print(f'\n[받은 후보 안] 조합 {oa["totalCombinations"]}개')
        print(f'  최선 {b["cardSelections"]} → {b["finalAsset"]:,}원 ({b["finalReturnRate"]}%)')
        print(f'  내 순위 {op["rank"]}위 / {oa["totalCombinations"]}개')
        for ra in oa['roundAlternatives']:
            alts = ', '.join(f'{a["cardId"]}번 {a["diffReturnRate"]:+.2f}%p' for a in ra['alternatives'])
            print(f'  {ra["round"]}R 내 선택 {ra["playerCardId"]}번 / 대안: {alts or "(없음)"}')
