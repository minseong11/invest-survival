"""
Java GameService.calculateRounds() 를 Python으로 포팅
카드 정의, 조건 체크, 라운드 계산 로직 포함
"""
from data_loader import get_price_list

INITIAL_ASSET = 10_000_000

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


def _calc_change_rate(prev_close, curr_close) -> float:
    if prev_close is None or prev_close <= 0:
        return 0.0
    rate = (curr_close - prev_close) / prev_close * 100
    return round(rate, 2)


def _check_condition(condition, spx_change, ndx_change, aapl_change) -> bool:
    if condition is None:
        return False
    if condition == 'SPX_CHANGE <= -3':    return spx_change  <= -3
    elif condition == 'SPX_CHANGE <= -5':  return spx_change  <= -5
    elif condition == 'SPX_CHANGE >= 3':   return spx_change  >= 3
    elif condition == 'NDX_CHANGE >= 2':   return ndx_change  >= 2
    elif condition == 'NDX_CHANGE <= -4':  return ndx_change  <= -4
    elif condition == 'AAPL_CHANGE <= -5': return aapl_change <= -5
    return False


def run_game(start_date: str, card_selections: dict, initial_asset: int = INITIAL_ASSET) -> dict:
    """
    게임 실행 메인 함수
    :param start_date: 시작 날짜 (예: "2008-09-02")
    :param card_selections: {라운드: 카드ID} (예: {1: 1, 25: 2, 50: 3, 75: 4})
    :param initial_asset: 초기 자산 (기본 10,000,000)
    """
    price_data = {ticker: get_price_list(start_date, ticker) for ticker in TICKERS}

    spx_list = price_data['^SPX']
    if len(spx_list) < 100:
        raise ValueError(f'SPX 데이터 부족 ({len(spx_list)}개). start_date를 확인하세요.')

    cash = float(initial_asset)
    shares = {t: 0.0 for t in TICKERS}
    trigger_map = {}
    applied_card_ids = []
    rounds_result = []

    for i in range(100):
        if i >= len(spx_list):
            break

        round_number = i + 1

        # 카드 선택 라운드 처리
        if round_number in card_selections:
            card_id = card_selections[round_number]
            if card_id not in applied_card_ids:
                applied_card_ids.append(card_id)
                card = CARDS[card_id]
                # BUY_ONCE 즉시 매수
                if card['type'] == 'BUY_ONCE':
                    ticker = card['ticker']
                    df = price_data.get(ticker)
                    if df is not None and len(df) > i:
                        price = df.iloc[i]['Close']
                        if price > 0:
                            buy_amount = cash * card['ratio']
                            cash -= buy_amount
                            shares[ticker] += buy_amount / price

        # 현재 라운드 주가
        spx_curr = spx_list.iloc[i]
        spx_prev = spx_list.iloc[i - 1] if i > 0 else None

        def get_curr(ticker):
            df = price_data[ticker]
            return df.iloc[i] if i < len(df) else None

        def get_prev(ticker):
            df = price_data[ticker]
            return df.iloc[i - 1] if (i > 0 and i < len(df)) else None

        ndx_curr  = get_curr('^NDX');  ndx_prev  = get_prev('^NDX')
        aapl_curr = get_curr('AAPL'); aapl_prev = get_prev('AAPL')
        gld_curr  = get_curr('GLD')
        uso_curr  = get_curr('USO')
        tlt_curr  = get_curr('TLT')

        def close(row):
            return float(row['Close']) if row is not None else 0.0

        spx_change  = _calc_change_rate(close(spx_prev),  close(spx_curr))
        ndx_change  = _calc_change_rate(close(ndx_prev),  close(ndx_curr))
        aapl_change = _calc_change_rate(close(aapl_prev), close(aapl_curr))

        prices = {
            '^SPX': close(spx_curr), '^NDX': close(ndx_curr),
            'GLD':  close(gld_curr), 'USO':  close(uso_curr),
            'AAPL': close(aapl_curr),'TLT':  close(tlt_curr),
        }

        total_asset = cash + sum(shares[t] * prices[t] for t in TICKERS)
        triggered_card_ids = []

        # 파산 방지: 총자산이 initialAsset의 1% 이하면 카드 발동 중지
        if total_asset > initial_asset * 0.01:
            active_cards = sorted(
                [CARDS[cid] for cid in applied_card_ids],
                key=lambda c: c['priority']
            )

            for card in active_cards:
                if card['type'] == 'BUY_ONCE':
                    continue

                triggered = False
                if card['type'] == 'BUY_SPLIT':
                    triggered = True
                elif card['type'] in ('BUY_ON_CONDITION', 'SELL_ON_CONDITION'):
                    triggered = _check_condition(card['condition'], spx_change, ndx_change, aapl_change)
                elif card['type'] == 'BUY_EVERY_N':
                    triggered = (round_number % 5 == 0)

                if not triggered:
                    continue

                # maxTrigger 체크
                if card['max_trigger'] is not None:
                    count = trigger_map.get(card['id'], 0)
                    if count >= card['max_trigger']:
                        continue
                    trigger_map[card['id']] = count + 1

                # 매도 처리
                if card['type'] == 'SELL_ON_CONDITION':
                    if card['ticker'] == '^SPX' and prices['^SPX'] > 0:
                        sell_shares = shares['^SPX'] * card['ratio']
                        shares['^SPX'] -= sell_shares
                        cash += sell_shares * prices['^SPX']
                    triggered_card_ids.append(card['id'])
                    continue

                # 현금 부족 스킵 (총자산의 5% 미만)
                if cash < total_asset * 0.05:
                    continue

                # 매수 처리
                amount = cash * card['ratio']
                price  = prices.get(card['ticker'], 0.0)
                if price <= 0:
                    continue

                cash -= amount
                shares[card['ticker']] += amount / price
                triggered_card_ids.append(card['id'])

        # 자산 재계산
        total_asset = cash + sum(shares[t] * prices[t] for t in TICKERS)
        round_asset = int(total_asset)
        return_rate = round((total_asset - initial_asset) / initial_asset * 100, 2)

        rounds_result.append({
            'round':          round_number,
            'date':           str(spx_curr['Date'])[:10],
            'roundAsset':     round_asset,
            'returnRate':     return_rate,
            'triggeredCards': triggered_card_ids,
        })

    final = rounds_result[-1] if rounds_result else {}
    return {
        'scenario':          'lehman',
        'start_date':        start_date,
        'card_selections':   {str(k): v for k, v in card_selections.items()},
        'initial_asset':     initial_asset,
        'rounds':            rounds_result,
        'final_asset':       final.get('roundAsset', initial_asset),
        'final_return_rate': final.get('returnRate', 0.0),
    }
