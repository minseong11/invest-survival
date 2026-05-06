"""
V1.5 시뮬레이션 데이터 분포 분석 + 시각화 (교수님 피드백 5번 반영)

분석 내용:
  1. Final_Return 통계 (평균, 중앙값, 표준편차, 최소, 최대, 양수/음수 비율)
  2. 시작 날짜별 결과 분포
  3. 카드별 평균 수익률
  4. 시각화:
     - Final_Return 히스토그램
     - SPX_Return vs Final_Return 산점도
     - 시작 날짜별 박스 플롯
     - 카드별 평균 수익률 막대 그래프
"""
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib

# Mac 한글 폰트 설정
matplotlib.rcParams['font.family'] = 'AppleGothic'
matplotlib.rcParams['axes.unicode_minus'] = False

DATA_DIR  = os.path.join(os.path.dirname(__file__), '..', 'data', 'simulation')
DATA_PATH = os.path.join(DATA_DIR, 'training_data_v15.csv')
OUTPUT_DIR = os.path.join(DATA_DIR, 'analysis')
os.makedirs(OUTPUT_DIR, exist_ok=True)

CARD_SELECT_ROUNDS = [1, 25, 50, 75]

CARD_NAMES = {
    1: '거인의 어깨',   2: '황금 적립',     3: '공포탐욕',
    4: '금 피난처',     5: '기술의 파도',   6: '낙폭과대 사냥',
    7: '원유 베팅',     8: '역발상 투자',   9: '애플 줍줍',
    10: '채권 피난처',  11: '분할매수 장인',
}


# =============================================
# 1. 기본 통계 출력
# =============================================
def print_statistics(df: pd.DataFrame):
    """Final_Return 기본 통계"""
    ret = df['Final_Return']
    
    print('=' * 60)
    print(' [1] Final_Return 기본 통계')
    print('=' * 60)
    print(f' 총 시뮬레이션:  {len(df):,}건')
    print(f' 평균:           {ret.mean():+.4f}%')
    print(f' 중앙값:         {ret.median():+.4f}%')
    print(f' 표준편차:       {ret.std():.4f}%')
    print(f' 최솟값:         {ret.min():+.4f}%')
    print(f' 최댓값:         {ret.max():+.4f}%')
    
    positive = (ret > 0).sum()
    negative = (ret <= 0).sum()
    print(f'\n 수익 게임:      {positive:,}건 ({positive/len(df)*100:.1f}%)')
    print(f' 손실 게임:      {negative:,}건 ({negative/len(df)*100:.1f}%)')
    
    print(f'\n SPX_Return 평균:     {df["SPX_Return"].mean():+.4f}%')
    print(f' SPX_Volatility 평균: {df["SPX_Volatility"].mean():.4f}')


# =============================================
# 2. 시작 날짜별 분포
# =============================================
def analyze_by_start_date(df: pd.DataFrame):
    """시작 날짜(월별)에 따른 결과 분포"""
    print('\n' + '=' * 60)
    print(' [2] 시작 날짜별 결과 분포 (월별)')
    print('=' * 60)
    
    df['start_date'] = pd.to_datetime(df['start_date'])
    df['year_month'] = df['start_date'].dt.to_period('M')
    
    monthly = df.groupby('year_month').agg(
        count=('Final_Return', 'count'),
        mean=('Final_Return', 'mean'),
        std=('Final_Return', 'std'),
        min=('Final_Return', 'min'),
        max=('Final_Return', 'max'),
    ).round(2)
    
    print(monthly.to_string())
    return monthly


