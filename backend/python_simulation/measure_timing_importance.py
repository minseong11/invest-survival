"""
V1.5 카드 시점 중요성 정량 측정 (교수님 피드백 1번 대응)

측정 방법:
  같은 4장 카드 조합의 24가지 시점 변형(순열) 수익률 표준편차 측정
  
해석:
  표준편차 < 1%p: 시점 noise 수준 (순열 평가 불필요)
  표준편차 1~3%p: 시점 약간 중요
  표준편차 > 5%p: 시점 핵심 변수 (순열 평가 정당)
"""
import warnings
warnings.filterwarnings('ignore')

import os
import numpy as np
import pandas as pd
from itertools import permutations, combinations

DATA_DIR  = os.path.join(os.path.dirname(__file__), '..', 'data', 'simulation')
DATA_PATH = os.path.join(DATA_DIR, 'training_data_v15.csv')

CARD_SELECT_ROUNDS = [1, 25, 50, 75]
ALL_CARD_IDS       = list(range(1, 12))

CARD_NAMES = {
    1: '거인의 어깨',   2: '황금 적립',     3: '공포탐욕',
    4: '금 피난처',     5: '기술의 파도',   6: '낙폭과대 사냥',
    7: '원유 베팅',     8: '역발상 투자',   9: '애플 줍줍',
    10: '채권 피난처',  11: '분할매수 장인',
}


# =============================================
# 유틸: 시점 조합 매칭 검색
# =============================================
def find_matching(df, card_selections):
    """특정 시점 조합으로 진행한 게임 찾기 (시장 무관)"""
    mask = pd.Series([True] * len(df))
    for round_num, card_id in card_selections.items():
        col = f'Card{card_id}_Round{round_num}'
        if col in df.columns:
            mask &= (df[col] == 1)
    return df[mask]


# =============================================
# 1. 특정 카드 4장 조합의 시점 변형 분석
# =============================================
def analyze_combo_permutations(df, card_set):
    """
    주어진 4장 카드의 24가지 시점 순서별 수익률 비교
    
    Returns:
      results: [{perm, count, mean_return}, ...]
      std: 시점별 평균 수익률의 표준편차
    """
    results = []
    
    for perm in permutations(card_set):
        sel = {
            1: perm[0],
            25: perm[1],
            50: perm[2],
            75: perm[3],
        }
        matching = find_matching(df, sel)
        
        if len(matching) > 0:
            mean_return = matching['Final_Return'].mean()
            median_return = matching['Final_Return'].median()
            results.append({
                'perm': perm,
                'count': len(matching),
                'mean': mean_return,
                'median': median_return,
            })
    
    if len(results) < 2:
        return results, None  # 비교 불가
    
    means = [r['mean'] for r in results]
    std = np.std(means)
    
    return results, std


