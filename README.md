# 과거로 떠나는 투자 서바이벌

리먼 브라더스 사태·닷컴 버블·코로나 쇼크의 실제 주가로 100라운드를 지나가며,
위기 때의 투자 판단을 돈을 잃을 위험 없이 겪어 보고 돌아보는 게임입니다.

```
Flutter 앱 ──(8080)──▶ Spring Boot ──(8000)──▶ FastAPI (V2 추천 · LLM 설명 · 사후 분석)
                            │
                            └──(5432)──▶ PostgreSQL (주가 · 카드 · 뉴스 · 게임 세션)
```

## 한 판의 흐름

| 언제 | 무엇을 | 설명 |
|---|---|---|
| 시작 전 | 시장 브리핑 | 시작일 직전 20거래일의 종목별 등락과 그때의 배경 |
| 1·25·50·75라운드 | 전략 카드 선택 | 후보 3장 중 1장. 카드는 정해진 규칙대로 알아서 사고판다 |
| 뉴스 속보 라운드 (시나리오마다 3번) | 위기 대응 | 버틴다 / 절반 판다 / 더 산다 중 하나. 그날 종가로 바로 매매 |
| 25·50라운드 | AI 예측 | V2 모델이 후보 카드를 비교하고, LLM이 이유를 한 문장으로 설명 |
| 100라운드 뒤 | 사후 분석 | 가능한 카드 조합 전부와 비교한 등급, 카드별 성적표, 위기 대응 돌아보기, 그 후 이야기, AI 코치 한마디 |