# =============================================
# 3. 카드별 평균 수익률
# =============================================
def analyze_by_card(df: pd.DataFrame):
    """카드별 평균 수익률 (그 카드를 선택한 게임들의 평균)"""
    print('\n' + '=' * 60)
    print(' [3] 카드별 평균 수익률')
    print('=' * 60)
    
    card_stats = []
    for card_id in range(1, 12):
        # 카드 i가 어느 라운드에서든 선택된 게임 찾기
        cols = [f'Card{card_id}_Round{r}' for r in CARD_SELECT_ROUNDS]
        mask = df[cols].sum(axis=1) > 0
        selected_games = df[mask]
        
        if len(selected_games) > 0:
            card_stats.append({
                'card_id': card_id,
                'name': CARD_NAMES[card_id],
                'count': len(selected_games),
                'mean': selected_games['Final_Return'].mean(),
                'std': selected_games['Final_Return'].std(),
            })
    
    card_df = pd.DataFrame(card_stats)
    card_df_sorted = card_df.sort_values('mean', ascending=False)
    
    print(f'{"순위":<4} {"카드명":<15} {"선택 횟수":<10} {"평균 수익률":<12} {"표준편차"}')
    print('-' * 60)
    for rank, row in enumerate(card_df_sorted.itertuples(), 1):
        print(f'{rank:<4} {row.name:<15} {row.count:>6,}건  '
              f'{row.mean:>+8.2f}%   {row.std:>6.2f}%')
    
    return card_df


# =============================================
# 4. 시각화
# =============================================
def plot_final_return_histogram(df: pd.DataFrame):
    """Final_Return 히스토그램"""
    plt.figure(figsize=(10, 6))
    plt.hist(df['Final_Return'], bins=50, color='steelblue', edgecolor='black', alpha=0.7)
    plt.axvline(x=0, color='red', linestyle='--', linewidth=2, label='0%')
    plt.axvline(x=df['Final_Return'].mean(), color='orange', linestyle='--', 
                linewidth=2, label=f'평균 {df["Final_Return"].mean():+.2f}%')
    plt.xlabel('Final Return (%)', fontsize=12)
    plt.ylabel('게임 수', fontsize=12)
    plt.title('Final_Return 분포 (히스토그램)', fontsize=14, fontweight='bold')
    plt.legend(fontsize=11)
    plt.grid(alpha=0.3)
    plt.tight_layout()
    
    save_path = os.path.join(OUTPUT_DIR, '1_final_return_histogram.png')
    plt.savefig(save_path, dpi=100)
    plt.close()
    print(f' 저장: {save_path}')


def plot_spx_vs_final_return(df: pd.DataFrame):
    """SPX_Return vs Final_Return 산점도"""
    plt.figure(figsize=(10, 6))
    plt.scatter(df['SPX_Return'], df['Final_Return'], 
                alpha=0.3, s=10, color='steelblue')
    plt.axvline(x=0, color='gray', linestyle=':', linewidth=1)
    plt.axhline(y=0, color='gray', linestyle=':', linewidth=1)
    plt.xlabel('SPX_Return (시장 수익률 %)', fontsize=12)
    plt.ylabel('Final_Return (게임 수익률 %)', fontsize=12)
    plt.title('시장 수익률 vs 게임 수익률', fontsize=14, fontweight='bold')
    plt.grid(alpha=0.3)
    plt.tight_layout()
    
    save_path = os.path.join(OUTPUT_DIR, '2_spx_vs_final_scatter.png')
    plt.savefig(save_path, dpi=100)
    plt.close()
    print(f' 저장: {save_path}')


def plot_by_start_date(df: pd.DataFrame):
    """시작 날짜별 박스 플롯"""
    df_copy = df.copy()
    df_copy['start_date'] = pd.to_datetime(df_copy['start_date'])
    df_copy['year_month'] = df_copy['start_date'].dt.to_period('M').astype(str)
    
    # 월별 평균 정렬
    monthly_means = df_copy.groupby('year_month')['Final_Return'].mean().sort_index()
    
    plt.figure(figsize=(14, 6))
    
    # 박스 플롯용 데이터 준비
    months = sorted(df_copy['year_month'].unique())
    data_by_month = [df_copy[df_copy['year_month'] == m]['Final_Return'].values 
                     for m in months]
    
    bp = plt.boxplot(data_by_month, labels=months, showfliers=False, patch_artist=True)
    
    # 색상 (수익은 빨강, 손실은 파랑)
    for patch, mean in zip(bp['boxes'], monthly_means):
        patch.set_facecolor('lightcoral' if mean > 0 else 'lightblue')
    
    plt.axhline(y=0, color='red', linestyle='--', linewidth=1)
    plt.xlabel('시작 날짜 (월)', fontsize=12)
    plt.ylabel('Final_Return (%)', fontsize=12)
    plt.title('시작 날짜별 게임 수익률 분포', fontsize=14, fontweight='bold')
    plt.xticks(rotation=45)
    plt.grid(alpha=0.3, axis='y')
    plt.tight_layout()
    
    save_path = os.path.join(OUTPUT_DIR, '3_by_start_date_boxplot.png')
    plt.savefig(save_path, dpi=100)
    plt.close()
    print(f' 저장: {save_path}')


