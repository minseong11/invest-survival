"""
AI 서버(FastAPI) 엔드포인트 테스트 (#125) — 가상의 주가 CSV + 가짜 LLM (실제 API를 부르지 않음)
"""
import pytest
from fastapi.testclient import TestClient

import fastapi_server as fs
from conftest import FakeLLM

BODY = {
    'startDate': '2008-09-01',
    'playerCardSelections': {'1': 1, '25': 4, '50': 5, '75': 9},
    'offeredCards': {'1': [1, 3, 10], '25': [4, 7, 8], '50': [5, 2, 11], '75': [9, 6, 3]},
    'decisions': {'11': 'SELL_HALF', '21': 'HOLD', '61': 'BUY_MORE'},
    'baseTicker': '^SPX',
}


@pytest.fixture(scope='module')
def client():
    with TestClient(fs.app) as c:
        yield c


@pytest.fixture
def llm(monkeypatch):
    def use(**kwargs):
        fake = FakeLLM(**kwargs)
        monkeypatch.setattr(fs.client.messages, 'create', fake)
        return fake
    return use


def heads(text):
    return [line.split(':')[0] for line in text.split('\n')]


# ── 사후 분석 ────────────────────────────────────────────────

def test_backtest_returns_extended_analysis(client):
    r = client.post('/ai/analysis/backtest', json=BODY)
    assert r.status_code == 200, r.text
    a = r.json()
    assert a['totalCombinations'] == 7920 and a['cardPoolSize'] == 11
    assert a['grade'] in {'S', 'A', 'B', 'C', 'D'}
    assert len(a['cardReport']) == 4
    assert [d['round'] for d in a['decisionReview']['rounds']] == [11, 21, 61]
    assert [p['label'] for p in a['epilogue']['points']] == ['6개월 뒤', '1년 뒤']
    assert a['risk']['marketMdd'] < 0
    assert a['offeredAnalysis']['playerResult']['finalAsset'] == a['playerResult']['finalAsset']


def test_backtest_without_decisions_is_backward_compatible(client):
    body = {k: BODY[k] for k in ('startDate', 'playerCardSelections')}
    a = client.post('/ai/analysis/backtest', json=body).json()
    assert a['decisionReview'] is None and a['offeredAnalysis'] is None
    assert a['playerResult']['rank'] >= 1


@pytest.mark.parametrize('patch, message', [
    ({'decisions': {'25': 'HOLD'}}, '카드 선택 라운드가 아닌'),
    ({'decisions': {'10': 'RUN'}}, '알 수 없는 위기 대응'),
    ({'baseTicker': 'BTC'}, '알 수 없는 기준 종목'),
    ({'playerCardSelections': {'1': 1, '25': 1, '50': 5, '75': 9}}, '유효하지 않은 카드 조합'),
    ({'topN': 0}, 'topN'),
])
def test_backtest_rejects_bad_requests(client, patch, message):
    r = client.post('/ai/analysis/backtest', json={**BODY, **patch})
    assert r.status_code == 400 and message in r.json()['detail']


def test_prewarm_then_ready(client):
    body = {'startDate': '2008-09-01', 'decisions': {'33': 'SELL_HALF'}, 'baseTicker': '^SPX'}
    assert client.post('/ai/analysis/prewarm', json=body).json() == {'status': 'started'}
    # 미리 계산 중에 같은 조건의 분석 요청이 와도 한 번만 계산하고 같은 결과를 쓴다
    a = client.post('/ai/analysis/backtest', json={**BODY, 'decisions': {'33': 'SELL_HALF'}}).json()
    assert a['totalCombinations'] == 7920
    assert client.post('/ai/analysis/prewarm', json=body).json() == {'status': 'ready'}
    assert client.post('/ai/analysis/prewarm', json={**body, 'decisions': {'50': 'HOLD'}}).status_code == 400


# ── AI 코치 한마디 ───────────────────────────────────────────