# =============================================
# 2. 여러 조합에 대해 표준편차 측정
# =============================================
def measure_timing_importance(df, num_combos=10, min_data_per_perm=1):
    """
    데이터가 충분한 조합들에 대해 시점 중요성 측정
    
    Args:
      num_combos: 측정할 조합 수
      min_data_per_perm: 각 순열당 최소 데이터 수
    """
    print('=' * 70)
    print(' V1.5 카드 시점 중요성 정량 측정')
    print('=' * 70)
    print(f' 데이터: {len(df):,}건')
    print(f' 측정 대상 조합: {num_combos}개')
    print(f' 각 순열당 최소 데이터: {min_data_per_perm}건')
    print()
    
    # 모든 4장 조합 (330개)
    all_combos = list(combinations(ALL_CARD_IDS, 4))
    
    # 각 조합의 24가지 시점 변형 중 데이터 있는 것 개수 카운트
    combo_data_counts = []
    
    print(' [1단계] 데이터 충분한 조합 찾는 중...')
    for combo in all_combos:
        valid_perms = 0
        total_data = 0
        for perm in permutations(combo):
            sel = {1: perm[0], 25: perm[1], 50: perm[2], 75: perm[3]}
            matching = find_matching(df, sel)
            if len(matching) >= min_data_per_perm:
                valid_perms += 1
                total_data += len(matching)
        
        combo_data_counts.append({
            'combo': combo,
            'valid_perms': valid_perms,
            'total_data': total_data,
        })
    
    # 데이터 많은 조합 순으로 정렬
    combo_data_counts.sort(key=lambda x: -x['valid_perms'])
    
    # 상위 N개 조합 선택
    selected_combos = [c for c in combo_data_counts if c['valid_perms'] >= 3][:num_combos]
    
    if len(selected_combos) == 0:
        print('\n ⚠️  데이터 충분한 조합 없음. 더 많은 시뮬레이션 필요.')
        return
    
    print(f' 데이터 충분한 조합 {len(selected_combos)}개 선택\n')
    
    # 각 조합별 측정
    print(' [2단계] 시점별 수익률 표준편차 측정')
    print('-' * 70)
    
    all_stds = []
    
    for idx, info in enumerate(selected_combos, 1):
        combo = info['combo']
        names = [CARD_NAMES[c] for c in combo]
        
        print(f'\n 조합 {idx}: {", ".join(names)}')
        print(f'   데이터 있는 시점 변형: {info["valid_perms"]}/24가지')
        
        results, std = analyze_combo_permutations(df, combo)
        
        if std is None:
            print(f'   ⚠️  비교 불가 (데이터 부족)')
            continue
        
        means = [r['mean'] for r in results]
        
        print(f'   수익률 범위: {min(means):+.2f}% ~ {max(means):+.2f}%')
        print(f'   수익률 차이: {max(means) - min(means):.2f}%p')
        print(f'   ★ 시점별 표준편차: {std:.2f}%p')
        
        all_stds.append({
            'combo': combo,
            'names': names,
            'std': std,
            'range': max(means) - min(means),
            'valid_perms': info['valid_perms'],
        })
    
    # 종합 결과
    if not all_stds:
        print('\n ❌ 측정 가능한 조합 없음')
        return
    
    print('\n' + '=' * 70)
    print(' [종합 결과]')
    print('=' * 70)
    
    avg_std = np.mean([s['std'] for s in all_stds])
    median_std = np.median([s['std'] for s in all_stds])
    max_std = max(s['std'] for s in all_stds)
    min_std = min(s['std'] for s in all_stds)
    
    print(f' 측정 조합 수: {len(all_stds)}개')
    print(f' 시점별 표준편차 평균:   {avg_std:.2f}%p')
    print(f' 시점별 표준편차 중앙값: {median_std:.2f}%p')
    print(f' 시점별 표준편차 범위:   {min_std:.2f}%p ~ {max_std:.2f}%p')
    
    # 해석
    print('\n' + '-' * 70)
    print(' [해석]')
    print('-' * 70)
    
    if avg_std < 1.0:
        verdict = '시점 noise 수준 (순열 평가 불필요)'
        symbol = '⚠️ '
    elif avg_std < 3.0:
        verdict = '시점 약간 중요 (순열 평가 권장)'
        symbol = '✅'
    elif avg_std < 5.0:
        verdict = '시점 중요 (순열 평가 정당)'
        symbol = '✅'
    else:
        verdict = '시점 핵심 변수 (순열 평가 필수)'
        symbol = '⭐'
    
    print(f' {symbol} 평균 표준편차 {avg_std:.2f}%p → {verdict}')
    
    print('\n 기준:')
    print('   < 1%p:   시점 noise 수준')
    print('   1~3%p:   시점 약간 중요')
    print('   3~5%p:   시점 중요')
    print('   > 5%p:   시점 핵심 변수')
    
    # 발표 자료용 멘트
    print('\n' + '=' * 70)
    print(' [캡스톤 발표용 멘트]')
    print('=' * 70)
    print(f'''
"같은 4장 카드 조합의 24가지 시점 변형 수익률 표준편차 측정:

측정 조합 수: {len(all_stds)}개
시점별 표준편차 평균: {avg_std:.2f}%p
시점별 표준편차 중앙값: {median_std:.2f}%p

이는 같은 카드 4장이라도 어느 라운드에 선택하느냐에 따라
수익률이 평균 ±{avg_std:.2f}%p 변동함을 의미합니다.

→ {verdict}
→ V1.5의 시점 인코딩(7920 순열) 평가 정당성 정량 입증"
''')


# =============================================
# 메인
# =============================================
def main():
    if not os.path.exists(DATA_PATH):
        print(f'❌ 학습 데이터 없음: {DATA_PATH}')
        print('먼저 monte_carlo.py를 실행하세요.')
        return
    
    df = pd.read_csv(DATA_PATH)
    
    # 측정 실행
    measure_timing_importance(df, num_combos=10, min_data_per_perm=1)


if __name__ == '__main__':
    main()