게임 계산은 Java(게임 서버)와 Python(사후 분석·학습 데이터) 두 곳에 있고, 두 계산은 원 단위까지 같습니다
(`backend/python_simulation/compare_report.md`, 확인 방법은 [6. 테스트](#6-테스트)).

---

# 실행 방법

서버 3개를 **PostgreSQL → FastAPI → Spring Boot → Flutter** 순서로 켭니다.

## 0. 준비물

| 항목 | 버전 / 비고 |
|---|---|
| Java | 17 이상 (17·21 모두 가능) |
| Python | 3.10 이상 |
| PostgreSQL | 로컬 5432 포트 |
| Flutter | 최신 stable |
| 주가 CSV 6개 | `backend/data/` 에 넣기 (git에 없음, 팀 드라이브에서 받기) |
| 모델 파일 | `backend/data/simulation/` 에 넣기 (git에 없음) |
| Anthropic API 키 | LLM 설명용 (없어도 게임은 진행됨) |

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

접속 정보 기본값은 아래와 같고, 환경변수로 바꿀 수 있습니다 (`application.yaml` 을 고치지 않아도 됨).

| 항목 | 기본값 | 환경변수 |
|---|---|---|
| URL | `jdbc:postgresql://localhost:5432/survivor_db` | `DB_URL` |
| 계정 | `postgres` | `DB_USERNAME` |
| 비밀번호 | `1234` | `DB_PASSWORD` |

---

## 2. FastAPI (AI 서버, 8000 포트)

```bash
cd backend/python_simulation
pip install -r requirements.txt

export ANTHROPIC_API_KEY=sk-ant-...      # Windows: set ANTHROPIC_API_KEY=sk-ant-...
python3 fastapi_server.py
```

**정상 확인**
- 터미널에 `✅ V2 모델 A 로드 완료`, `✅ V2 모델 B 로드 완료` 가 보이면 됩니다.
- 브라우저에서 `http://localhost:8000/` 접속 → `"status": "ok"`

> API 키가 없거나 LLM 응답이 늦으면(8초) 프로그램이 만든 기본 문장으로 응답합니다. 게임은 그대로 진행됩니다.

| 환경변수 | 기본값 | 설명 |
|---|---|---|
| `ANTHROPIC_API_KEY` | (없음) | LLM 설명·AI 코치 문장용 |
| `LLM_MODEL` | `claude-sonnet-4-6` | LLM 모델 |
| `LLM_TIMEOUT_SEC` | `8` | LLM 응답을 기다리는 시간(초). 넘으면 기본 문장으로 응답 |
| `SURVIVAL_DATA_DIR` | `backend/data` | 주가 CSV 폴더 |

---

## 3. Spring Boot (게임 서버, 8080 포트)

**반드시 `backend/` 폴더를 작업 디렉터리로 실행합니다.**
CSV 경로가 `data/^spx_d.csv` 처럼 상대 경로라서, 다른 위치에서 실행하면 주가가 DB에 안 들어갑니다.
(다른 위치에서 실행해야 하면 환경변수 `DATA_CSV_DIR` 에 CSV 폴더의 절대 경로를 지정합니다.)

```bash
cd backend
./gradlew bootRun          # Windows: gradlew.bat bootRun
```

IntelliJ로 실행할 때는 Run Configuration의 **Working directory** 를 `backend` 폴더로 지정합니다.

**정상 확인**
- 처음 실행 시 콘솔에 `[임포트 완료] ticker=^SPX, 새로 저장=...건` 이 종목별로 나옵니다.
- `필수 주가 데이터 준비 실패` 가 보이면 CSV 경로·파일명을 확인합니다.
- 시나리오마다 아래 세 줄이 나오고 마지막에 `시나리오 3개 모두 통과` 가 보이면 됩니다.

```
[시나리오 검사] 1번 리먼브라더스 사태: 뉴스 8개 → 5R, 10R, 20R, ...
[시나리오 검사] 1번 리먼브라더스 사태: 위기 대응 3번 → 10R, 20R, 60R
[시나리오 검사] 1번 리먼브라더스 사태: 1R 2008-09-02 ~ 100R 2009-01-23, 사용 가능 카드 11/11장, ...
```

- `위기 대응` 줄이 3번이 아니면: 위기 대응 뉴스 날짜가 카드 선택 라운드(1·25·50·75)에 걸린 것입니다.
  경고 로그에 어느 뉴스인지 나오며, `data.sql` 의 `decision` 값을 다른 뉴스로 옮기면 됩니다.
- DB에 주가가 다 들어갔는지 확인:

```sql
SELECT ticker, MIN(trade_date), MAX(trade_date), COUNT(*)
FROM stock_price GROUP BY ticker ORDER BY ticker;
```

모든 종목이 시나리오 기간(2000, 2008, 2020)을 포함해야 합니다.
(USO는 2006년, TLT는 2002년부터라서 닷컴에서는 원유·채권 카드가 자동 제외됩니다 — 정상)

SQL 로그가 필요하면 `SHOW_SQL=true` 로 실행합니다 (기본은 꺼져 있음).

---

## 4. Flutter (앱)

서버 주소는 실행할 때 지정합니다 (코드를 고치지 않습니다).

```bash
cd frontEnd
flutter pub get

# 같은 PC에서 서버를 켰을 때 (기본값 http://localhost:8080)
flutter run

# 다른 기기(휴대폰 등)에서 실행할 때: 서버 PC의 IP를 지정
flutter run --dart-define=API_BASE_URL=http://<서버 PC IP>:8080

# 안드로이드 에뮬레이터에서 같은 PC의 서버에 붙을 때
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

---

## 5. 동작 확인 체크리스트

시나리오 3개를 각각 끝까지 진행합니다.

| 확인 항목 | 리먼 | 닷컴 | 코로나 |
|---|---|---|---|
| 시나리오 선택 → 시작 전 시장 브리핑 표시 | | | |
| 1라운드 카드 선택 | | | |
| 뉴스 속보 라운드에서 멈춤 → 위기 대응 선택 (3번) | | | |
| 25라운드 AI 예측 + 설명 | | | |
| 50라운드 AI 예측 + 설명 | | | |
| 75라운드 카드 선택 (AI 예측 없음 안내) | | | |
| 100라운드 종료 → 결과 화면 | | | |
| 결과 화면: 등급·최대 낙폭 | | | |
| 결과 화면: AI 코치 한마디 | | | |
| 결과 화면: 카드별 성적표·위기 대응 돌아보기 | | | |
| 결과 화면: 라운드별 돌아보기·그 후 이야기 | | | |

**막히면 아래 3가지를 캡처해서 공유합니다**
1. 어디서 막혔는지 (위 표의 어느 칸)
2. 앱에 뜬 에러 문구
3. 같은 시점의 Spring Boot 콘솔, FastAPI 터미널 에러

---

## 6. 테스트

```bash
# Python — 서버·DB·API 키·실제 CSV 없이 실행됨
cd backend/python_simulation
pip install -r requirements-test.txt
pytest

# Flutter — 서버 없이 실행됨 (가짜 서버로 한 판 전체 흐름 확인)
cd frontEnd
flutter test

# 게임 서버 계산·진행 — DB 없이 실행됨
cd backend
./gradlew test --tests "*GameServiceTest"

# 게임 서버 전체 (PostgreSQL + backend/data의 CSV 필요)
./gradlew test
```

**서버를 켠 상태에서 하는 확인** (3번 Spring Boot, 2번 FastAPI 실행 후)

```bash
cd backend/python_simulation

# Java와 Python 계산이 같은지 (시나리오마다 500개 조합, 절반은 위기 대응 포함)
#   → compare_report.md 를 다시 씀. 모든 조합에서 차이 0원이어야 통과
python3 compare_java_python.py

# 실제 게임 흐름을 API로 끝까지 진행하며 응답 형식·오류 응답·Python 일치 확인
python3 e2e_game_flow.py
```

GitHub에 올리면 위 검사가 자동으로 돌아갑니다 (`.github/workflows/ci.yml`).
실제 CSV는 저장소에 없으므로 자동 검사에서는 테스트용 가상의 주가를 씁니다.

> **실제 CSV 없이 서버를 켜 보고 싶을 때** (화면·흐름 확인용)
> `python3 backend/python_simulation/tests/make_fixture_data.py backend/data` 로 가상의 주가를 만들 수 있습니다.
> **실제 주가가 아니므로 게임 결과·AI 성능 수치를 말할 때는 쓰면 안 됩니다.**
> 실제 CSV가 이미 있는 폴더에는 덮어쓰지 않고 멈춥니다.

---

## 7. 시연 전 점검

1. 실제 CSV·모델 파일을 넣고 서버를 켠 뒤, 시작 로그에서 시나리오마다 `위기 대응 3번` 이 나오는지 확인합니다.
2. `python3 compare_java_python.py` 를 실행해 **통과**인지 확인합니다
   (저장소의 `compare_report.md` 는 팀의 실제 주가 CSV로 만든 결과입니다 — 시나리오당 500개 조합 모두 차이 0원.
   주가 데이터나 게임 계산을 바꿨다면 다시 실행해 갱신하세요).
3. `python3 e2e_game_flow.py` 가 통과하는지 확인합니다.
4. 시연할 기기에서 시나리오 3개를 한 판씩 끝까지 진행합니다 (5번 체크리스트).
5. 인터넷 연결을 확인합니다.
   - LLM 문장(AI 설명의 "그래서", AI 코치의 "다음엔")은 인터넷이 필요합니다. 끊기면 기본 문장으로 바뀌고 게임은 그대로 진행됩니다 (AI 예측 자체는 모델 파일로 동작).
   - **웹(크롬)으로 시연하면 앱 화면 자체도 인터넷이 필요합니다.** Flutter 웹은 화면을 그리는 엔진(CanvasKit)과 한글·이모지 글꼴을 구글 서버에서 받아 옵니다.
     인터넷이 없으면 기본 빌드는 빈 화면이 됩니다. 기기에 설치된 글꼴을 쓰는 안드로이드·iOS·Windows 앱에는 해당하지 않습니다.
   - 시연장 인터넷이 불안할 때 웹으로 시연하려면:
     1. `frontEnd` 폴더에서 `flutter build web --no-web-resources-cdn` 으로 빌드합니다 (엔진을 빌드 결과에 함께 담음. 서버 주소를 바꾸려면 `--dart-define=API_BASE_URL=...` 도 같이).
     2. `cd build/web && python3 -m http.server 5173` 으로 띄우고, **시연에 쓸 브라우저**로 `http://localhost:5173` 을 엽니다.
     3. 인터넷이 되는 곳에서 시나리오 3개를 결과 화면까지 한 판씩 진행합니다 → 글꼴이 브라우저에 저장됩니다.
        글꼴은 화면에 처음 나오는 글자·아이콘마다 나눠서 받기 때문에, 한 번도 나오지 않은 아이콘은 인터넷이 없으면 네모로 보일 수 있습니다.
6. 시간이 부족하면 게임 화면 오른쪽 위의 배속 버튼(×1 → ×2 → ×4)으로 진행 속도를 올립니다.

---

## 자주 나는 문제

| 증상 | 원인 / 해결 |
|---|---|
| "주가 데이터가 부족합니다" | DB에 해당 기간 주가 없음 → 3번의 SQL로 확인, CSV 다시 임포트 |
| "AI 서버에 연결할 수 없습니다" | FastAPI가 꺼져 있거나 모델 파일이 없음 → 2번 실행, `backend/data/simulation/` 확인 |
| 결과 화면에 사후 분석이 안 나옴 | FastAPI 오류 (결과 화면은 분석 없이 표시되도록 처리됨) → FastAPI 터미널 확인 |
| AI 설명·AI 코치가 항상 같은 기본 문장 | API 키가 없거나 LLM 호출 실패 → FastAPI 터미널의 `LLM ... 생성 실패` 로그 확인 |
| 위기 대응이 나오지 않음 | 서버 시작 로그의 `위기 대응` 줄 확인 (3번 참고) |
| `ModuleNotFoundError: fastapi` 등 | 2번의 pip install 다시 실행 |
| 앱이 서버에 연결 안 됨 | `--dart-define=API_BASE_URL=...` 의 IP 확인, 같은 와이파이인지 확인 |
| 웹(크롬)에서 빈 화면이거나 한글·아이콘이 네모로 보임 | 인터넷 연결 확인 — Flutter 웹은 엔진·글꼴을 인터넷에서 받아 옴 (7번의 5 참고) |
| JDK 버전 오류로 빌드 실패 | JDK 17 이상인지 확인 (`java -version`) |
