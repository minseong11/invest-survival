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

-- 기존 거인의 어깨 업데이트 (type, condition, max_trigger 반영)
INSERT INTO card (id, name, ticker, ratio, description, type, condition, max_trigger)
VALUES
    (1, '거인의 어깨',    '^SPX',   0.30, '현재 자산의 30%로 S&P500 즉시 매수',              'BUY_ONCE',         null,              null),
    (2, '황금 적립',      'XAUUSD', 0.05, '매 라운드마다 자산의 5%씩 금 매수',               'BUY_SPLIT',        null,              null),
    (3, '공포탐욕',       '^SPX',   0.20, 'S&P500이 -3% 이하 하락 시 자산의 20% 매수',       'BUY_ON_CONDITION', 'SPX_CHANGE <= -3', null),
    (4, '금 피난처',      'XAUUSD', 0.15, 'S&P500이 -5% 이하 하락 시 자산의 15% 금 매수',   'BUY_ON_CONDITION', 'SPX_CHANGE <= -5', null),
    (5, '기술의 파도',    '^NDX',   0.10, '나스닥이 +2% 이상 상승 시 자산의 10% 매수',       'BUY_ON_CONDITION', 'NDX_CHANGE >= 2',  null),
    (6, '낙폭과대 사냥',  '^NDX',   0.25, '나스닥이 -4% 이하 하락 시 자산의 25% 매수 (3회)', 'BUY_ON_CONDITION', 'NDX_CHANGE <= -4', 3)
    ON CONFLICT (id) DO UPDATE SET
    name        = EXCLUDED.name,
                            ticker      = EXCLUDED.ticker,
                            ratio       = EXCLUDED.ratio,
                            description = EXCLUDED.description,
                            type        = EXCLUDED.type,
                            condition   = EXCLUDED.condition,
                            max_trigger = EXCLUDED.max_trigger;