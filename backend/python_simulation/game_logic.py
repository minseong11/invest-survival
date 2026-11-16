"""
Java GameService 게임 계산을 Python으로 옮긴 엔진
카드 정의, 조건 체크, 라운드 계산 로직 포함

(#125) 바뀐 점
  1) Java와 같은 연산 순서·버림으로 계산한다 → 최종 자산이 원 단위까지 같다
     - 현금은 정수(원). 매수·매도 금액은 Java의 (long) 캐스트처럼 소수점 아래를 버리고 반영
     - 총자산 = 현금 + (보유 자산 평가액의 소수점 아래 버림)
     - 등락률·수익률 반올림은 Java Math.round와 같은 규칙(.5는 위로)
     - 보유 자산 평가액은 종목 순서대로 하나씩 더한다 (Python 3.12+의 sum()은 보정 합산이라 Java와 끝자리가 달라질 수 있음)
  2) 위기 대응 선택(decisions): 뉴스 속보 라운드에서 버틴다/절반 판다/더 산다
  3) 카드가 조건은 맞았지만 실행되지 못한 이유(skippedCards)와 카드별 통계(card_stats)
  4) collect_rounds=False: 매매가 일어날 수 있는 라운드만 계산 (전체 조합 계산용, 결과는 같다)
"""
import math

import pandas as pd

from data_loader import get_price_list, load_all

INITIAL_ASSET = 10_000_000
GAME_ROUNDS = 100

CARDS = {
    1:  {'id': 1,  'name': '거인의 어깨',   'ticker': '^SPX', 'ratio': 0.30, 'type': 'BUY_ONCE',          'condition': None,               'max_trigger': None, 'priority': 1},
    2:  {'id': 2,  'name': '황금 적립',     'ticker': 'GLD',  'ratio': 0.05, 'type': 'BUY_SPLIT',         'condition': None,               'max_trigger': None, 'priority': 2},
    3:  {'id': 3,  'name': '공포탐욕',      'ticker': '^SPX', 'ratio': 0.20, 'type': 'BUY_ON_CONDITION',  'condition': 'SPX_CHANGE <= -3', 'max_trigger': None, 'priority': 3},
    4:  {'id': 4,  'name': '금 피난처',     'ticker': 'GLD',  'ratio': 0.15, 'type': 'BUY_ON_CONDITION',  'condition': 'SPX_CHANGE <= -5', 'max_trigger': None, 'priority': 4},
    5:  {'id': 5,  'name': '기술의 파도',   'ticker': '^NDX', 'ratio': 0.10, 'type': 'BUY_ON_CONDITION',  'condition': 'NDX_CHANGE >= 2',  'max_trigger': None, 'priority': 5},
    6:  {'id': 6,  'name': '낙폭과대 사냥', 'ticker': '^NDX', 'ratio': 0.25, 'type': 'BUY_ON_CONDITION',  'condition': 'NDX_CHANGE <= -4', 'max_trigger': 3,    'priority': 6},
    7:  {'id': 7,  'name': '원유 베팅',     'ticker': 'USO',  'ratio': 0.20, 'type': 'BUY_ONCE',          'condition': None,               'max_trigger': None, 'priority': 7},
    8:  {'id': 8,  'name': '역발상 투자',   'ticker': '^SPX', 'ratio': 0.15, 'type': 'SELL_ON_CONDITION', 'condition': 'SPX_CHANGE >= 3',  'max_trigger': None, 'priority': 1},
    9:  {'id': 9,  'name': '애플 줍줍',     'ticker': 'AAPL', 'ratio': 0.10, 'type': 'BUY_ON_CONDITION',  'condition': 'AAPL_CHANGE <= -5','max_trigger': 5,    'priority': 9},
    10: {'id': 10, 'name': '채권 피난처',   'ticker': 'TLT',  'ratio': 0.03, 'type': 'BUY_SPLIT',         'condition': None,               'max_trigger': None, 'priority': 10},
    11: {'id': 11, 'name': '분할매수 장인', 'ticker': '^NDX', 'ratio': 0.10, 'type': 'BUY_EVERY_N',       'condition': None,               'max_trigger': None, 'priority': 11},
}

