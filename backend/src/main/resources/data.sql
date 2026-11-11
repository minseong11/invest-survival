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
    (1,  '거인의 어깨',    '^SPX',  0.30, '보유 현금의 30%로 S&P500 즉시 매수',              'BUY_ONCE',         null,                null, 1),
    (2,  '황금 적립',      'XAUUSD',0.05, '매 라운드 보유 현금의 5%씩 금 매수',               'BUY_SPLIT',        null,                null, 2),
    (3,  '공포탐욕',       '^SPX',  0.20, 'SPX -3% 이하 시 보유 현금의 20% SPX 매수',       'BUY_ON_CONDITION', 'SPX_CHANGE <= -3',  null, 3),
    (4,  '금 피난처',      'XAUUSD',0.15, 'SPX -5% 이하 시 보유 현금의 15% 금 매수',   'BUY_ON_CONDITION', 'SPX_CHANGE <= -5',  null, 4),
    (5,  '기술의 파도',    '^NDX',  0.10, 'NDX +2% 이상 시 보유 현금의 10% 나스닥 매수',       'BUY_ON_CONDITION', 'NDX_CHANGE >= 2',   null, 5),
    (6,  '낙폭과대 사냥',  '^NDX',  0.25, 'NDX -4% 이하 시 보유 현금의 25% 나스닥 매수 (최대 3회)', 'BUY_ON_CONDITION', 'NDX_CHANGE <= -4',  3,    6),
    (7,  '원유 베팅',      'USO',   0.20, '보유 현금의 20%로 원유 즉시 매수',            'BUY_ONCE',         null,                null, 7),
    (8,  '역발상 투자',    '^SPX',  0.15, 'SPX +3% 이상 시 보유 S&P500의 15% 매도',       'SELL_ON_CONDITION','SPX_CHANGE >= 3',   null, 1),
    (9,  '애플 줍줍',      'AAPL',  0.10, 'AAPL -5% 이하 시 보유 현금의 10% 애플 매수 (최대 5회)',   'BUY_ON_CONDITION', 'AAPL_CHANGE <= -5', 5,    9),
    (10, '채권 피난처',    'TLT',   0.03, '매 라운드 보유 현금의 3%씩 채권 매수',         'BUY_SPLIT',        null,                null, 10),
    (11, '분할매수 장인',  '^NDX',  0.10, '매 5라운드마다 보유 현금의 10% 나스닥 매수',            'BUY_EVERY_N',      null,                null, 11)
    ON CONFLICT (id) DO UPDATE SET
    name        = EXCLUDED.name,
                            ticker      = EXCLUDED.ticker,
                            ratio       = EXCLUDED.ratio,
                            description = EXCLUDED.description,
                            type        = EXCLUDED.type,
                            condition   = EXCLUDED.condition,
                            max_trigger = EXCLUDED.max_trigger,
                            priority    = EXCLUDED.priority;

-- =============================================
-- (11주차) 시나리오별 뉴스 이벤트
-- - event_date: 게임에 표시할 날짜 (주말 발표 → 다음 거래일, 장 마감 후 발표 → 다음 거래일)
-- - level: danger / caution / positive (그날 뉴스 성격 기준)
-- - 헤드라인의 숫자는 출처에서 확인된 것만 사용
-- - 목록을 바꿔도 남는 행이 없도록 전부 지우고 다시 입력
-- =============================================
DELETE FROM news_event;

