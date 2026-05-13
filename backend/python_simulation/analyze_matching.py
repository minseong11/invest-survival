"""
매칭 조건별 샘플 수 및 표준오차 정량 분석 (교수님 피드백 2-D)

측정 항목:
  1. SPX 매칭 범위(±5%, ±10%, ±15%)별 평균 매칭 샘플 수
  2. 매칭 샘플 수와 평균 수익률 추정의 표준오차 관계
  3. SPX_Volatility 조건 추가 시 매칭 수 감소율
  4. MDD 조건 추가 시 매칭 수 감소율
"""
import os
import warnings
warnings.filterwarnings('ignore')

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
from itertools import permutations

# ── 경로 설정 ──────────────────────────────────────────────
DATA_DIR  = os.path.join(os.path.dirname(__file__), '..', 'data', 'simulation')
DATA_PATH = os.path.join(DATA_DIR, 'training_data_v15.csv')
OUT_DIR   = os.path.join(DATA_DIR, 'analysis')
os.makedirs(OUT_DIR, exist_ok=True)

CARD_SELECT_ROUNDS = [1, 25, 50, 75]
ALL_CARD_IDS       = list(range(1, 12))

CARD_ROUND_COLS = [
    f'Card{i}_Round{r}'
    for i in range(1, 12)
    for r in CARD_SELECT_ROUNDS
]

# 분석 기준 시장 (리먼브라더스 폭락장)
TARGET_SPX_RETURN = -30.0
TARGET_SPX_VOL    = 3.5
TARGET_MDD        = -35.0   # MDD 분석용 기준값 (추정)

SPX_TOLERANCES  = [5.0, 10.0, 15.0]
VOL_TOLERANCES  = [0.5, 1.0, 1.5]
MDD_TOLERANCES  = [5.0, 10.0, 15.0]


# ── MDD 계산 ───────────────────────────────────────────────
def calc_mdd_from_returns(returns: pd.Series) -> float:
    """
    누적 수익률 시리즈로부터 MDD(최대낙폭률) 계산
    returns: 각 라운드의 수익률(%) 시리즈
    """
    cumulative = (1 + returns / 100).cumprod()
    rolling_max = cumulative.cummax()
    drawdown = (cumulative - rolling_max) / rolling_max * 100
    return drawdown.min()


def add_mdd_column(df: pd.DataFrame) -> pd.DataFrame:
    """
    training_data_v15.csv에 SPX_MDD 컬럼 추가
    현재 데이터에 라운드별 수익률이 없으므로
    SPX_Return과 SPX_Volatility로 MDD를 근사 추정
    공식: MDD ≈ SPX_Return - 1.5 * SPX_Volatility (폭락장 근사)
    """
    if 'SPX_MDD' not in df.columns:
        # 근사식: 수익률이 낮고 변동성이 클수록 MDD 커짐
        df = df.copy()
        df['SPX_MDD'] = df['SPX_Return'] - 1.5 * df['SPX_Volatility']
    return df


# ── 매칭 함수 ──────────────────────────────────────────────
def get_match_count(df: pd.DataFrame,
                    card_selections: dict,
                    spx_return: float,
                    spx_tol: float,
                    spx_vol: float = None,
                    vol_tol: float = None,
                    mdd: float = None,
                    mdd_tol: float = None) -> int:
    mask = pd.Series([True] * len(df), index=df.index)

    # 카드 조합 매칭
    for round_num, card_id in card_selections.items():
        col = f'Card{card_id}_Round{round_num}'
        if col in df.columns:
            mask &= (df[col] == 1)

    # SPX 수익률 범위
    mask &= df['SPX_Return'].between(spx_return - spx_tol,
                                      spx_return + spx_tol)

    # 변동성 범위 (선택)
    if spx_vol is not None and vol_tol is not None and 'SPX_Volatility' in df.columns:
        mask &= df['SPX_Volatility'].between(spx_vol - vol_tol,
                                              spx_vol + vol_tol)

    # MDD 범위 (선택)
    if mdd is not None and mdd_tol is not None and 'SPX_MDD' in df.columns:
        mask &= df['SPX_MDD'].between(mdd - mdd_tol, mdd + mdd_tol)

    return int(mask.sum())


def sample_permutations(n: int = 500) -> list:
    """전체 7920개 순열 중 n개 샘플링"""
    all_perms = list(permutations(ALL_CARD_IDS, 4))
    np.random.seed(42)
    idx = np.random.choice(len(all_perms), size=min(n, len(all_perms)), replace=False)
    sampled = [all_perms[i] for i in idx]
    return [
        {1: c[0], 25: c[1], 50: c[2], 75: c[3]}
        for c in sampled
    ]