TICKERS = ['^SPX', '^NDX', 'GLD', 'USO', 'AAPL', 'TLT']
CARD_SELECT_ROUNDS = [1, 25, 50, 75]

# =============================================
# (#125) 위기 대응 선택 — Java GameService.applyDecision()과 같은 규칙
#   HOLD      : 아무것도 하지 않음
#   SELL_HALF : 보유 종목을 각각 절반씩 그날 종가에 매도
#   BUY_MORE  : 현금의 30%로 시나리오 기준 지수(S&P500 또는 나스닥100)를 그날 종가에 매수
# =============================================
DECISION_HOLD = 'HOLD'
DECISION_SELL_HALF = 'SELL_HALF'
DECISION_BUY_MORE = 'BUY_MORE'
DECISION_CHOICES = (DECISION_HOLD, DECISION_SELL_HALF, DECISION_BUY_MORE)
SELL_HALF_RATIO = 0.5
BUY_MORE_RATIO = 0.3

# (#125) 카드가 발동 조건은 맞았지만 실행되지 못한 이유
SKIP_CASH_LOW = 'CASH_LOW'          # 현금이 총자산의 5% 미만
SKIP_MAX_REACHED = 'MAX_REACHED'    # 최대 발동 횟수를 다 씀
SKIP_NO_HOLDINGS = 'NO_HOLDINGS'    # 매도 카드인데 팔 주식이 없음
SKIP_NO_PRICE = 'NO_PRICE'          # 그날 가격이 없음


def _java_round(x: float) -> int:
    """Java Math.round(double)과 같은 반올림: 가장 가까운 정수, 정확히 .5면 큰 쪽으로"""
    f = math.floor(x)
    return f + 1 if x - f >= 0.5 else f


def _round2(x: float) -> float:
    """Java의 Math.round(x * 100.0) / 100.0"""
    return _java_round(x * 100.0) / 100.0


def _calc_change_rate(prev_close, curr_close):
    """
    전일 대비 등락률(%). 가격이 없으면(None) 등락률도 None — 결측을 0%로 취급하지 않는다.
    """
    if prev_close is None or curr_close is None or prev_close <= 0:
        return None
    rate = (curr_close - prev_close) / prev_close * 100
    return _round2(rate)


def _check_condition(condition, spx_change, ndx_change, aapl_change) -> bool:
    """조건에 쓰이는 등락률이 None(가격 없음)이면 발동하지 않는다."""
    if condition is None:
        return False
    if condition.startswith('SPX_'):
        change = spx_change
    elif condition.startswith('NDX_'):
        change = ndx_change
    elif condition.startswith('AAPL_'):
        change = aapl_change
    else:
        return False
    if change is None:
        return False
    if condition == 'SPX_CHANGE <= -3':    return change <= -3
    elif condition == 'SPX_CHANGE <= -5':  return change <= -5
    elif condition == 'SPX_CHANGE >= 3':   return change >= 3
    elif condition == 'NDX_CHANGE >= 2':   return change >= 2
    elif condition == 'NDX_CHANGE <= -4':  return change <= -4
    elif condition == 'AAPL_CHANGE <= -5': return change <= -5
    return False


def load_price_data(start_date: str) -> dict:
    """
    start_date 이후 전 종목 종가를 SPX 거래일 기준으로 맞춰 일반 리스트로 준비한다.
    (백테스팅처럼 run_game을 반복 호출할 때 한 번만 호출)

    정렬 규칙 — i번째 라운드 = SPX의 i번째 거래일
      - 각 종목은 그 날짜의 종가를 사용
      - 그날 거래가 없으면(휴장일 차이) 직전 거래일 종가 사용
      - 그 날짜 이전에 데이터가 전혀 없으면(상장 전) None (가격 없음 — 0과 구분)
    반환: {'dates': ['2008-09-02', ...], 'close': {ticker: [float 또는 None, ...]}}  (모든 종목 길이 = SPX 길이)
    """
    spx = get_price_list(start_date, '^SPX')
    if spx.empty:
        return {'dates': [], 'close': {t: [] for t in TICKERS}}
    spx_dates = pd.DatetimeIndex(spx['Date'])

    all_data = load_all()
    close = {}
    for ticker in TICKERS:
        if ticker == '^SPX':
            close[ticker] = spx['Close'].astype(float).tolist()
            continue
        df = all_data.get(ticker, pd.DataFrame())
        if df.empty:
            close[ticker] = [None] * len(spx_dates)
            continue
        # 전체 기간 데이터에서 SPX 날짜마다 "그 날짜 또는 직전 거래일" 종가를 가져옴 (start_date 이전 값도 사용)
        series = df.set_index('Date')['Close'].astype(float)
        series = series[~series.index.duplicated(keep='last')].sort_index()
        aligned = series.reindex(spx_dates, method='ffill')
        close[ticker] = [None if pd.isna(v) else float(v) for v in aligned]

    dates = spx['Date'].dt.strftime('%Y-%m-%d').tolist()
    return {'dates': dates, 'close': close}


