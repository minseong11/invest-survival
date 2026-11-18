"""
make_fixture_data.py — 테스트용 대체 주가 데이터 생성 (#125)

※ 실제 주가가 아니다. 난수로 만든 가상의 가격이다.
   게임 결과·AI 성능을 이야기할 때는 반드시 팀 드라이브의 실제 CSV(backend/data)를 써야 한다.

실제 주가 CSV는 git에 없어서(용량·출처 문제) 자동 테스트와 CI에서는 쓸 수 없다.
이 스크립트는 같은 파일 이름·형식(STOOQ: Date,Open,High,Low,Close,Volume)으로 가상의 가격을 만들어
  - Python 테스트(pytest)
  - CI에서 Spring Boot·FastAPI를 실제로 띄워 하는 Java↔Python 일치 확인
에 쓴다. 두 계산이 같은지, 응답 형식이 맞는지는 가격이 가상이어도 똑같이 확인된다.

실제 데이터와 같게 맞춘 점
  - 기간 1995~2025, 원유(USO)는 2006-04-10부터, 미국 장기채(TLT)는 2002-07-30부터 (닷컴 시나리오에서 두 카드 제외)
  - 2000·2008·2020년 위기 구간에 하루 ±3~10% 움직임이 나오도록 변동성을 키움 (조건부 카드가 발동하도록)
  - 금·원유·채권은 며칠씩 빠진 날이 있음 (그날은 직전 거래일 가격을 쓰는 정렬 규칙 확인용)
다른 점
  - 미국 공휴일이 없다 (모든 평일이 거래일) → 라운드 번호가 실제 데이터와 며칠 다를 수 있음

같은 seed면 항상 같은 파일이 나온다.

사용법:
    python3 tests/make_fixture_data.py <폴더>          # 예: python3 tests/make_fixture_data.py ../data
"""
import os
import sys

import numpy as np
import pandas as pd

MARKER = 'FIXTURE_DATA.txt'

# (시작, 끝, 하루 평균 수익률, 하루 변동성) — 시장 공통 요인의 위기 구간
CRISIS = [
    ('2000-03-13', '2000-05-31', -0.0040, 0.030),
    ('2000-06-01', '2002-10-09', -0.0008, 0.018),
    ('2008-09-01', '2009-03-09', -0.0045, 0.035),
    ('2009-03-10', '2009-12-31',  0.0025, 0.016),
    ('2020-02-20', '2020-03-23', -0.0160, 0.045),
    ('2020-03-24', '2020-08-31',  0.0050, 0.022),
]

# 종목: (파일 이름, 첫 날짜, 시작 가격, 시장 민감도, 고유 변동성, 평소 하루 수익률, 빠지는 날 간격)
ASSETS = [
    ('^spx_d.csv',   '1995-01-02', 460.0,  1.00, 0.002, 0.0000, 0),
    ('^ndx_d.csv',   '1995-01-02', 400.0,  1.25, 0.006, 0.0001, 0),
    ('xauusd_d.csv', '1995-01-02', 380.0, -0.15, 0.009, 0.0002, 41),
    ('uso_d.csv',    '2006-04-10', 68.0,   0.50, 0.020, -0.0002, 53),
    ('aapl_d.csv',   '1995-01-02', 0.35,   1.30, 0.018, 0.0006, 0),
    ('tlt_d.csv',    '2002-07-30', 82.0,  -0.30, 0.007, 0.0001, 47),
]


def generate(out_dir: str, seed: int = 20250125) -> None:
    os.makedirs(out_dir, exist_ok=True)
    rng = np.random.default_rng(seed)
    dates = pd.bdate_range('1995-01-02', '2025-12-31')
    n = len(dates)

    # 시장 공통 요인 (하루 로그 수익률)
    market = rng.normal(0.0003, 0.009, n)
    for start, end, mu, sigma in CRISIS:
        mask = (dates >= start) & (dates <= end)
        market[mask] = rng.normal(mu, sigma, int(mask.sum()))

    for name, first, start_price, beta, idio, drift, drop_every in ASSETS:
        noise = rng.normal(0.0, idio, n)
        ret = beta * market + noise + drift
        sel = dates >= first
        d = dates[sel]
        close = start_price * np.exp(np.cumsum(ret[sel]))

        df = pd.DataFrame({'Date': d.strftime('%Y-%m-%d'), 'Close': close})
        prev = df['Close'].shift(1).fillna(df['Close'])
        df['Open'] = prev * (1 + rng.normal(0, 0.002, len(df)))
        spread = np.abs(rng.normal(0, 0.004, len(df)))
        df['High'] = df[['Open', 'Close']].max(axis=1) * (1 + spread)
        df['Low'] = df[['Open', 'Close']].min(axis=1) * (1 - spread)
        df['Volume'] = 1_000_000
        if drop_every:      # 며칠씩 빠진 날 (휴장일 차이 흉내)
            df = df[(np.arange(len(df)) % drop_every) != drop_every - 1]

        df[['Date', 'Open', 'High', 'Low', 'Close', 'Volume']].to_csv(
            os.path.join(out_dir, name), index=False, float_format='%.6f')

    with open(os.path.join(out_dir, MARKER), 'w', encoding='utf-8') as f:
        f.write('이 폴더의 CSV는 tests/make_fixture_data.py가 만든 테스트용 가상의 주가입니다 (실제 주가 아님).\n'
                f'seed={seed}\n')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    target = sys.argv[1]
    real = [name for name, *_ in ASSETS
            if os.path.exists(os.path.join(target, name)) and not os.path.exists(os.path.join(target, MARKER))]
    if real:
        print(f'중단: {target} 에 이미 CSV가 있습니다 ({", ".join(real)}).\n'
              f'실제 주가 파일을 덮어쓰지 않도록 다른 폴더를 지정하거나 파일을 옮긴 뒤 다시 실행하세요.')
        sys.exit(1)
    generate(target)
    print(f'테스트용 대체 데이터 생성 완료: {target} (실제 주가 아님)')