# ── 분석 1: SPX 범위별 평균 매칭 수 ───────────────────────
def analyze_spx_tolerance(df: pd.DataFrame, combos: list):
    print('\n' + '=' * 60)
    print(' [분석 1] SPX 매칭 범위별 평균 매칭 샘플 수')
    print('=' * 60)
    print(f' 기준 시장: SPX {TARGET_SPX_RETURN:+.0f}%, 변동성 {TARGET_SPX_VOL}')
    print(f' 샘플 순열 수: {len(combos):,}개\n')

    results = {}
    for tol in SPX_TOLERANCES:
        counts = [
            get_match_count(df, sel, TARGET_SPX_RETURN, tol)
            for sel in combos
        ]
        counts = np.array(counts)
        avg   = counts.mean()
        med   = np.median(counts)
        zero  = (counts == 0).sum()
        ge30  = (counts >= 30).sum()
        ge50  = (counts >= 50).sum()

        results[tol] = {'avg': avg, 'med': med, 'zero': zero,
                        'ge30': ge30, 'ge50': ge50, 'counts': counts}

        print(f' ±{tol:.0f}%  평균: {avg:.1f}건  중앙값: {med:.0f}건  '
              f'0건: {zero}개  ≥30건: {ge30}개  ≥50건: {ge50}개')

    return results


# ── 분석 2: 샘플 수 vs 표준오차 관계 ──────────────────────
def analyze_se_vs_sample(df: pd.DataFrame):
    print('\n' + '=' * 60)
    print(' [분석 2] 샘플 수와 평균 수익률 표준오차 관계')
    print('=' * 60)

    # ±15% 범위에서 매칭 수 충분한 조합 수집
    combos_all = sample_permutations(n=200)
    data_points = []

    for sel in combos_all:
        mask = pd.Series([True] * len(df), index=df.index)
        for round_num, card_id in sel.items():
            col = f'Card{card_id}_Round{round_num}'
            if col in df.columns:
                mask &= (df[col] == 1)
        mask &= df['SPX_Return'].between(TARGET_SPX_RETURN - 15,
                                          TARGET_SPX_RETURN + 15)
        sub = df[mask]['Final_Return']
        n = len(sub)
        if n >= 5:
            se = sub.std() / np.sqrt(n)
            data_points.append({'n': n, 'se': se, 'mean': sub.mean()})

    if not data_points:
        print(' ⚠️  분석 가능한 데이터 없음')
        return []

    dp = pd.DataFrame(data_points).sort_values('n')

    print(f'\n {"샘플수":>6}  {"표준오차":>8}  {"평균수익률":>10}')
    print(' ' + '-' * 32)

    # 구간별 대표값 출력
    bins = [5, 10, 20, 30, 50, 100, 200, 500]
    for i in range(len(bins) - 1):
        sub = dp[(dp['n'] >= bins[i]) & (dp['n'] < bins[i+1])]
        if len(sub) > 0:
            print(f' {bins[i]:>4}~{bins[i+1]-1:<3}  '
                  f'{sub["se"].mean():>7.3f}%  '
                  f'{sub["mean"].mean():>+9.2f}%  '
                  f'({len(sub)}개 조합)')

    print(f'\n 표준편차(Final_Return 전체): {df["Final_Return"].std():.2f}%')
    print(f' → 신뢰할 만한 평균 추정을 위해')
    print(f'   SE < 1.5%p 기준: 약 {int((df["Final_Return"].std()/1.5)**2)+1}건 이상 필요')
    print(f'   SE < 1.0%p 기준: 약 {int((df["Final_Return"].std()/1.0)**2)+1}건 이상 필요')

    return data_points


# ── 분석 3: 변동성 조건 추가 시 감소율 ────────────────────
def analyze_vol_reduction(df: pd.DataFrame, combos: list):
    print('\n' + '=' * 60)
    print(' [분석 3] SPX_Volatility 조건 추가 시 매칭 수 감소율')
    print('=' * 60)
    print(f' 기준: SPX ±10% + Volatility {TARGET_SPX_VOL} ±X\n')

    base_counts = np.array([
        get_match_count(df, sel, TARGET_SPX_RETURN, 10.0)
        for sel in combos
    ])
    base_avg = base_counts.mean()
    print(f' 기준 (SPX ±10%만):  평균 {base_avg:.1f}건')

    results = {}
    for tol in VOL_TOLERANCES:
        counts = np.array([
            get_match_count(df, sel, TARGET_SPX_RETURN, 10.0,
                            spx_vol=TARGET_SPX_VOL, vol_tol=tol)
            for sel in combos
        ])
        avg      = counts.mean()
        ratio    = avg / base_avg * 100 if base_avg > 0 else 0
        reduce   = 100 - ratio
        ge30     = (counts >= 30).sum()

        results[tol] = {'avg': avg, 'ratio': ratio, 'ge30': ge30}
        print(f' Vol ±{tol}:  평균 {avg:.1f}건  '
              f'(기준 대비 {ratio:.1f}%, 감소율 {reduce:.1f}%)  '
              f'≥30건: {ge30}개')

    return results