def available_card_ids(price_data: dict) -> list:
    """
    시작일(1라운드)에 종목 가격이 있는 카드만 사용 가능.
    상장 전 종목의 카드는 해당 시나리오에서 제시하지 않는다 (게임·사후 분석 공통 규칙).
    """
    closes = price_data['close']
    return sorted(
        cid for cid, card in CARDS.items()
        if closes.get(card['ticker']) and closes[card['ticker']][0] is not None
    )


def _precompute(price_data: dict) -> dict:
    """
    (#125) 가격 데이터 하나당 한 번만 계산해 두는 값 (price_data['_pre']에 보관)
      - 라운드별 SPX·NDX·AAPL 등락률
      - 카드별로 발동 조건이 맞는 라운드 (0부터 세는 위치)
    같은 시작일로 run_game을 수천 번 부를 때(전체 조합 계산, 몬테카를로) 등락률을 매번 다시 계산하지 않는다.
    """
    pre = price_data.get('_pre')
    if pre is not None:
        return pre

    closes = price_data['close']
    n = min(GAME_ROUNDS, len(closes.get('^SPX', [])))

    def changes(ticker):
        s = closes.get(ticker) or []
        out = [None] * n
        for i in range(1, n):
            if i < len(s):
                out[i] = _calc_change_rate(s[i - 1], s[i])
        return out

    spx_c, ndx_c, aapl_c = changes('^SPX'), changes('^NDX'), changes('AAPL')
    trig = {}
    for cid, card in CARDS.items():
        ctype = card['type']
        if ctype == 'BUY_ONCE':
            rounds = []
        elif ctype == 'BUY_SPLIT':
            rounds = list(range(n))
        elif ctype == 'BUY_EVERY_N':
            rounds = [i for i in range(n) if (i + 1) % 5 == 0]
        else:   # BUY_ON_CONDITION, SELL_ON_CONDITION
            rounds = [i for i in range(n)
                      if _check_condition(card['condition'], spx_c[i], ndx_c[i], aapl_c[i])]
        trig[cid] = frozenset(rounds)

    pre = {'n': n, 'trig': trig}
    price_data['_pre'] = pre
    return pre


def normalize_decisions(decisions) -> dict:
    """
    {라운드: 선택} 형태로 정리 (키는 int/str 모두 허용, 없으면 빈 dict).
    위기 대응은 2~99라운드 중 카드 선택 라운드가 아닌 라운드에서만 가능하다.
    """
    if not decisions:
        return {}
    out = {}
    for r, choice in decisions.items():
        rn = int(r)
        if choice not in DECISION_CHOICES:
            raise ValueError(f'알 수 없는 위기 대응 선택입니다: {choice} (가능: {DECISION_CHOICES})')
        if rn in CARD_SELECT_ROUNDS or not 2 <= rn <= GAME_ROUNDS - 1:
            raise ValueError(f'위기 대응은 2~{GAME_ROUNDS - 1}라운드 중 카드 선택 라운드가 아닌 라운드에서만 가능합니다: {rn}')
        out[rn] = choice
    return out


