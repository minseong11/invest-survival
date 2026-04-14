INSERT INTO scenario (id, title, year, difficulty, description, color_hex, ticker, start_date, end_date)
VALUES
(1, '리먼브라더스 사태', 2008, 5, '2008년 금융위기. 역사상 최악의 시장 붕괴.', 'FAECE7', '^SPX', '2008-09-01', '2009-03-09'),
(2, '닷컴버블 붕괴', 2000, 4, '인터넷 버블이 터지며 나스닥 80% 폭락.', 'FAEEDA', '^NDX', '2000-03-01', '2002-10-09'),
(3, '코로나 쇼크', 2020, 3, '팬데믹으로 인한 급격한 시장 변동.', 'E6F1FB', '^SPX', '2020-02-19', '2020-12-31')
ON CONFLICT (id) DO UPDATE SET
    title = EXCLUDED.title,
    year = EXCLUDED.year,
    difficulty = EXCLUDED.difficulty,
    description = EXCLUDED.description,
    color_hex = EXCLUDED.color_hex,
    ticker = EXCLUDED.ticker,
    start_date = EXCLUDED.start_date,
    end_date = EXCLUDED.end_date;

INSERT INTO card (id, name, ticker, ratio, description, type, condition, max_trigger, priority)
VALUES
    (1,  '거인의 어깨',    '^SPX',  0.30, '현재 자산의 30%로 S&P500 즉시 매수',              'BUY_ONCE',         null,                null, 1),
    (2,  '황금 적립',      'XAUUSD',0.05, '매 라운드마다 자산의 5%씩 금 매수',               'BUY_SPLIT',        null,                null, 2),
    (3,  '공포탐욕',       '^SPX',  0.20, 'S&P500이 -3% 이하 하락 시 자산의 20% 매수',       'BUY_ON_CONDITION', 'SPX_CHANGE <= -3',  null, 3),
    (4,  '금 피난처',      'XAUUSD',0.15, 'S&P500이 -5% 이하 하락 시 자산의 15% 금 매수',   'BUY_ON_CONDITION', 'SPX_CHANGE <= -5',  null, 4),
    (5,  '기술의 파도',    '^NDX',  0.10, '나스닥이 +2% 이상 상승 시 자산의 10% 매수',       'BUY_ON_CONDITION', 'NDX_CHANGE >= 2',   null, 5),
    (6,  '낙폭과대 사냥',  '^NDX',  0.25, '나스닥이 -4% 이하 하락 시 자산의 25% 매수 (3회)', 'BUY_ON_CONDITION', 'NDX_CHANGE <= -4',  3,    6),
    (7,  '원유 베팅',      'USO',   0.20, '현재 자산의 20%로 원유 ETF 즉시 매수',            'BUY_ONCE',         null,                null, 7),
    (8,  '역발상 투자',    '^SPX',  0.15, 'S&P500이 +3% 이상 상승 시 자산의 15% 매도',       'SELL_ON_CONDITION','SPX_CHANGE >= 3',   null, 1),
    (9,  '애플 줍줍',      'AAPL',  0.10, '애플이 -5% 이하 하락 시 자산의 10% 매수 (5회)',   'BUY_ON_CONDITION', 'AAPL_CHANGE <= -5', 5,    9),
    (10, '채권 피난처',    'TLT',   0.03, '매 라운드마다 자산의 3%씩 채권 ETF 매수',         'BUY_SPLIT',        null,                null, 10),
    (11, '분할매수 장인',  '^NDX',  0.10, '매 5라운드마다 자산의 10% 나스닥 매수',            'BUY_EVERY_N',      null,                null, 11)
    ON CONFLICT (id) DO UPDATE SET
    name        = EXCLUDED.name,
                            ticker      = EXCLUDED.ticker,
                            ratio       = EXCLUDED.ratio,
                            description = EXCLUDED.description,
                            type        = EXCLUDED.type,
                            condition   = EXCLUDED.condition,
                            max_trigger = EXCLUDED.max_trigger,
                            priority    = EXCLUDED.priority;