# ── 분석 4: MDD 조건 추가 시 감소율 ───────────────────────
def analyze_mdd_reduction(df: pd.DataFrame, combos: list):
    print('\n' + '=' * 60)
    print(' [분석 4] SPX_MDD 조건 추가 시 매칭 수 감소율')
    print('=' * 60)

    if 'SPX_MDD' not in df.columns:
        print(' ⚠️  SPX_MDD 컬럼 없음 — 근사값으로 계산합니다.')
        df = add_mdd_column(df)

    mdd_vals = df['SPX_MDD']
    print(f' SPX_MDD 분포: 평균 {mdd_vals.mean():.1f}%  '
          f'표준편차 {mdd_vals.std():.1f}%  '
          f'범위 {mdd_vals.min():.1f}% ~ {mdd_vals.max():.1f}%')

    # 기준 MDD: 데이터의 중앙값 근처
    target_mdd = mdd_vals.median()
    print(f' 기준 MDD: {target_mdd:.1f}%  (기준: SPX ±10%)\n')

    base_counts = np.array([
        get_match_count(df, sel, TARGET_SPX_RETURN, 10.0)
        for sel in combos
    ])
    base_avg = base_counts.mean()

    results = {}
    for tol in MDD_TOLERANCES:
        counts = np.array([
            get_match_count(df, sel, TARGET_SPX_RETURN, 10.0,
                            mdd=target_mdd, mdd_tol=tol)
            for sel in combos
        ])
        avg    = counts.mean()
        ratio  = avg / base_avg * 100 if base_avg > 0 else 0
        reduce = 100 - ratio
        ge30   = (counts >= 30).sum()

        results[tol] = {'avg': avg, 'ratio': ratio, 'ge30': ge30}
        print(f' MDD ±{tol:.0f}%:  평균 {avg:.1f}건  '
              f'(기준 대비 {ratio:.1f}%, 감소율 {reduce:.1f}%)  '
              f'≥30건: {ge30}개')

    return results


# ── 시각화 ─────────────────────────────────────────────────
def plot_results(spx_results: dict, vol_results: dict,
                 mdd_results: dict, se_data: list):
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    fig.suptitle('Matching Condition Analysis', fontsize=14, fontweight='bold')

    # 1. SPX 범위별 평균 매칭 수
    ax = axes[0, 0]
    tols  = [f'+-{int(t)}%' for t in SPX_TOLERANCES]
    avgs  = [spx_results[t]['avg'] for t in SPX_TOLERANCES]
    ge30  = [spx_results[t]['ge30'] for t in SPX_TOLERANCES]
    bars  = ax.bar(tols, avgs, color=['#e74c3c', '#f39c12', '#2ecc71'])
    ax.axhline(y=30, color='blue', linestyle='--', alpha=0.7, label='n=30 (CLT)')
    ax.axhline(y=50, color='purple', linestyle='--', alpha=0.7, label='n=50')
    for bar, g in zip(bars, ge30):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.3,
                f'>=30: {g}', ha='center', va='bottom', fontsize=9)
    ax.set_title('SPX Tolerance vs Avg Match Count')
    ax.set_ylabel('Avg Match Count')
    ax.legend(fontsize=8)
    ax.grid(axis='y', alpha=0.3)

    # 2. 샘플 수 vs 표준오차
    ax = axes[0, 1]
    if se_data:
        dp = pd.DataFrame(se_data)
        ax.scatter(dp['n'], dp['se'], alpha=0.5, s=20, color='steelblue')
        ns = np.linspace(dp['n'].min(), dp['n'].max(), 100)
        std_val = dp['se'].mean() * np.sqrt(dp['n'].mean())
        ax.plot(ns, std_val / np.sqrt(ns), 'r-', label='SE = std/sqrt(n)', linewidth=2)
        ax.axhline(y=1.5, color='orange', linestyle='--', alpha=0.7, label='SE=1.5%')
        ax.axhline(y=1.0, color='green', linestyle='--', alpha=0.7, label='SE=1.0%')
        ax.set_title('Sample Size vs Standard Error')
        ax.set_xlabel('Sample Size (n)')
        ax.set_ylabel('Standard Error (%)')
        ax.legend(fontsize=8)
        ax.grid(alpha=0.3)

    # 3. 변동성 조건 추가 시 감소율
    ax = axes[1, 0]
    v_tols  = [f'+-{t}' for t in VOL_TOLERANCES]
    v_ratios = [vol_results[t]['ratio'] for t in VOL_TOLERANCES]
    ax.bar(v_tols, v_ratios, color=['#3498db', '#9b59b6', '#1abc9c'])
    ax.axhline(y=100, color='gray', linestyle='--', alpha=0.5, label='Base (SPX +-10%)')
    ax.set_title('Volatility Condition: Match Count Ratio (%)')
    ax.set_xlabel('Volatility Tolerance')
    ax.set_ylabel('Ratio vs Base (%)')
    ax.legend(fontsize=8)
    ax.grid(axis='y', alpha=0.3)

    # 4. MDD 조건 추가 시 감소율
    ax = axes[1, 1]
    m_tols   = [f'+-{int(t)}%' for t in MDD_TOLERANCES]
    m_ratios = [mdd_results[t]['ratio'] for t in MDD_TOLERANCES]
    ax.bar(m_tols, m_ratios, color=['#e67e22', '#e74c3c', '#c0392b'])
    ax.axhline(y=100, color='gray', linestyle='--', alpha=0.5, label='Base (SPX +-10%)')
    ax.set_title('MDD Condition: Match Count Ratio (%)')
    ax.set_xlabel('MDD Tolerance')
    ax.set_ylabel('Ratio vs Base (%)')
    ax.legend(fontsize=8)
    ax.grid(axis='y', alpha=0.3)

    plt.tight_layout()
    out_path = os.path.join(OUT_DIR, 'matching_analysis.png')
    plt.savefig(out_path, dpi=150, bbox_inches='tight')
    print(f'\n 그래프 저장: {out_path}')
    plt.close()


