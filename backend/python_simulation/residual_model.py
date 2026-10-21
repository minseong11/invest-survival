"""
residual_model.py — V2 "평균 + 시장 차이" 모델 (8주차 실험)

카드 점수 = 평소 실력(라운드·카드별 평균 기여도) + 시장 차이(지금 시장 때문에 생기는 차이)

기존 V2는 Card_Contribution을 통째로 배워서, 7주차 평가에서 시장을 보지 않는
고정 순위(라운드·카드별 평균)와 거의 같은 순위를 냈다.
이 모델은
  - 평균(base)은 학습 데이터에서 라운드·카드별로 직접 계산해 두고
  - XGBoost는 "실제 기여도 − 평균"(시장 차이)만 학습한다.
예측할 때는 평균 + 시장 차이 예측값을 더한다.

predict() 입력·출력은 기존 V2 모델(XGBRegressor)과 같아서
fastapi_server.py·eval_test_period.py를 고치지 않고 그대로 바꿔 끼울 수 있다.
(pickle로 저장하므로, 불러오는 쪽에서도 이 파일이 같은 폴더에 있어야 한다)
"""
import numpy as np

# 입력 26차원 순서 (recommend_v2.FEATURE_COLS와 동일)
#   0~2 시장 지표, 3 current_round, 4~14 Already_Card1~11, 15~25 Selected_Card_1~11
ROUND_IDX = 3
SELECTED_START = 15
N_CARDS = 11


class ResidualModel:
    def __init__(self, base: dict, residual_model):
        """
        base: {(라운드, 카드ID): 평균 기여도}
        residual_model: 시장 차이를 학습한 회귀 모델 (predict 지원)
        """
        self.base = base
        self.residual_model = residual_model

    def base_values(self, X) -> np.ndarray:
        X = np.asarray(X, dtype=float)
        rounds = X[:, ROUND_IDX].astype(int)
        cards = X[:, SELECTED_START:SELECTED_START + N_CARDS].argmax(axis=1) + 1
        return np.array([self.base.get((r, c), 0.0) for r, c in zip(rounds, cards)])

    def predict(self, X) -> np.ndarray:
        X = np.asarray(X, dtype=float)
        return self.base_values(X) + self.residual_model.predict(X)

    @property
    def feature_importances_(self):
        return self.residual_model.feature_importances_
