"""
export_fixed_ranking.py — 고정 순위(평소 순위)를 Flutter 상수 파일로 내보낸다.

고정 순위 = 학습 데이터(training_data_v2.csv, 2006~2018)에서
            (라운드, 카드)별 Card_Contribution 평균. 시장 지표는 보지 않음.
            eval_test_period.py의 '고정 순위 기준선'과 같은 계산(load_fixed_baseline)을 그대로 사용.

게임 화면 25·50라운드에서 V2 예측 옆에 "평소 순위"로 함께 보여준다.

실행 (backend/python_simulation 에서):
  python3 export_fixed_ranking.py
출력:
  frontEnd/lib/models/fixed_ranking.dart  (덮어씀)
"""
import os
from datetime import date

from eval_test_period import load_fixed_baseline, TRAIN_DATA, EVAL_ROUNDS

OUT_DART = os.path.join(os.path.dirname(__file__), '..', '..', 'frontEnd', 'lib', 'models', 'fixed_ranking.dart')

TEMPLATE = """// 자동 생성 파일 — 직접 수정하지 말 것
// 생성: backend/python_simulation/export_fixed_ranking.py ({today})
// 출처: training_data_v2.csv {rows:,}행 (게임 시작일 최대 {max_start})
//
// 고정 순위(평소 순위) = 학습 기간에 이 라운드에서 각 카드가 낸 평균 기여도(%p).
// 지금 시장은 보지 않는다. 중간보고서 4장 평가의 '고정 순위' 기준선과 같은 값.

class FixedRanking {{
  // 라운드 → {{카드 ID: 평균 기여도(%p)}}
  static const Map<int, Map<int, double>> means = {{
{body}
  }};

  // 후보 카드를 평소 순위(평균 기여도 높은 순)로 정렬. 값이 없으면 빈 목록 → 화면에 표시 안 함
  static List<int> order(int round, List<int> cards) {{
    final m = means[round];
    if (m == null || cards.isEmpty || !cards.every(m.containsKey)) return const [];
    final sorted = List<int>.from(cards)..sort((a, b) => m[b]!.compareTo(m[a]!));
    return sorted;
  }}
}}
"""


def main():
    base, info = load_fixed_baseline(TRAIN_DATA)
    if not base:
        print(f'❌ 고정 순위 계산 실패: {info}')
        return
    lines = []
    for r in EVAL_ROUNDS:
        cards = sorted(c for (rr, c) in base if rr == r)
        items = ', '.join(f'{c}: {base[(r, c)]:.4f}' for c in cards)
        lines.append(f'    {r}: {{{items}}},')
    text = TEMPLATE.format(today=date.today(), rows=info['rows'], max_start=info['max_start'], body='\n'.join(lines))
    with open(OUT_DART, 'w', encoding='utf-8') as f:
        f.write(text)
    print(f'✅ 저장: {os.path.normpath(OUT_DART)}')
    for r in EVAL_ROUNDS:
        order = sorted((c for (rr, c) in base if rr == r), key=lambda c: -base[(r, c)])
        print(f'  {r}라운드 평소 순위: {order}')


if __name__ == '__main__':
    main()
