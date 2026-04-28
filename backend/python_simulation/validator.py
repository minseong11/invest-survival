"""
검증 모드: Python 결과 vs Java 결과 비교
"""
import json
import os
import requests
from game_logic import run_game

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), '..', 'data', 'simulation')
os.makedirs(OUTPUT_DIR, exist_ok=True)

JAVA_BASE_URL = "http://localhost:8080"

# =============================================
# Python 검증 모드
# =============================================
def run_python_validation(start_date: str, card_selections: dict,
                          output_file: str = 'result_python.json') -> dict:
    """
    Python 게임 로직 실행 후 JSON 저장
    :param start_date: "2008-09-02"
    :param card_selections: {1: 1, 25: 2, 50: 3, 75: 4}
    """
    result = run_game(start_date, card_selections)
    path = os.path.join(OUTPUT_DIR, output_file)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(f'Python 저장 완료: {path}')
    return result


# =============================================
# Java API 호출 검증 모드
# =============================================
def run_java_validation(start_date: str, card_selections: dict,
                        output_file: str = 'result_java.json') -> dict:
    """
    Java /game/validate API 호출 후 JSON 저장
    :param start_date: "2008-09-02"
    :param card_selections: {1: 1, 25: 2, 50: 3, 75: 4}
    """
    payload = {
        "startDate": start_date,
        "cardSelections": {str(k): v for k, v in card_selections.items()}
    }
    resp = requests.post(f"{JAVA_BASE_URL}/game/validate", json=payload)
    resp.raise_for_status()
    result = resp.json().get("data", resp.json())

    path = os.path.join(OUTPUT_DIR, output_file)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(f'Java 저장 완료: {path}')
    return result


# =============================================
# 비교 스크립트
# =============================================
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


# =============================================
# 검증 시나리오 5개
# =============================================
VALIDATION_CASES = [
    {'name': 'test1', 'start_date': '2008-09-02', 'cards': {1: 1,  25: 2,  50: 3,  75: 4}},
    {'name': 'test2', 'start_date': '2008-09-02', 'cards': {1: 8,  25: 1,  50: 2,  75: 3}},
    {'name': 'test3', 'start_date': '2008-09-02', 'cards': {1: 11, 25: 11, 50: 11, 75: 11}},
    {'name': 'test4', 'start_date': '2008-09-02', 'cards': {1: 9,  25: 9,  50: 9,  75: 9}},
    {'name': 'test5', 'start_date': '2008-10-15', 'cards': {1: 1,  25: 7,  50: 5,  75: 10}},
]

if __name__ == '__main__':
    import sys
    mode = sys.argv[1] if len(sys.argv) > 1 else 'python'

    print(f'=== 검증 시나리오 실행 (mode={mode}) ===\n')

    for case in VALIDATION_CASES:
        name = case['name']
        print(f"[{name}] start={case['start_date']} cards={case['cards']}")

        if mode == 'python':
            # Python 결과 생성
            result = run_python_validation(
                case['start_date'], case['cards'],
                output_file=f'result_python_{name}.json'
            )
            print(f"  최종 자산: {result['final_asset']:,}원  수익률: {result['final_return_rate']}%\n")

        elif mode == 'java':
            # Java API 결과 생성 (서버 실행 중이어야 함)
            result = run_java_validation(
                case['start_date'], case['cards'],
                output_file=f'result_java_{name}.json'
            )
            print(f"  최종 자산: {result.get('final_asset', '?'):,}  수익률: {result.get('final_return_rate', '?')}%\n")

        elif mode == 'compare':
            # Python vs Java 비교
            java_path   = os.path.join(OUTPUT_DIR, f'result_java_{name}.json')
            python_path = os.path.join(OUTPUT_DIR, f'result_python_{name}.json')
            if not os.path.exists(java_path):
                print(f'  Java 파일 없음: {java_path} (먼저 java 모드 실행)\n')
                continue
            if not os.path.exists(python_path):
                print(f'  Python 파일 없음: {python_path} (먼저 python 모드 실행)\n')
                continue
            compare_results(java_path, python_path)
            print()
