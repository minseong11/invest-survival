import os
import pandas as pd

DATA_DIR = os.path.join(os.path.dirname(__file__), '..', 'data')

CSV_FILES = {
    '^SPX':  os.path.join(DATA_DIR, '^spx_d.csv'),
    '^NDX':  os.path.join(DATA_DIR, '^ndx_d.csv'),
    'GLD':   os.path.join(DATA_DIR, 'xauusd_d.csv'),  # XAUUSD = GLD
    'USO':   os.path.join(DATA_DIR, 'uso_d.csv'),
    'AAPL':  os.path.join(DATA_DIR, 'aapl_d.csv'),
    'TLT':   os.path.join(DATA_DIR, 'tlt_d.csv'),
}

_cache = {}

def load_all() -> dict:
    """전체 종목 CSV 로드 (캐시 사용)"""
    if _cache:
        return _cache
    for ticker, path in CSV_FILES.items():
        if not os.path.exists(path):
            print(f'[경고] 파일 없음: {path}')
            _cache[ticker] = pd.DataFrame()
            continue
        df = pd.read_csv(path)
        df.columns = [c.strip() for c in df.columns]
        df['Date'] = pd.to_datetime(df['Date'])
        df = df.sort_values('Date').reset_index(drop=True)
        _cache[ticker] = df
    return _cache

def get_price_list(start_date: str, ticker: str) -> pd.DataFrame:
    """start_date 이후 해당 ticker 데이터 반환"""
    all_data = load_all()
    df = all_data.get(ticker, pd.DataFrame())
    if df.empty:
        return df
    df = df[df['Date'] >= pd.to_datetime(start_date)].reset_index(drop=True)
    return df
