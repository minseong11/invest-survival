# 과거로 떠나는 투자 서바이벌 — 실행 방법

서버 3개를 **PostgreSQL → FastAPI → Spring Boot → Flutter** 순서로 켭니다.

```
Flutter 앱 ──(8080)──▶ Spring Boot ──(8000)──▶ FastAPI (V2 추천 · LLM 피드백 · 사후 분석)
                            │
                            └──(5432)──▶ PostgreSQL (주가 · 카드 · 게임 세션)
```

---

## 0. 준비물

| 항목 | 버전 / 비고 |
|---|---|
| Java | 17 |
| Python | 3.10 이상 |
| PostgreSQL | 로컬 5432 포트 |
| Flutter | 최신 stable |
| 주가 CSV 6개 | `backend/data/` 에 넣기 (git에 없음, 팀 드라이브에서 받기) |
| 모델 파일 | `backend/data/simulation/` 에 넣기 (git에 없음) |
| Anthropic API 키 | LLM 피드백용 |

**`backend/data/` 에 있어야 하는 파일**

```
backend/data/
├── ^spx_d.csv
├── ^ndx_d.csv
├── xauusd_d.csv
├── uso_d.csv
├── aapl_d.csv
├── tlt_d.csv
└── simulation/
    ├── model_v2_A.pkl      # V2 모델 A (리먼 외 시나리오)
    ├── model_v2_B.pkl      # V2 모델 B (리먼 시나리오)
    └── model_v15.pkl       # (선택) V1.5 — 게임에서는 사용 안 함
```

> 주가 CSV는 1995~2025 전체 기간이어야 합니다. 일부 기간만 있으면 해당 시나리오가 시작되지 않습니다
> (리먼 2008, 닷컴 2000, 코로나 2020).

---

## 1. PostgreSQL

DB만 만들어 두면 테이블과 데이터는 Spring Boot가 자동으로 채웁니다.

```sql
CREATE DATABASE survivor_db;
```

접속 정보는 `backend/src/main/resources/application.yaml` 기준입니다.

| 항목 | 값 |
|---|---|
| URL | `jdbc:postgresql://localhost:5432/survivor_db` |
| 계정 | `postgres` / `1234` |

비밀번호가 다르면 `application.yaml` 을 본인 환경에 맞게 바꿉니다 (커밋하지 않기).

---

## 2. FastAPI (AI 서버, 8000 포트)

```bash
cd backend/python_simulation
pip install pandas numpy scikit-learn xgboost fastapi uvicorn httpx anthropic

export ANTHROPIC_API_KEY=sk-ant-...      # Windows: set ANTHROPIC_API_KEY=sk-ant-...
python3 fastapi_server.py
```

**정상 확인**
- 터미널에 `✅ V2 모델 A 로드 완료`, `✅ V2 모델 B 로드 완료` 가 보이면 됩니다.
- 브라우저에서 `http://localhost:8000/` 접속 → `"status": "ok"`

> API 키가 없어도 서버는 켜집니다. 이때 LLM 피드백 대신 카드 규칙 + "AI 설명 생성에 실패했어요" 문구가 나옵니다.

---

## 3. Spring Boot (게임 서버, 8080 포트)

**반드시 `backend/` 폴더를 작업 디렉터리로 실행합니다.**
CSV 경로가 `data/^spx_d.csv` 처럼 상대 경로라서, 다른 위치에서 실행하면 주가가 DB에 안 들어갑니다.

```bash
cd backend
./gradlew bootRun          # Windows: gradlew.bat bootRun
```

IntelliJ로 실행할 때는 Run Configuration의 **Working directory** 를 `backend` 폴더로 지정합니다.

**정상 확인**
- 처음 실행 시 콘솔에 `[임포트 완료] ticker=^SPX, 저장건수=...` 가 종목별로 나옵니다 (첫 실행은 시간이 걸림).
- `[임포트 실패]` 가 보이면 CSV 경로·파일명을 확인합니다.
- DB에 주가가 다 들어갔는지 확인:

```sql
SELECT ticker, MIN(trade_date), MAX(trade_date), COUNT(*)
FROM stock_price GROUP BY ticker ORDER BY ticker;
```

모든 종목이 시나리오 기간(2000, 2008, 2020)을 포함해야 합니다.
(USO는 2006년, TLT는 2002년부터라서 닷컴에서는 원유·채권 카드가 자동 제외됩니다 — 정상)

---

## 4. Flutter (앱)

`frontEnd/lib/services/api_client.dart` 의 `_baseUrl` 을 Spring Boot가 켜진 PC 주소로 바꿉니다.

```dart
static const String _baseUrl = 'http://<서버 PC IP>:8080';   // 같은 PC면 http://localhost:8080
```

```bash
cd frontEnd
flutter pub get
flutter run
```

---

## 5. 동작 확인 체크리스트

시나리오 3개를 각각 끝까지 진행합니다.

| 확인 항목 | 리먼 | 닷컴 | 코로나 |
|---|---|---|---|
| 시나리오 선택 → 게임 시작 | | | |
| 1라운드 카드 선택 | | | |
| 25라운드 AI 예측 + 피드백 | | | |
| 50라운드 AI 예측 + 피드백 | | | |
| 75라운드 카드 선택 (AI 예측 없음 안내) | | | |
| 100라운드 종료 → 결과 화면 | | | |
| 결과 화면 사후 분석 (순위·상위 조합) | | | |

**막히면 아래 3가지를 캡처해서 공유합니다**
1. 어디서 막혔는지 (위 표의 어느 칸)
2. 앱에 뜬 에러 문구
3. 같은 시점의 Spring Boot 콘솔, FastAPI 터미널 에러

---

## 자주 나는 문제

| 증상 | 원인 / 해결 |
|---|---|
| "주가 데이터가 부족합니다" | DB에 해당 기간 주가 없음 → 3번의 SQL로 확인, CSV 다시 임포트 |
| "AI 서버에 연결할 수 없습니다" | FastAPI가 꺼져 있음 → 2번 실행 |
| 결과 화면에 사후 분석이 안 나옴 | FastAPI 오류 (결과 화면은 분석 없이 표시되도록 처리됨) → FastAPI 터미널 확인 |
| `ModuleNotFoundError: fastapi` 등 | 2번의 pip install 다시 실행 |
| 앱이 서버에 연결 안 됨 | `_baseUrl` IP 확인, 같은 와이파이인지 확인 |