# ── 종합 요약 ──────────────────────────────────────────────
def print_summary(spx_results: dict, vol_results: dict, mdd_results: dict):
    print('\n' + '=' * 60)
    print(' [종합 요약] 매칭 조건 설계 권고')
    print('=' * 60)

    # CLT 기준 30건 이상 확보되는 최소 SPX 범위 찾기
    best_spx = None
    for tol in SPX_TOLERANCES:
        if spx_results[tol]['avg'] >= 30:
            best_spx = tol
            break

    if best_spx:
        print(f'\n ✅ SPX ±{best_spx:.0f}% 범위에서 평균 {spx_results[best_spx]["avg"]:.1f}건 확보')
        print(f'    → CLT 기준 30건 충족')
    else:
        print(f'\n ⚠️  SPX ±15% 범위에서도 평균 {spx_results[15.0]["avg"]:.1f}건')
        print(f'    → 데이터 추가 확장 필요')

    # 변동성 추가 권고
    v05 = vol_results.get(0.5, {})
    v10 = vol_results.get(1.0, {})
    print(f'\n 변동성 ±0.5 추가 시: 매칭 수 {v05.get("ratio", 0):.1f}% 수준 유지')
    print(f' 변동성 ±1.0 추가 시: 매칭 수 {v10.get("ratio", 0):.1f}% 수준 유지')

    if v05.get('avg', 0) >= 10:
        print(f' → ✅ 변동성 ±0.5 추가 가능 (평균 {v05["avg"]:.1f}건)')
    else:
        print(f' → ⚠️  변동성 추가 시 데이터 부족 우려')

    # 계층적 매칭 권고
    print(f'\n 📋 계층적 매칭 fallback 설계 권고:')
    print(f'   1단계: SPX ±5%  + Vol ±0.5  → 충분하면 사용')
    print(f'   2단계: SPX ±10% + Vol ±1.0  → 1단계 부족 시')
    print(f'   3단계: SPX ±15% 만           → 2단계도 부족 시')


# ── 메인 ───────────────────────────────────────────────────
def main():
    if not os.path.exists(DATA_PATH):
        print(f'❌ 학습 데이터 없음: {DATA_PATH}')
        print('먼저 monte_carlo.py를 실행하세요.')
        return

    print('=' * 60)
    print(' 매칭 조건 정량 분석 (교수님 피드백 2-D)')
    print('=' * 60)

    df = pd.read_csv(DATA_PATH)
    print(f' 데이터 로드: {len(df):,}건')
    print(f' 컬럼: {list(df.columns[:5])} ...')

    # MDD 컬럼 추가 (없는 경우 근사)
    df = add_mdd_column(df)

    # 순열 샘플링 (500개)
    print(f'\n 순열 샘플링 중... (전체 7,920개 중 500개)')
    combos = sample_permutations(n=500)
    print(f' 완료: {len(combos)}개')

    # 분석 실행
    spx_results = analyze_spx_tolerance(df, combos)
    se_data     = analyze_se_vs_sample(df)
    vol_results = analyze_vol_reduction(df, combos)
    mdd_results = analyze_mdd_reduction(df, combos)

    # 종합 요약
    print_summary(spx_results, vol_results, mdd_results)

    # 시각화
    print('\n 그래프 생성 중...')
    plot_results(spx_results, vol_results, mdd_results, se_data)

    print('\n✅ 분석 완료!')


if __name__ == '__main__':
    main()
