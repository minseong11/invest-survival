"""
run_verification.py — LLM 피드백 사실 왜곡 검증 실행 스크립트

로컬에서 돌고 있는 FastAPI 서버(/ai/v2/feedback)에 다양한 시나리오를 반복 호출하고,
verify_feedback.py의 규칙 기반 검증을 적용해 리포트를 생성한다.

사용법:
    cd backend/python_simulation
    python3 run_verification.py

사전 조건:
    - fastapi_server.py가 8000번 포트에서 실행 중이어야 함
    - ANTHROPIC_API_KEY 환경변수 설정 필요
"""
import random
import requests
from datetime import datetime
from verify_feedback import verify_feedback, CARD_FACTS

BASE_URL = 'http://localhost:8000'
ALL_CARD_IDS = list(range(1, 12))

# 검증에 쓸 시나리오 개수 (늘리고 싶으면 이 값만 바꾸면 됨)
N_SCENARIOS = 100


def make_random_scenario():
    """무작위 시나리오 하나 생성: 시장 상황 + 이미 보유 카드 + 후보 rankings"""
    current_round = random.choice([25, 50])

    n_already = random.randint(0, 3)
    already_cards = random.sample(ALL_CARD_IDS, n_already)

    remaining = [c for c in ALL_CARD_IDS if c not in already_cards]
    n_candidates = min(3, len(remaining))
    candidates = random.sample(remaining, n_candidates)

    rankings = [
        {
            'rank': i + 1,
            'cardId': cid,
            'contribution': round(random.uniform(-2.0, 4.0), 2),
        }
        for i, cid in enumerate(sorted(candidates, key=lambda _: random.random()))
    ]
    # rank 순서 재정렬 (contribution 내림차순으로 rank 부여)
    rankings.sort(key=lambda r: -r['contribution'])
    for i, r in enumerate(rankings):
        r['rank'] = i + 1

    return {
        'spxReturnSoFar': round(random.uniform(-30.0, 20.0), 2),
        'spxVolatilitySoFar': round(random.uniform(0.5, 4.0), 2),
        'spxMddSoFar': round(random.uniform(-40.0, 0.0), 2),
        'currentRound': current_round,
        'alreadyCards': already_cards,
        'rankings': rankings,
    }


def run():
    results = []
    print(f'{N_SCENARIOS}개 시나리오로 검증 시작...\n')

    for i in range(N_SCENARIOS):
        scenario = make_random_scenario()
        try:
            resp = requests.post(f'{BASE_URL}/ai/v2/feedback', json=scenario, timeout=30)
            resp.raise_for_status()
            feedback = resp.json().get('feedback', '')
        except Exception as e:
            print(f'[{i+1}/{N_SCENARIOS}] 요청 실패: {e}')
            continue

        ranking_ids = [r['cardId'] for r in scenario['rankings']]
        result = verify_feedback(feedback, scenario['alreadyCards'], ranking_ids)

        results.append({
            'scenario': scenario,
            'feedback': feedback,
            'result': result,
        })

        status = '✅ 일치' if result.consistent else f'⚠️  위반 {len(result.issues)}건'
        print(f'[{i+1}/{N_SCENARIOS}] {status}')

    # ── 요약 ──────────────────────────────
    total = len(results)
    passed = sum(1 for r in results if r['result'].consistent)
    failed = total - passed

    print(f'\n=== 검증 결과 요약 ===')
    print(f'총 {total}건 중 일치 {passed}건 / 위반 {failed}건 ({passed/total*100:.1f}% 통과)' if total else '결과 없음')

    # ── 리포트 파일 생성 ──────────────────
    report_path = 'verification_report.md'
    with open(report_path, 'w', encoding='utf-8') as f:
        f.write(f'# LLM 피드백 사실 왜곡 검증 리포트\n\n')
        f.write(f'생성 시각: {datetime.now().isoformat()}\n\n')
        f.write(f'- 총 시나리오: {total}\n')
        f.write(f'- 일치: {passed}\n')
        f.write(f'- 위반: {failed}\n')
        f.write(f'- 통과율: {passed/total*100:.1f}%\n\n' if total else '\n')

        f.write('## 위반 사례 상세\n\n')
        any_failed = False
        for i, r in enumerate(results):
            if r['result'].consistent:
                continue
            any_failed = True
            f.write(f'### 시나리오 {i+1}\n\n')
            f.write(f'- currentRound: {r["scenario"]["currentRound"]}\n')
            f.write(f'- alreadyCards: {r["scenario"]["alreadyCards"]}\n')
            f.write(f'- rankings: {r["scenario"]["rankings"]}\n\n')
            f.write(f'**생성된 feedback:**\n> {r["feedback"]}\n\n')
            f.write(f'**위반 내용:**\n')
            for issue in r['result'].issues:
                f.write(f'- {issue}\n')
            f.write('\n---\n\n')

        if not any_failed:
            f.write('위반 사례 없음 — 모든 시나리오에서 카드 발동 조건과 일치하는 설명 생성됨.\n')

    print(f'\n리포트 저장됨: {report_path}')


if __name__ == '__main__':
    run()