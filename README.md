# 미니 프로젝트 데이터셋 (현대백화점 기본반)

서브쿼리·조인·그룹화 연습용 SQL 데이터셋 **3종**입니다. 모두 **MySQL 호환**이며, 핵심 테이블에 수백~천 단위 행이 들어 있어 "의미 있는 분석"이 가능합니다.

| 파일 | 주제 | 테이블 | 총 행수 | 핵심 fact 테이블 |
|---|---|---|---|---|
| `01_department_store.sql` | 백화점 리테일 | **14개** | 약 3,900 | orders(600) · order_items(약1,500) · reviews(300) |
| `02_streaming_ott.sql` | OTT 스트리밍 | **12개** | 약 5,100 | watch_history(1,500) · ratings(약700) · episodes |
| `03_hospital.sql` | 병원 진료 | **12개** | 약 3,600 | appointments(700) · prescriptions · billings |

> 데이터는 난수 seed로 생성한 **가상 데이터**입니다. 실명·실제 매출과 무관합니다.

---

## 불러오기 (Import)

### 방법 A — DBeaver에서 SQL 스크립트 실행
1. DBeaver에서 MySQL 연결 생성 → 새 데이터베이스 만들기 (예: `mini_dept`)
2. 해당 DB를 더블클릭해 **활성 상태**로 둔다
3. `SQL Editor` 열기 → `.sql` 파일 내용을 붙여넣거나 **파일 열기**
4. 전체 실행(`Ctrl/Cmd + Enter` 또는 ▶▶ 스크립트 실행)

### 방법 B — 터미널
```bash
mysql -u root -p -e "CREATE DATABASE mini_dept DEFAULT CHARSET utf8mb4;"
mysql -u root -p mini_dept < 01_department_store.sql
```
> 한글이 깨지면 DB charset이 `utf8mb4`인지 확인하세요. 각 파일 첫 줄에 `SET NAMES utf8mb4;`가 들어 있습니다.

---

## 데이터셋별 구조 & 연습 문제

### ① 백화점 리테일 `01_department_store.sql`
**테이블:** regions · stores · membership_grades · categories · brands · suppliers · products · inventory · employees · members · orders · order_items · payments · reviews

연습(서브쿼리 위주):
1. 전체 평균 주문금액보다 큰 주문을 한 회원의 이름을 조회하시오. *(WHERE 서브쿼리)*
2. 점포별 매출 합계가, 전 점포 평균 매출보다 높은 점포를 조회하시오. *(FROM 절 파생 테이블)*
3. 리뷰 평점 평균이 가장 높은 카테고리를 조회하시오.
4. 한 번도 주문되지 않은 상품을 조회하시오. *(NOT IN / NOT EXISTS)*
5. 자신이 속한 등급(grade)의 평균 가입일보다 먼저 가입한 회원을 조회하시오. *(상관 서브쿼리)*

### ② OTT 스트리밍 `02_streaming_ott.sql`
**테이블:** subscription_plans · users · subscriptions · genres · contents · content_genres · episodes · actors · content_actors · devices · watch_history · ratings

연습:
1. 평균 평점보다 높은 평점을 받은 콘텐츠 제목을 조회하시오.
2. 전체 평균 시청시간보다 더 오래 본 사용자를 조회하시오.
3. 장르별 평균 평점을 구하고, 전체 평균보다 높은 장르만 조회하시오.
4. 한 편도 시청 기록이 없는 콘텐츠를 조회하시오. *(NOT EXISTS)*
5. 가장 많이 시청된 콘텐츠의 출연 배우를 조회하시오. *(중첩 서브쿼리)*

### ③ 병원 진료 `03_hospital.sql`
**테이블:** departments · doctors · patients · rooms · diagnoses · treatments · medications · appointments · appointment_diagnoses · appointment_treatments · prescriptions · billings

연습:
1. 전체 평균 수납금액보다 비싼 진료를 받은 환자를 조회하시오.
2. 진료과별 진료 건수가, 평균 진료 건수보다 많은 과를 조회하시오.
3. 가장 많이 처방된 약품명을 조회하시오.
4. 한 번도 예약되지 않은 의사를 조회하시오. *(NOT IN)*
5. 같은 진료과에서 평균 진료비보다 높은 진료 건을 조회하시오. *(상관 서브쿼리)*

---

## 직접 데이터를 구하고 싶다면 — 추천 사이트

수업 자료에 있던 **통계청 · Kaggle · AI-HUB**에 더해, 미니 프로젝트에 바로 쓰기 좋은 곳들입니다.

### 국내 (한글 데이터·바로 CSV)
| 사이트 | 특징 | 링크 |
|---|---|---|
| **공공데이터포털** | 국내 공공기관 데이터 끝판왕. CSV/Excel 다운로드 풍부 | https://www.data.go.kr |
| **통계청 KOSIS** | 인구·물가·소비 등 통계표를 표 형태로 | https://kosis.kr |
| **서울 열린데이터광장** | 서울시 생활·교통·상권 데이터 (리테일 분석에 좋음) | https://data.seoul.go.kr |
| **AI-HUB** | NIA 운영, 대용량·정형/비정형 다양 | https://www.aihub.or.kr |
| **금융 빅데이터 개방시스템(CreDB)** | 카드 소비·금융 통계 | https://credb.kcredit.or.kr |

### 해외 (영문, 양·품질 좋음)
| 사이트 | 특징 | 링크 |
|---|---|---|
| **Kaggle Datasets** | 데이터 분석 표준. 리테일·영화·의료 등 주제별 풍부 | https://www.kaggle.com/datasets |
| **Google Dataset Search** | 데이터셋 전용 검색엔진 | https://datasetsearch.research.google.com |
| **UCI ML Repository** | 학습용 정제 데이터셋 | https://archive.ics.uci.edu |
| **Maven Analytics Data Playground** | 분석 실습용 깔끔한 CSV (추천) | https://www.mavenanalytics.io/data-playground |
| **data.world** | 커뮤니티 공유 데이터셋 | https://data.world |
| **Awesome Public Datasets** | 분야별 데이터 링크 모음 (GitHub) | https://github.com/awesomedata/awesome-public-datasets |

### SQL 연습용 샘플 DB (스키마가 잘 짜인 학습용)
| DB | 특징 |
|---|---|
| **Sakila** (MySQL 공식) | 영화 대여점. 조인·서브쿼리 연습 표준 |
| **Chinook** | 음원 판매. 가볍고 직관적 |
| **Northwind** | 무역회사 주문. 리테일 분석에 딱 |

> **데이터 고를 때 체크리스트** — ① 테이블/컬럼이 여러 개라 **조인·서브쿼리**를 쓸 거리가 있는가 ② 행이 너무 적지 않은가(수백 행 이상 권장) ③ Import 전 강의자료의 3가지 확인(콤마 포함 여부 · xlsx vs csv · `001`처럼 0으로 시작하는 숫자)
