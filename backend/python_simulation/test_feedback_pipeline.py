"""
test_feedback_pipeline.py — 실제 피드백 출력 경로(/ai/v2/feedback)에 문장을 넣어 사용자에게 무엇이 나가는지 확인 (8주차)

7주차 피드백: "검증 실패 시 대체"만으로는 기존 GAP이 해결되지 않는다.
검증기 v3가 놓치는 GAP 6개 문장을 실제 출력 경로에 그대로 넣어, 사용자에게 반환되는 문장을 확인한다.

LLM 호출만 가짜로 바꾸고(지정한 문장을 그대로 돌려줌), 나머지는 서버 코드 그대로 실행한다.
Claude API 키·Spring Boot·DB 없이 실행 가능.

실행: python3 test_feedback_pipeline.py
"""
import os
os.environ.setdefault('ANTHROPIC_API_KEY', 'test-dummy')   # 실제 호출은 하지 않음

from fastapi.testclient import TestClient
import fastapi_server as fs

# 시장 상황: 리먼 25라운드 화면 예시와 같은 값
MARKET = dict(spxReturnSoFar=-17.27, spxVolatilitySoFar=3.28, spxMddSoFar=-20.5, currentRound=25)


def req(card_ids, already=(1,)):
    contribs = [1.26, 0.14, -3.22]
    return dict(**MARKET, alreadyCards=list(already),
                rankings=[{'rank': i + 1, 'cardId': c, 'contribution': contribs[i]}
                          for i, c in enumerate(card_ids)])


CASES = [
    # (이름, LLM이 돌려준 문장, 요청의 후보 카드(1위가 첫 번째), 기대 status)
    ('GAP1 빠지면(-2%, 정답 -3%)',
     '공포탐욕은 SPX가 -2%나 빠지면 매수하는 카드입니다.', [3, 8, 2], 'fallback'),
    ('GAP2 초과하면(+5%, 정답 +2%)',
     '기술의 파도는 NDX가 +5%를 초과하면 매수합니다.', [5, 8, 2], 'fallback'),
    ('GAP3 밑돌면(-2%, 정답 -5%)',
     '금 피난처는 SPX가 -2%를 밑돌면 매수하는 카드입니다.', [4, 8, 2], 'fallback'),
    ('GAP4 웃돌면(+10%, 정답 +3%)',
     '역발상 투자는 SPX가 +10%를 웃돌면 매도합니다.', [8, 3, 2], 'fallback'),
    ('GAP5 최대 5회(정답 3회)',
     '낙폭과대 사냥은 최대 5회까지만 발동합니다.', [6, 8, 2], 'fallback'),
    ('GAP6 무조건부 카드를 조건부로',
     '채권 피난처는 TLT가 하락할 때만 매수하는 카드입니다.', [10, 8, 2], 'fallback'),
    ('정상: 시장 수치·예측값만 사용',
     '현재 SPX 누적수익률이 -17.27%로 깊은 하락장이고 변동성도 3.28로 높아 급락일이 반복될 가능성이 커요. '
     '공포탐욕은 이런 급락 국면에서 저점 매수 기회를 노리는 카드예요. 3위 카드는 예측 기여도가 -3.22%로 낮아요.',
     [3, 8, 2], 'llm'),
    ('정상: 마크다운 섞임 → 기호 제거',
     '## 1위 카드 선택 근거\n현재 SPX 누적수익률이 **-17.27%**로 하락장이에요. 공포탐욕이 이런 국면에 맞아요.',
     [3, 8, 2], 'llm'),
    ('조건 없는 카드를 "언제 유리한지"만 설명 → 통과',
     '황금 적립은 하락장일 때 유리할 수 있어요.', [2, 8, 3], 'llm'),
]


def fake_llm(text):
    """지정한 문장을 그대로 돌려주는 가짜 LLM 호출"""
    def create(**kwargs):
        return type('M', (), {'content': [type('C', (), {'text': text})()]})()
    return create


def main():
    fail = 0
    with TestClient(fs.app) as c:
        for name, llm_text, cards, expected in CASES:
            fs.client.messages.create = fake_llm(llm_text)
            r = c.post('/ai/v2/feedback', json=req(cards)).json()
            ok = r['status'] == expected
            fail += not ok
            print('=' * 70)
            print(f"[{'PASS' if ok else 'FAIL'}] {name}  (기대 {expected} / 실제 {r['status']}, verified={r['verified']})")
            print(f'LLM 문장 : {llm_text}')
            print('사용자에게 나가는 문장:')
            for line in r['feedback'].split('\n'):
                print(f'  | {line}')

        # LLM 호출 실패
        def boom(**k):
            raise RuntimeError('API 오류')
        fs.client.messages.create = boom
        r = c.post('/ai/v2/feedback', json=req([3, 8, 2])).json()
        ok = r['status'] == 'failed' and r['feedback'] != ''
        fail += not ok
        print('=' * 70)
        print(f"[{'PASS' if ok else 'FAIL'}] LLM 호출 실패  (status={r['status']}, verified={r['verified']})")
        for line in r['feedback'].split('\n'):
            print(f'  | {line}')

    total = len(CASES) + 1
    print('=' * 70)
    print(f'결과: {total - fail}/{total} 통과')


if __name__ == '__main__':
    main()
