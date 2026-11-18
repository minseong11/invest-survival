"""
pytest 공통 설정 (#125)
  - 모든 테스트는 tests/make_fixture_data.py로 만든 가상의 주가를 쓴다 (실제 CSV·서버·API 키 없이 실행됨)
  - LLM 호출은 테스트마다 가짜로 바꾼다 (실제 API를 부르지 않음)

실행: cd backend/python_simulation && pytest
"""
import os
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
for path in (ROOT, HERE):
    if path not in sys.path:
        sys.path.insert(0, path)

os.environ.setdefault('ANTHROPIC_API_KEY', 'test-dummy')   # 실제 호출은 하지 않음


@pytest.fixture(scope='session', autouse=True)
def fixture_data(tmp_path_factory):
    """가상의 주가 CSV를 임시 폴더에 만들고 data_loader가 그 폴더를 보게 한다"""
    import backtest
    import data_loader
    from make_fixture_data import generate

    data_dir = tmp_path_factory.mktemp('prices')
    generate(str(data_dir))
    data_loader.set_data_dir(str(data_dir))
    backtest.clear_cache()
    yield str(data_dir)


def make_price_data(spx, ndx=None, gld=None, uso=None, aapl=None, tlt=None, listed=None):
    """
    손으로 만든 가격으로 price_data를 만든다 (run_game에 바로 넘길 수 있는 형태).
    spx: 100개 이상의 종가. 나머지 종목을 주지 않으면 100.0으로 고정.
    listed: 상장된 종목 목록 (기본: 전부). 여기 없는 종목은 가격 없음(None)
    """
    n = len(spx)
    flat = [100.0] * n
    close = {
        '^SPX': [float(v) for v in spx],
        '^NDX': [float(v) for v in (ndx or flat)],
        'GLD': [float(v) for v in (gld or flat)],
        'USO': [float(v) for v in (uso or flat)],
        'AAPL': [float(v) for v in (aapl or flat)],
        'TLT': [float(v) for v in (tlt or flat)],
    }
    if listed is not None:
        for t in close:
            if t not in listed:
                close[t] = [None] * n
    dates = [f'2001-01-{(i % 28) + 1:02d}' for i in range(n)]
    return {'dates': dates, 'close': close}


class FakeLLM:
    """fastapi_server.client.messages.create를 대신하는 가짜 — 지정한 글(또는 예외)을 돌려준다"""

    def __init__(self, text=None, error=None, blocks=None):
        self.text, self.error, self.blocks = text, error, blocks
        self.calls = []

    def __call__(self, **kwargs):
        self.calls.append(kwargs)
        if self.error:
            raise self.error
        if self.blocks is not None:
            content = self.blocks
        else:
            content = [type('Block', (), {'type': 'text', 'text': self.text})()]
        return type('Message', (), {'content': content, 'stop_reason': 'end_turn'})()