INSERT INTO news_event (id, scenario_id, event_date, headline, level, source, source_url)
VALUES
    -- 1. 리먼 (1R 2008-09-02 ~ 100R 2009-01 하순)
    (1,  1, '2008-09-08', '미 정부, 패니메이·프레디맥 관리 체제 편입 (9/7 일요일 발표)', 'caution',  '연준',      'https://www.federalreserve.gov/newsevents/press/other/20080907a.htm'),
    (2,  1, '2008-09-15', '리먼 브라더스 파산 보호 신청, 메릴린치는 BoA가 인수',          'danger',   'CNN Money', 'https://money.cnn.com/2008/09/15/news/companies/lehman_brothers/index.htm'),
    (3,  1, '2008-09-29', '미 하원 구제금융안 부결, 다우 700포인트 넘게 폭락',            'danger',   'NPR',       'https://www.npr.org/2008/09/29/95180529/house-rejects-bailout-bill-wall-street-shudders'),
    (4,  1, '2008-10-03', '7,000억 달러 구제금융법 의회 통과·대통령 서명',                 'positive', 'CNN Money', 'https://money.cnn.com/2008/10/03/news/economy/house_friday_bailout/index.htm'),
    (5,  1, '2008-11-07', '10월 일자리 24만 개 감소, 실업률 6.5%로 14년 만에 최고',        'danger',   'NPR',       'https://www.npr.org/2008/11/07/96737955/u-s-jobless-rate-rises-to-14-year-high-6-5-percent'),
    (6,  1, '2008-11-24', '정부, 씨티그룹 긴급 지원 발표 (11/23 일요일 발표)',             'positive', '연준',      'https://www.federalreserve.gov/newsevents/pressreleases/bcreg20081123a.htm'),
    (7,  1, '2008-12-16', '연준, 기준금리 0~0.25%로 인하',                                 'positive', '연준',      'https://www.federalreserve.gov/newsevents/pressreleases/monetary20081216b.htm'),
    (8,  1, '2008-12-19', '정부, GM·크라이슬러에 174억 달러 긴급 대출',                    'caution',  'NPR',       'https://www.npr.org/2008/12/19/98498125/bush-sets-17-4-billion-in-loans-for-automakers'),

    -- 2. 닷컴 (1R 2000-03-01 ~ 100R 2000-07 하순)
    (9,  2, '2000-03-10', '나스닥 5,048로 사상 최고치 마감',                               'positive', 'ABC News',  'https://abcnews.go.com/Business/Decade/nasdaq-composite-closes-504862/story?id=9279557'),
    (10, 2, '2000-03-20', '배런스 "인터넷 기업 상당수 현금 고갈 임박" 보도',               'caution',  '배런스',    'https://pages.stern.nyu.edu/~adamodar/New_Home_Page/articles/cashburn.htm'),
    (11, 2, '2000-04-03', '법원 "마이크로소프트 반독점법 위반" 판결, 나스닥 급락',         'danger',   'CNN Money', 'https://money.cnn.com/2000/04/03/markets/markets_newyork/'),
    (12, 2, '2000-04-14', '나스닥 하루 9% 넘게 폭락',                                      'danger',   'CNN Money', 'https://money.cnn.com/2000/04/14/markets/techwrap/'),
    (13, 2, '2000-05-16', '연준, 금리 0.5%p 인상 (6.5%)',                                  'caution',  '연준',      'https://www.federalreserve.gov/boarddocs/press/general/2000/20000516/'),
    (14, 2, '2000-06-07', '법원, 마이크로소프트 회사 분할 명령',                           'caution',  'CNN Money', 'https://money.cnn.com/2000/06/07/technology/microsoft_ruling/'),
    (15, 2, '2000-06-28', '연준, 금리 6.5%로 동결 (인상 행진 멈춤)',                       'positive', '연준',      'https://www.federalreserve.gov/boarddocs/press/general/2000/20000628/default.htm'),

    -- 3. 코로나 (1R 2020-02-19 ~ 100R 2020-07-10)
    (16, 3, '2020-02-24', '이탈리아 등 확진자 급증, 다우 1,031포인트 급락',               'danger',   'AP',        'https://www.dailyherald.com/?p=402864'),
    (17, 3, '2020-03-09', '사우디·러시아 유가 전쟁, 미 증시 서킷브레이커 발동',            'danger',   'CNBC',      'https://www.cnbc.com/2020/03/09/circuit-breakers-triggered-for-the-first-time-in-20-years-pass-a-crucial-test.html'),
    (18, 3, '2020-03-23', '연준, 국채·MBS "필요한 만큼" 매입 발표 (사실상 무제한)',        'positive', '연준',      'https://www.federalreserve.gov/newsevents/pressreleases/monetary20200323b.htm'),
    (19, 3, '2020-04-20', 'WTI 원유 선물 사상 첫 마이너스 가격',                           'danger',   'Axios',     'https://www.axios.com/2020/04/20/oil-prices-collapse-coronavirus-demand'),
    (20, 3, '2020-04-29', '렘데시비르 임상서 회복 기간 단축 효과 확인, 증시 상승',         'positive', 'CNN',       'https://amp.cnn.com/cnn/2020/04/29/business/gilead-coronavirus-stock-market'),
    (21, 3, '2020-05-08', '4월 일자리 2,050만 개 감소, 실업률 14.7%',                      'danger',   'Axios',     'https://www.axios.com/2020/05/08/april-jobs-report-unemployment-coronavirus'),
    (22, 3, '2020-06-05', '5월 고용 250만 명 깜짝 증가, 실업률 13.3%로 하락',              'positive', 'PBS',       'https://www.pbs.org/newshour/economy/unemployment-rate-falls-to-13-3-us-adds-2-5-million-jobs'),
    (23, 3, '2020-06-11', '재확산 우려에 다우 1,800포인트 넘게 급락',                      'danger',   'NPR',       'https://www.mprnews.org/story/2020/06/11/npr-stocks-tumble-as-the-fed-warns-of-a-long-recovery-coronavirus-cases-spike');