"""
eval_scenario_ai.py — 한 시나리오에서 AI 예측(V2)이 실제로 얼마나 맞는지 전수 확인 (12주차)

게임에서 나올 수 있는 모든 상황을 다 넣어 본다.
  - 25라운드: (1라운드에 고른 카드) × (후보 3장 조합)
  - 50라운드: (1·25라운드에 고른 카드) × (후보 3장 조합)
각 상황에서
  - AI 선택   = 서버와 같은 모델·같은 입력으로 예측한 1위 카드
  - 실제 정답 = 그 카드를 골랐을 때의 최종 수익률 (남은 라운드 선택은 가능한 경우를 모두 평균)
을 비교한다. 모든 조합의 실제 결과는 게임 로직(run_game)으로 직접 계산한다.

실행 (backend/python_simulation 에서, Spring·Claude API 불필요):
  python3 eval_scenario_ai.py                 # 리먼 (2008-09-01)
  python3 eval_scenario_ai.py 2020-02-03      # 다른 시작일
"""
import os
import sys
from collections import Counter, defaultdict
from itertools import combinations, permutations

os.environ.setdefault('ANTHROPIC_API_KEY', 'test-dummy')   # 실제 호출 없음

import fastapi_server as fs
from game_logic import run_game, load_price_data, available_card_ids, CARDS, CARD_SELECT_ROUNDS

TIE = 0.005   # 수익률 차이가 이보다 작으면 같은 결과로 본다 (%p)


def indicators(closes):
    """Spring calcIndicators와 같은 계산 (수익률 %, 일별 수익률 표준편차, MDD %)"""
    ret = (closes[-1] - closes[0]) / closes[0] * 100
    daily = [(closes[i + 1] - closes[i]) / closes[i] * 100 for i in range(len(closes) - 1)]
    mean = sum(daily) / len(daily)
    vol = (sum((d - mean) ** 2 for d in daily) / len(daily)) ** 0.5
    peak, mdd = closes[0], 0.0
    for c in closes:
        peak = max(peak, c)
        mdd = min(mdd, (c - peak) / peak * 100)
    return round(ret, 4), round(vol, 4), round(mdd, 4)


def name(cid):
    return CARDS[cid]['name']


def main():
    start = sys.argv[1] if len(sys.argv) > 1 else '2008-09-01'
    fs.load_models()
    model, version = fs.select_v2_model(start)
    if model is None:
        print('❌ V2 모델 파일이 없습니다 (backend/data/simulation)')
        return

    price = load_price_data(start)
    pool = available_card_ids(price)
    print(f'\n시작일 {start} (1라운드 {price["dates"][0]}) · 모델 {version} · 사용 가능 카드 {len(pool)}장')

    # 1) 모든 4장 조합의 실제 최종 수익률
    actual = {}
    for combo in permutations(pool, 4):
        sel = dict(zip(CARD_SELECT_ROUNDS, combo))
        actual[combo] = run_game(start, sel, price_data=price)['final_return_rate']
    print(f'전체 조합 {len(actual):,}개 계산 완료 '
          f'(최고 {max(actual.values()):+.2f}% / 최저 {min(actual.values()):+.2f}%)')

    # prefix(앞에서 고른 카드들) → 그 뒤 가능한 모든 선택의 평균 수익률
    prefix_sum, prefix_cnt = defaultdict(float), Counter()
    for combo, rate in actual.items():
        for k in (2, 3):
            prefix_sum[combo[:k]] += rate
            prefix_cnt[combo[:k]] += 1
    value = {p: prefix_sum[p] / prefix_cnt[p] for p in prefix_sum}

    spx = price['close']['^SPX']
    for rnd, n_already in ((25, 1), (50, 2)):
        ret, vol, mdd = indicators(spx[:rnd])

        cases = []
        for already in permutations(pool, n_already):
            rest = [c for c in pool if c not in already]
            for cands in combinations(rest, 3):
                cases.append((already, cands))

        # 서버와 같은 입력으로 한 번에 예측
        feats = [fs.make_feature_v2(ret, vol, mdd, rnd, list(a), c) for a, cs in cases for c in cs]
        preds = model.predict(feats)

        n = len(cases)
        hit = worst = 0
        regret_ai = regret_rand = 0.0
        miss = Counter()
        picked, picked_hit = Counter(), Counter()
        gap_when_miss = []
        for i, (already, cands) in enumerate(cases):
            p = preds[i * 3:i * 3 + 3]
            ai = cands[max(range(3), key=lambda j: p[j])]
            vals = {c: value[already + (c,)] for c in cands}
            best_v, worst_v = max(vals.values()), min(vals.values())
            is_hit = vals[ai] >= best_v - TIE
            hit += is_hit
            worst += (vals[ai] <= worst_v + TIE) and (best_v - worst_v > TIE)
            regret_ai += best_v - vals[ai]
            regret_rand += best_v - sum(vals.values()) / 3
            picked[ai] += 1
            picked_hit[ai] += is_hit
            if not is_hit:
                best_c = max(vals, key=vals.get)
                miss[(ai, best_c)] += 1
                gap_when_miss.append(best_v - vals[ai])

        print('\n' + '=' * 72)
        print(f'[{rnd}라운드] 시장: 수익률 {ret:+.1f}% · 하루 등락 {vol:.2f} · 최대 낙폭 {mdd:.1f}%   (상황 {n:,}개)')
        print(f'  AI가 실제 1위를 고른 비율 : {hit / n * 100:5.1f}%   (아무거나 고르면 약 33%)')
        print(f'  AI가 실제 꼴찌를 고른 비율: {worst / n * 100:5.1f}%')
        print(f'  1위 카드 대비 평균 손해   : AI {regret_ai / n:.2f}%p / 아무거나 {regret_rand / n:.2f}%p')
        if gap_when_miss:
            print(f'  빗나갔을 때 평균 손해     : {sum(gap_when_miss) / len(gap_when_miss):.2f}%p '
                  f'(최대 {max(gap_when_miss):.2f}%p)')

        print('\n  AI가 고른 카드별 (고른 횟수 / 그중 실제 1위)')
        for c, k in picked.most_common():
            print(f'    {name(c):<10} {k:5d}회  적중 {picked_hit[c] / k * 100:5.1f}%')

        print('\n  자주 빗나간 경우 (AI 선택 → 실제 1위)')
        for (ai, best_c), k in miss.most_common(8):
            print(f'    {name(ai):<10} → {name(best_c):<10} {k:5d}회')

        # 이 시장에서 실제로 좋았던 카드 (후보에 있을 때 1위였던 비율)
        appear, top = Counter(), Counter()
        for already, cands in cases:
            vals = {c: value[already + (c,)] for c in cands}
            b = max(vals, key=vals.get)
            for c in cands:
                appear[c] += 1
            top[b] += 1
        print('\n  이 라운드에서 실제로 강했던 카드 (후보에 나왔을 때 1위였던 비율)')
        for c in sorted(appear, key=lambda c: -top[c] / appear[c])[:5]:
            print(f'    {name(c):<10} {top[c] / appear[c] * 100:5.1f}%')

    print('\n※ "실제 정답"은 게임이 끝난 뒤에만 알 수 있는 값입니다. AI는 그 라운드까지의 시장만 보고 예측합니다.')


if __name__ == '__main__':
    main()