def test_coach_uses_llm_sentence_when_it_passes_checks(client, llm):
    fake = llm(text='**하락장에서는** 한 번에 사기보다 나눠 사는 카드를 먼저 골라 보세요.')
    r = client.post('/ai/analysis/coach', json=BODY).json()
    assert r['status'] == 'llm' and r['verified'] is True
    assert heads(r['comment'])[0] == '요약' and heads(r['comment'])[-1] == '다음엔'
    assert r['comment'].split('\n')[-1] == '다음엔: 하락장에서는 한 번에 사기보다 나눠 사는 카드를 먼저 골라 보세요.'
    assert fake.calls[0]['model'] == fs.LLM_MODEL
    assert '숫자는 쓰지 마' in fake.calls[0]['messages'][0]['content']


@pytest.mark.parametrize('text', [
    '다음엔 현금을 30% 남겨 보세요.',                        # 숫자
    '금 카드를 반드시 먼저 고르세요.',                        # 단정 표현
    '황금 적립을 먼저 골라 보세요.',                          # 고르지 않은 카드
    '금 피난처는 SPX가 -3% 이하일 때 사니까 골라 보세요.',     # 틀린 카드 조건
])
def test_coach_falls_back_when_llm_sentence_fails_checks(client, llm, text):
    llm(text=text)
    r = client.post('/ai/analysis/coach', json=BODY).json()
    assert r['status'] == 'fallback' and r['verified'] is False
    assert text not in r['comment']
    assert heads(r['comment'])[-1] == '다음엔'


def test_coach_survives_llm_failure(client, llm):
    llm(error=RuntimeError('API 오류'))
    r = client.post('/ai/analysis/coach', json=BODY)
    assert r.status_code == 200
    assert r.json()['status'] == 'failed' and r.json()['verified'] is None
    assert heads(r.json()['comment'])[-1] == '다음엔'


def test_coach_numbers_come_from_analysis(client, llm):
    llm(error=RuntimeError('x'))
    analysis = client.post('/ai/analysis/backtest', json=BODY).json()
    comment = client.post('/ai/analysis/coach', json=BODY).json()['comment']
    market = abs(analysis['risk']['marketReturnRate'])
    assert f'{market:.1f}%' in comment.split('\n')[0]


# ── LLM 응답 읽기 ────────────────────────────────────────────

def test_llm_text_skips_non_text_blocks(llm):
    # 생각 블록이 먼저 오는 모델에서도 글 블록만 읽는다 (기존: content[0].text → 오류)
    thinking = type('Block', (), {'type': 'thinking', 'thinking': '...'})()
    text = type('Block', (), {'type': 'text', 'text': '시장이 흔들릴 때 금이 버팀목이 될 수 있어요.'})()
    llm(blocks=[thinking, text])
    assert fs.llm_text('아무 질문') == '시장이 흔들릴 때 금이 버팀목이 될 수 있어요.'


def test_llm_text_fails_when_there_is_no_text(llm):
    llm(blocks=[])
    with pytest.raises(RuntimeError, match='글이 없습니다'):
        fs.llm_text('아무 질문')


def test_feedback_falls_back_when_response_has_no_text(client, llm):
    llm(blocks=[])
    body = {
        'spxReturnSoFar': -17.27, 'spxVolatilitySoFar': 3.28, 'spxMddSoFar': -20.5, 'currentRound': 25,
        'alreadyCards': [1],
        'rankings': [{'rank': 1, 'cardId': 4, 'contribution': 1.26}, {'rank': 2, 'cardId': 8, 'contribution': 0.14},
                     {'rank': 3, 'cardId': 2, 'contribution': -3.22}],
    }
    r = client.post('/ai/v2/feedback', json=body).json()
    assert r['status'] == 'failed'
    assert heads(r['feedback'])[:3] == ['지금 시장', '이 카드는', '그래서']


def test_health(client):
    assert client.get('/').json()['status'] == 'ok'
