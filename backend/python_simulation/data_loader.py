import os
import pandas as pd

# 주가 CSV 폴더. 기본은 backend/data, 환경변수 SURVIVAL_DATA_DIR로 바꿀 수 있다 (테스트·CI용 대체 데이터)
DATA_DIR = os.environ.get('SURVIVAL_DATA_DIR') or os.path.join(os.path.dirname(__file__), '..', 'data')

CSV_NAMES = {
    '^SPX':  '^spx_d.csv',
    '^NDX':  '^ndx_d.csv',
    'GLD':   'xauusd_d.csv',  # XAUUSD = GLD
    'USO':   'uso_d.csv',
    'AAPL':  'aapl_d.csv',
    'TLT':   'tlt_d.csv',
}
CSV_FILES = {ticker: os.path.join(DATA_DIR, name) for ticker, name in CSV_NAMES.items()}

_cache = {}


def set_data_dir(path: str):
    """CSV 폴더를 바꾸고 캐시를 비운다 (테스트에서 대체 데이터 폴더를 지정할 때 사용)"""
    global DATA_DIR
    DATA_DIR = path
    CSV_FILES.clear()
    CSV_FILES.update({ticker: os.path.join(path, name) for ticker, name in CSV_NAMES.items()})
    _cache.clear()

def load_all() -> dict:
    """전체 종목 CSV 로드 (캐시 사용)"""
    if _cache:
        return _cache
    for ticker, path in CSV_FILES.items():
        if not os.path.exists(path):
            print(f'[경고] 파일 없음: {path}')
            _cache[ticker] = pd.DataFrame()
            continue
        # float_precision='round_trip': 문자열 → 실수 변환을 Java Double.parseDouble과 같게
        # (기본 파서는 빠르지만 끝자리가 다를 수 있어 Java와 1원 차이가 날 수 있음)
        df = pd.read_csv(path, float_precision='round_trip')
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