def run_game(start_date: str, card_selections: dict, initial_asset: int = INITIAL_ASSET,
             price_data: dict = None, decisions: dict = None, base_ticker: str = '^SPX',
             collect_rounds: bool = True) -> dict:
    """
    게임 실행 메인 함수
    :param start_date: 시작 날짜 (예: "2008-09-02")
    :param card_selections: {라운드: 카드ID} (예: {1: 1, 25: 2, 50: 3, 75: 4})
    :param initial_asset: 초기 자산 (기본 10,000,000)
    :param price_data: load_price_data(start_date) 결과. None이면 내부에서 로드 (반복 호출 시 미리 넘겨서 재사용)
    :param decisions: (#125) 위기 대응 선택 {라운드: 'HOLD' | 'SELL_HALF' | 'BUY_MORE'}
    :param base_ticker: (#125) '더 산다'에서 사는 종목 (시나리오 기준 지수: '^SPX' 또는 '^NDX')
    :param collect_rounds: False면 매매가 일어날 수 있는 라운드만 계산하고 rounds에는 마지막 라운드만 담는다.
                           최종 자산·통계는 True일 때와 같다 (전체 조합 계산처럼 최종 결과만 필요할 때 사용)
    """
    if price_data is None:
        price_data = load_price_data(start_date)

    dates = price_data['dates']
    closes = price_data['close']
    spx_closes = closes['^SPX']
    if len(spx_closes) < GAME_ROUNDS:
        raise ValueError(f'SPX 데이터 부족 ({len(spx_closes)}개). start_date를 확인하세요.')

    selections = {int(r): int(c) for r, c in card_selections.items()}
    decisions = normalize_decisions(decisions)
    if base_ticker not in TICKERS:
        raise ValueError(f'알 수 없는 기준 종목입니다: {base_ticker}')

    # 상장 전 종목 카드는 선택할 수 없음
    available = set(available_card_ids(price_data))
    unavailable = [c for c in selections.values() if c not in available]
    if unavailable:
        names = ', '.join(CARDS[c]['name'] if c in CARDS else str(c) for c in unavailable)
        raise ValueError(f'이 시작일에는 사용할 수 없는 카드입니다 (상장 전 종목): {names}')

    trig = _precompute(price_data)['trig']

    cash = int(initial_asset)               # 현금은 정수(원) — Java long
    shares = {t: 0.0 for t in TICKERS}
    trigger_map = {}
    applied_card_ids = []
    active_cards = []                       # BUY_ONCE를 뺀 보유 카드 (priority 순)
    rounds_result = []
    card_stats = {}                         # 카드ID → {triggers, amount, skips{사유: 횟수}}
    decision_log = []                       # [{round, choice, amount}]

    def stat(cid):
        return card_stats.setdefault(cid, {'triggers': 0, 'amount': 0, 'skips': {}})

    # 계산할 라운드 (0부터 세는 위치)
    if collect_rounds:
        order = range(GAME_ROUNDS)
    else:
        events = {GAME_ROUNDS - 1}
        for r, cid in selections.items():
            if 1 <= r <= GAME_ROUNDS:
                events.add(r - 1)
                events.update(i for i in trig[cid] if i >= r - 1)
        events.update(d - 1 for d in decisions)
        order = sorted(events)

    last_index = GAME_ROUNDS - 1
    for i in order:
        round_number = i + 1

        def price(ticker):
            s = closes[ticker]
            return s[i] if i < len(s) else None

        # 1) 카드 선택 라운드 처리
        if round_number in selections:
            card_id = selections[round_number]
            if card_id not in applied_card_ids:
                applied_card_ids.append(card_id)
                card = CARDS[card_id]
                # BUY_ONCE 즉시 매수
                if card['type'] == 'BUY_ONCE':
                    p = price(card['ticker'])
                    if p is not None and p > 0:
                        buy_amount = cash * card['ratio']
                        cash -= int(buy_amount)
                        shares[card['ticker']] += buy_amount / p
                        s = stat(card_id)
                        s['triggers'] += 1
                        s['amount'] += int(buy_amount)
                else:
                    active_cards = sorted(
                        [CARDS[cid] for cid in applied_card_ids if CARDS[cid]['type'] != 'BUY_ONCE'],
                        key=lambda c: c['priority'])
                stat(card_id)

        # 2) (#125) 위기 대응 선택 — 카드 발동 전에 그날 종가로 매매
        choice = decisions.get(round_number)
        if choice is not None:
            traded = 0
            if choice == DECISION_SELL_HALF:
                for t in TICKERS:
                    p = price(t)
                    if shares[t] > 0 and p is not None and p > 0:
                        sell_shares = shares[t] * SELL_HALF_RATIO
                        proceeds = int(sell_shares * p)
                        cash += proceeds
                        shares[t] -= sell_shares
                        traded += proceeds
            elif choice == DECISION_BUY_MORE:
                p = price(base_ticker)
                if p is not None and p > 0:
                    amount = cash * BUY_MORE_RATIO
                    cash -= int(amount)
                    shares[base_ticker] += amount / p
                    traded = int(amount)
            decision_log.append({'round': round_number, 'choice': choice, 'amount': traded})

        # 3) 보유 자산 평가 — 종목 순서대로 하나씩 더한다 (Java와 같은 순서)
        def holdings_value():
            v = 0.0
            for t in TICKERS:
                p = price(t)
                if p is not None:           # 가격이 없는 종목은 보유량도 0이므로 평가에서 제외
                    v += shares[t] * p
            return v

        total_asset = cash + int(holdings_value())
        triggered_card_ids = []
        skipped_cards = []

        def skip(cid, reason):
            skipped_cards.append({'cardId': cid, 'reason': reason})
            skips = stat(cid)['skips']
            skips[reason] = skips.get(reason, 0) + 1

        # 4) 카드 발동. 파산 방지: 총자산이 initialAsset의 1% 이하면 카드 발동 중지
        if total_asset > initial_asset * 0.01:
            for card in active_cards:
                cid = card['id']
                if i not in trig[cid]:
                    continue

                # maxTrigger 체크
                if card['max_trigger'] is not None:
                    count = trigger_map.get(cid, 0)
                    if count >= card['max_trigger']:
                        skip(cid, SKIP_MAX_REACHED)
                        continue
                    trigger_map[cid] = count + 1

                # 매도 처리
                if card['type'] == 'SELL_ON_CONDITION':
                    p = price(card['ticker'])
                    if p is None or p <= 0:
                        skip(cid, SKIP_NO_PRICE)
                    elif shares[card['ticker']] > 0:
                        sell_shares = shares[card['ticker']] * card['ratio']
                        proceeds = int(sell_shares * p)
                        cash += proceeds
                        shares[card['ticker']] -= sell_shares
                        triggered_card_ids.append(cid)
                        s = stat(cid)
                        s['triggers'] += 1
                        s['amount'] += proceeds
                    else:
                        skip(cid, SKIP_NO_HOLDINGS)     # 팔 주식이 없음 (계산 결과는 0주 매도와 같다)
                    continue

                # 현금 부족 스킵 (총자산의 5% 미만)
                if cash < total_asset * 0.05:
                    skip(cid, SKIP_CASH_LOW)
                    continue

                # 매수 처리
                amount = cash * card['ratio']
                p = price(card['ticker'])
                if p is None or p <= 0:
                    skip(cid, SKIP_NO_PRICE)
                    continue

                cash -= int(amount)
                shares[card['ticker']] += amount / p
                triggered_card_ids.append(cid)
                s = stat(cid)
                s['triggers'] += 1
                s['amount'] += int(amount)

        # 5) 자산 재계산
        if collect_rounds or i == last_index:
            round_asset = cash + int(holdings_value())
            return_rate = _round2((round_asset - initial_asset) / initial_asset * 100)
            rounds_result.append({
                'round':          round_number,
                'date':           dates[i],
                'roundAsset':     round_asset,
                'returnRate':     return_rate,
                'triggeredCards': triggered_card_ids,
                'skippedCards':   skipped_cards,
            })

    final = rounds_result[-1] if rounds_result else {}
    return {
        'scenario':          'lehman',
        'start_date':        start_date,
        'card_selections':   {str(k): v for k, v in selections.items()},
        'decisions':         {str(k): v for k, v in decisions.items()},
        'initial_asset':     initial_asset,
        'rounds':            rounds_result,
        'final_asset':       final.get('roundAsset', initial_asset),
        'final_return_rate': final.get('returnRate', 0.0),
        # (#125) 사후 분석용 상세
        'final_cash':        cash,
        'final_shares':      dict(shares),
        'card_stats':        card_stats,
        'decision_log':      decision_log,
    }
