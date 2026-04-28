"""
검증 모드: Python 결과 vs Java 결과 비교
"""
import json
import os
from game_logic import run_game

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), '..', 'data', 'simulation')
os.makedirs(OUTPUT_DIR, exist_ok=True)


def run_validation(start_date: str, card_selections: dict,
                   initial_asset: int = 10_000_000,
                   output_file: str = 'result_python.json') -> dict:
    """
    사용자 지정 입력으로 게임 실행 후 JSON 저장
    :param start_date: "2008-09-02"
    :param card_selections: {1: 1, 25: 2, 50: 3, 75: 4}
    :param output_file: 저장할 파일명
    """
    result = run_game(start_date, card_selections, initial_asset)
    path = os.path.join(OUTPUT_DIR, output_file)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(f'저장 완료: {path}')
    return result


def compare_results(java_file: str, python_file: str, tolerance: float = 1.0) -> bool:
    """Java 결과와 Python 결과 비교"""
    with open(java_file, encoding='utf-8') as f1:
        java = json.load(f1)
    with open(python_file, encoding='utf-8') as f2:
        python = json.load(f2)

    mismatches = []
    for j, p in zip(java['rounds'], python['rounds']):
        if abs(j['roundAsset'] - p['roundAsset']) > tolerance:
            mismatches.append({
                'round': j['round'], 'field': 'roundAsset',
                'java': j['roundAsset'], 'python': p['roundAsset']
            })
        if sorted(j['triggeredCards']) != sorted(p['triggeredCards']):
            mismatches.append({
                'round': j['round'], 'field': 'triggeredCards',
                'java': j['triggeredCards'], 'python': p['triggeredCards']
            })

    if mismatches:
        print(f'❌ {len(mismatches)}건 불일치 발견')
        for m in mismatches[:10]:
            print(f"  Round {m['round']} {m['field']}: java={m['java']}, python={m['python']}")
        return False

    print('✅ 모든 라운드 결과 일치')
    return True


# 검증 시나리오 5개
VALIDATION_CASES = [
    {'name': 'test1', 'start_date': '2008-09-02', 'cards': {1: 1,  25: 2,  50: 3,  75: 4}},
    {'name': 'test2', 'start_date': '2008-09-02', 'cards': {1: 8,  25: 1,  50: 2,  75: 3}},
    {'name': 'test3', 'start_date': '2008-09-02', 'cards': {1: 11, 25: 11, 50: 11, 75: 11}},
    {'name': 'test4', 'start_date': '2008-09-02', 'cards': {1: 9,  25: 9,  50: 9,  75: 9}},
    {'name': 'test5', 'start_date': '2008-10-15', 'cards': {1: 1,  25: 7,  50: 5,  75: 10}},
]

if __name__ == '__main__':
    print('=== 검증 시나리오 실행 ===\n')
    for case in VALIDATION_CASES:
        print(f"[{case['name']}] start={case['start_date']} cards={case['cards']}")
        result = run_validation(
            case['start_date'],
            case['cards'],
            output_file=f"result_python_{case['name']}.json"
        )
        print(f"  최종 자산: {result['final_asset']:,}원  수익률: {result['final_return_rate']}%\n")