def plot_by_card(df: pd.DataFrame):
    """카드별 평균 수익률 막대 그래프"""
    card_means = []
    for card_id in range(1, 12):
        cols = [f'Card{card_id}_Round{r}' for r in CARD_SELECT_ROUNDS]
        mask = df[cols].sum(axis=1) > 0
        selected_games = df[mask]
        
        if len(selected_games) > 0:
            card_means.append({
                'name': CARD_NAMES[card_id],
                'mean': selected_games['Final_Return'].mean(),
            })
    
    card_df = pd.DataFrame(card_means).sort_values('mean', ascending=True)
    
    plt.figure(figsize=(10, 6))
    colors = ['lightcoral' if m > 0 else 'lightblue' for m in card_df['mean']]
    plt.barh(card_df['name'], card_df['mean'], color=colors, edgecolor='black')
    plt.axvline(x=0, color='gray', linestyle='-', linewidth=1)
    plt.xlabel('평균 Final_Return (%)', fontsize=12)
    plt.ylabel('카드', fontsize=12)
    plt.title('카드별 평균 수익률 (선택된 게임 기준)', fontsize=14, fontweight='bold')
    plt.grid(alpha=0.3, axis='x')
    plt.tight_layout()
    
    save_path = os.path.join(OUTPUT_DIR, '4_by_card_bar.png')
    plt.savefig(save_path, dpi=100)
    plt.close()
    print(f' 저장: {save_path}')


def plot_volatility_distribution(df: pd.DataFrame):
    """SPX_Volatility 분포"""
    plt.figure(figsize=(10, 6))
    plt.hist(df['SPX_Volatility'], bins=40, color='purple', 
             edgecolor='black', alpha=0.7)
    plt.axvline(x=df['SPX_Volatility'].mean(), color='orange', 
                linestyle='--', linewidth=2,
                label=f'평균 {df["SPX_Volatility"].mean():.2f}')
    plt.xlabel('SPX_Volatility', fontsize=12)
    plt.ylabel('게임 수', fontsize=12)
    plt.title('SPX 변동성 분포', fontsize=14, fontweight='bold')
    plt.legend(fontsize=11)
    plt.grid(alpha=0.3)
    plt.tight_layout()
    
    save_path = os.path.join(OUTPUT_DIR, '5_volatility_histogram.png')
    plt.savefig(save_path, dpi=100)
    plt.close()
    print(f' 저장: {save_path}')


# =============================================
# 메인
# =============================================
def main():
    if not os.path.exists(DATA_PATH):
        print(f'❌ 학습 데이터 없음: {DATA_PATH}')
        print('먼저 monte_carlo.py를 실행하세요.')
        return
    
    print('=' * 60)
    print(' V1.5 시뮬레이션 데이터 분포 분석 (교수님 피드백 5번)')
    print('=' * 60)
    
    df = pd.read_csv(DATA_PATH)
    print(f' 데이터 로드: {len(df):,}건  /  컬럼: {len(df.columns)}개\n')
    
    # 통계 분석
    print_statistics(df)
    analyze_by_start_date(df)
    analyze_by_card(df)
    
    # 시각화
    print('\n' + '=' * 60)
    print(' [4] 시각화 저장')
    print('=' * 60)
    
    plot_final_return_histogram(df)
    plot_spx_vs_final_return(df)
    plot_by_start_date(df)
    plot_by_card(df)
    plot_volatility_distribution(df)
    
    print(f'\n 모든 그래프 저장 완료: {OUTPUT_DIR}')
    print('\n' + '=' * 60)
    print(' 분석 완료')
    print('=' * 60)


if __name__ == '__main__':
    main()
