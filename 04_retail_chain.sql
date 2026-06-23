-- #############################################################################
-- # 현백 심화반 4주차 프로젝트 — 데이터셋 A : 대한민국 전국 오프라인 유통체인
-- # 단일 실행 파일 (스키마 + 데이터 한 방에 생성). DBeaver 에서 이 파일 전체를
-- # 실행(Execute SQL Script / Alt+X)하면 DB·테이블·데이터가 모두 만들어진다.
-- #
-- # - 엔진: MySQL 8 / MariaDB 11 공통
-- # - 재현성: 모든 값이 CRC32(seed) 기반 → 몇 번 실행해도 동일 데이터
-- # - 14개 테이블, 지리 계층(지역>시군구>점포>층/부서>브랜드>상품)
-- #############################################################################

CREATE DATABASE IF NOT EXISTS kr_retail DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE kr_retail;

-- =====================================================================
-- 대한민국 전국 오프라인 유통체인 (현대백화점식) — 분석 리포트 데이터셋 A
-- 01_schema.sql  :  스키마 정의 (테이블 14개, 지리적 계층 구조)
-- 엔진: MySQL 8 표준 문법 / 로컬 검증: MariaDB 11.8
-- =====================================================================
-- 컨벤션 (2주차 sql_index_lab 과 동일):
--   - PK 는 BIGINT
--   - 물리 FK 제약 없음. 대신 "-- logical relation: child.col -> parent.col" 주석으로 표기
--   - ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
--     (MariaDB 11.8 에서도 utf8mb4_0900_ai_ci 허용됨. 만약 로드 실패 시
--      utf8mb4_general_ci 로 폴백하고 README 에 명시할 것.)
--
-- 계층 (지리 → 점포 → 매장):
--   regions(시도) -> districts(시군구) -> stores(점포)
--     -> floors(층) / departments(매장군) -> tenants(입점브랜드) -> products(SKU)
--   employees / members / visits / sales -> sale_items / inventory_snapshots / promotions
-- =====================================================================

SET NAMES utf8mb4;

-- DROP (의존성 역순) ----------------------------------------------------
DROP TABLE IF EXISTS sale_items;
DROP TABLE IF EXISTS sales;
DROP TABLE IF EXISTS inventory_snapshots;
DROP TABLE IF EXISTS visits;
DROP TABLE IF EXISTS promotions;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS tenants;
DROP TABLE IF EXISTS departments;
DROP TABLE IF EXISTS floors;
DROP TABLE IF EXISTS employees;
DROP TABLE IF EXISTS members;
DROP TABLE IF EXISTS stores;
DROP TABLE IF EXISTS districts;
DROP TABLE IF EXISTS regions;

-- =====================================================================
-- 1) regions : 17개 광역시도 (지리 계층 최상위)
-- =====================================================================
CREATE TABLE regions (
    region_id        BIGINT PRIMARY KEY,
    region_name      VARCHAR(40) NOT NULL,      -- 서울, 부산, 경기 ...
    region_type      VARCHAR(20) NOT NULL,      -- 특별시 / 광역시 / 도 / 특별자치도
    is_capital_area  TINYINT NOT NULL           -- 1=수도권(서울/경기/인천), 0=비수도권
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =====================================================================
-- 2) districts : 시군구
-- =====================================================================
CREATE TABLE districts (
    district_id      BIGINT PRIMARY KEY,
    region_id        BIGINT NOT NULL,
    district_name    VARCHAR(60) NOT NULL,
    pop_band         VARCHAR(10) NOT NULL       -- 상/중/하 (생활인구 규모대)
    -- logical relation: region_id -> regions.region_id
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =====================================================================
-- 3) stores : 점포
-- =====================================================================
CREATE TABLE stores (
    store_id         BIGINT PRIMARY KEY,
    district_id      BIGINT NOT NULL,
    store_name       VARCHAR(80) NOT NULL,
    store_format     VARCHAR(20) NOT NULL,      -- 본점 / 플래그십 / 아울렛 / 지역점
    opened_at        DATE NOT NULL,
    gross_area_m2    INT NOT NULL               -- 영업면적(㎡)
    -- logical relation: district_id -> districts.district_id
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =====================================================================
-- 4) floors : 층 (B1/1F.. 점포별)
-- =====================================================================
CREATE TABLE floors (
    floor_id         BIGINT PRIMARY KEY,
    store_id         BIGINT NOT NULL,
    floor_label      VARCHAR(10) NOT NULL,      -- B1, 1F, 2F ...
    floor_theme      VARCHAR(40) NOT NULL       -- 식품관 / 여성패션 / 명품 / 리빙 ...
    -- logical relation: store_id -> stores.store_id
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =====================================================================
-- 5) departments : 매장군 (점포 안의 매장 카테고리)
-- =====================================================================
CREATE TABLE departments (
    department_id    BIGINT PRIMARY KEY,
    store_id         BIGINT NOT NULL,
    floor_id         BIGINT NOT NULL,
    dept_name        VARCHAR(60) NOT NULL,      -- 명품관 / 여성패션 / 식품관 / 가전 / 리빙 ...
    dept_category    VARCHAR(30) NOT NULL       -- LUXURY / FASHION / FOOD / ELECTRONICS / LIVING / BEAUTY
    -- logical relations:
    -- store_id -> stores.store_id
    -- floor_id -> floors.floor_id
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =====================================================================
-- 6) tenants : 입점 브랜드
-- =====================================================================
CREATE TABLE tenants (
    tenant_id        BIGINT PRIMARY KEY,
    department_id    BIGINT NOT NULL,
    store_id         BIGINT NOT NULL,           -- 비정규화: 조인 편의용 (department.store_id 와 동일)
    brand_name       VARCHAR(80) NOT NULL,
    brand_tier       VARCHAR(20) NOT NULL,      -- 명품 / 컨템포러리 / 내셔널
    contract_type    VARCHAR(20) NOT NULL,      -- 직매입 / 특정매입 / 임대
    commission_rate  DECIMAL(5,2) NOT NULL      -- 수수료율(%) 임대=0, 특정매입 높음
    -- logical relations:
    -- department_id -> departments.department_id
    -- store_id      -> stores.store_id
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =====================================================================
-- 7) products : SKU
-- =====================================================================
CREATE TABLE products (
    product_id       BIGINT PRIMARY KEY,
    tenant_id        BIGINT NOT NULL,
    store_id         BIGINT NOT NULL,           -- 비정규화: 조인/재고 편의용
    dept_category    VARCHAR(30) NOT NULL,      -- 비정규화: tenant 의 dept 카테고리
    product_name     VARCHAR(120) NOT NULL,
    category         VARCHAR(40) NOT NULL,      -- 의류/잡화/식품/가전/화장품/리빙 세부
    unit_price       DECIMAL(12,2) NOT NULL,    -- 판매가
    cost             DECIMAL(12,2) NOT NULL     -- 원가
    -- logical relations:
    -- tenant_id -> tenants.tenant_id
    -- store_id  -> stores.store_id
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =====================================================================
-- 8) employees : 직원 (점포/매장군 소속)
-- =====================================================================
CREATE TABLE employees (
    employee_id      BIGINT PRIMARY KEY,
    store_id         BIGINT NOT NULL,
    department_id    BIGINT NOT NULL,
    emp_name         VARCHAR(60) NOT NULL,
    role             VARCHAR(20) NOT NULL,      -- 점장 / 매니저 / 판매 / CS
    employment_type  VARCHAR(20) NOT NULL,      -- 정규 / 계약 / 파견
    hire_date        DATE NOT NULL,
    monthly_salary   DECIMAL(12,2) NOT NULL
    -- logical relations:
    -- store_id      -> stores.store_id
    -- department_id -> departments.department_id
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =====================================================================
-- 9) members : 멤버십 회원
-- =====================================================================
CREATE TABLE members (
    member_id        BIGINT PRIMARY KEY,
    grade            VARCHAR(20) NOT NULL,      -- 우수 / 골드 / 플래티넘 / 디아너스
    home_region_id   BIGINT NOT NULL,
    birth_year       SMALLINT NOT NULL,
    gender           CHAR(1) NOT NULL,          -- M / F
    joined_at        DATE NOT NULL,
    marketing_opt_in TINYINT NOT NULL           -- 1=동의, 0=거부
    -- logical relation: home_region_id -> regions.region_id
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =====================================================================
-- 10) visits : 방문 로그
-- =====================================================================
CREATE TABLE visits (
    visit_id         BIGINT PRIMARY KEY,
    member_id        BIGINT NOT NULL,
    store_id         BIGINT NOT NULL,
    visited_at       DATETIME NOT NULL,
    dwell_min        INT NOT NULL,              -- 체류시간(분)
    channel          VARCHAR(20) NOT NULL       -- 오프라인 / 앱 / 발렛 / 픽업
    -- logical relations:
    -- member_id -> members.member_id
    -- store_id  -> stores.store_id
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =====================================================================
-- 11) sales : 거래 헤더
-- =====================================================================
CREATE TABLE sales (
    sale_id          BIGINT PRIMARY KEY,
    store_id         BIGINT NOT NULL,
    tenant_id        BIGINT NOT NULL,
    member_id        BIGINT NULL,               -- 비회원 거래는 NULL
    employee_id      BIGINT NOT NULL,
    sold_at          DATETIME NOT NULL,
    payment_method   VARCHAR(20) NOT NULL,      -- 카드 / 현금 / 상품권 / 간편결제
    sale_status      VARCHAR(20) NOT NULL,      -- 정상 / 취소 / 반품
    gross_amount     DECIMAL(14,2) NOT NULL,    -- 할인전 (sale_items 합으로 재계산됨)
    discount_amount  DECIMAL(14,2) NOT NULL,    -- 할인액 (sale_items 합으로 재계산됨)
    net_amount       DECIMAL(14,2) NOT NULL,    -- 실매출 = gross - discount
    point_earned     DECIMAL(12,2) NOT NULL     -- 적립 포인트
    -- logical relations:
    -- store_id    -> stores.store_id
    -- tenant_id   -> tenants.tenant_id
    -- member_id   -> members.member_id (NULL 허용)
    -- employee_id -> employees.employee_id
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =====================================================================
-- 12) sale_items : 거래 품목 (디테일)
-- =====================================================================
CREATE TABLE sale_items (
    sale_item_id     BIGINT PRIMARY KEY,
    sale_id          BIGINT NOT NULL,
    product_id       BIGINT NOT NULL,
    quantity         INT NOT NULL,
    unit_price       DECIMAL(12,2) NOT NULL,    -- 거래시점 판매가
    line_discount    DECIMAL(12,2) NOT NULL     -- 품목 할인액
    -- logical relations:
    -- sale_id    -> sales.sale_id
    -- product_id -> products.product_id
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =====================================================================
-- 13) inventory_snapshots : 재고 스냅샷
-- =====================================================================
CREATE TABLE inventory_snapshots (
    snapshot_id      BIGINT PRIMARY KEY,
    store_id         BIGINT NOT NULL,
    product_id       BIGINT NOT NULL,
    snapshot_date    DATE NOT NULL,
    on_hand_qty      INT NOT NULL,              -- 현 보유수량
    safety_qty       INT NOT NULL               -- 안전재고 (on_hand < safety = 결품위험)
    -- logical relations:
    -- store_id   -> stores.store_id
    -- product_id -> products.product_id
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =====================================================================
-- 14) promotions : 프로모션
-- =====================================================================
CREATE TABLE promotions (
    promotion_id     BIGINT PRIMARY KEY,
    store_id         BIGINT NOT NULL,
    dept_category    VARCHAR(30) NOT NULL,      -- 대상 매장군 카테고리
    promo_type       VARCHAR(20) NOT NULL,      -- 정기세일 / 사은행사 / 멤버십데이
    start_date       DATE NOT NULL,
    end_date         DATE NOT NULL,
    budget           DECIMAL(14,2) NOT NULL     -- 행사 예산
    -- logical relation: store_id -> stores.store_id
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =====================================================================
-- 스키마 끝. 데이터는 02_generate.sql 로 채운다.
-- =====================================================================


-- =====================================================================
-- 02_generate.sql : 결정적(재현가능) 데이터 생성
-- =====================================================================
-- 재현성 원리:
--   모든 난수는 CRC32(CONCAT('SALT:', n)) 으로 만든다. n=행번호, SALT=컬럼별 문자열.
--   RAND() 를 전혀 쓰지 않으므로 몇 번 실행하든 결과가 동일하다
--   (= "RAND(42) 시드 고정"과 같은 보장). 엔진(MySQL8/MariaDB)이 달라도 CRC32 값은 같다.
--
-- 헬퍼: seq (0..N) — 자릿수 크로스조인으로 만든다 (재귀 깊이 한계 회피).
--       생성이 끝나면 맨 마지막에 DROP TABLE seq 로 제거한다.
--
-- 실행 순서: seq → 마스터 → fact → 헤더금액 재계산 UPDATE → DROP seq
-- 단독 실행 가능 (01_schema.sql 로 테이블이 이미 있어야 함).
-- =====================================================================

SET NAMES utf8mb4;
SET SESSION sql_mode = '';        -- 0000-00-00 등 엄격모드 회피 (MariaDB/MySQL 공통)

-- ---------------------------------------------------------------------
-- seq 헬퍼 : 0 .. 999999
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS seq;
CREATE TABLE seq (n BIGINT PRIMARY KEY);
INSERT INTO seq (n)
WITH d AS (
  SELECT 0 x UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
  UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9
)
SELECT a.x + b.x*10 + c.x*100 + e.x*1000 + f.x*10000 + g.x*100000
FROM d a, d b, d c, d e, d f, d g;   -- 0..999999

-- =====================================================================
-- 마스터 1) regions : 17개 광역시도
-- =====================================================================
INSERT INTO regions (region_id, region_name, region_type, is_capital_area) VALUES
 (1 ,'서울','특별시',1),
 (2 ,'부산','광역시',0),
 (3 ,'대구','광역시',0),
 (4 ,'인천','광역시',1),
 (5 ,'광주','광역시',0),
 (6 ,'대전','광역시',0),
 (7 ,'울산','광역시',0),
 (8 ,'세종','특별자치시',0),
 (9 ,'경기','도',1),
 (10,'강원','특별자치도',0),
 (11,'충북','도',0),
 (12,'충남','도',0),
 (13,'전북','특별자치도',0),
 (14,'전남','도',0),
 (15,'경북','도',0),
 (16,'경남','도',0),
 (17,'제주','특별자치도',0);

-- =====================================================================
-- 마스터 2) districts : 60개 시군구
--   region_id 매핑은 수도권(1,4,9)에 가중치를 줘서 수도권 점포가 많아지게 함.
-- =====================================================================
INSERT INTO districts (district_id, region_id, district_name, pop_band)
SELECT
  n AS district_id,
  -- 수도권 편중: u<0.55 -> 서울/경기/인천 중 하나, 아니면 전 시도 균등
  CASE
    WHEN (CRC32(CONCAT('dist_reg:', n)) % 100) < 55
      THEN ELT(1 + CRC32(CONCAT('dist_cap:', n)) % 3, 1, 9, 4)
    ELSE 1 + CRC32(CONCAT('dist_all:', n)) % 17
  END AS region_id,
  CONCAT('자치구', LPAD(n, 2, '0')) AS district_name,
  ELT(1 + CRC32(CONCAT('dist_pop:', n)) % 3, '상','중','하') AS pop_band
FROM seq
WHERE n BETWEEN 1 AND 60;

-- =====================================================================
-- 마스터 3) stores : 30개 점포
--   district 매핑은 수도권 자치구 쏠림을 그대로 상속.
--   store_format 분포: 지역점 多, 본점/플래그십 少 (아울렛 중간).
-- =====================================================================
INSERT INTO stores (store_id, district_id, store_name, store_format, opened_at, gross_area_m2)
SELECT
  n AS store_id,
  1 + CRC32(CONCAT('store_dist:', n)) % 60 AS district_id,
  CONCAT('점포', LPAD(n, 2, '0')) AS store_name,
  CASE
    WHEN (CRC32(CONCAT('store_fmt:', n)) % 100) < 12 THEN '본점'
    WHEN (CRC32(CONCAT('store_fmt:', n)) % 100) < 27 THEN '플래그십'
    WHEN (CRC32(CONCAT('store_fmt:', n)) % 100) < 50 THEN '아울렛'
    ELSE '지역점'
  END AS store_format,
  DATE_ADD('2005-01-01', INTERVAL (CRC32(CONCAT('store_open:', n)) % 6500) DAY) AS opened_at,
  20000 + CRC32(CONCAT('store_area:', n)) % 90000 AS gross_area_m2
FROM seq
WHERE n BETWEEN 1 AND 30;

-- =====================================================================
-- 마스터 4) floors : 점포당 4층 = 120
--   floor_theme 은 층번호에 따라 결정 (식품관=B1, 1F 명품 ...).
-- =====================================================================
INSERT INTO floors (floor_id, store_id, floor_label, floor_theme)
SELECT
  n AS floor_id,
  1 + ((n - 1) DIV 4) AS store_id,            -- 4개씩 묶어 점포 배정 (1..30)
  ELT(1 + ((n - 1) % 4), 'B1','1F','2F','3F') AS floor_label,
  ELT(1 + ((n - 1) % 4), '식품관','명품','여성패션','리빙') AS floor_theme
FROM seq
WHERE n BETWEEN 1 AND 120;

-- =====================================================================
-- 마스터 5) departments : 200개 매장군
--   점포에 라운드로빈 배정. dept_category 분포로 LUXURY/FOOD 등 부여.
-- =====================================================================
INSERT INTO departments (department_id, store_id, floor_id, dept_name, dept_category)
SELECT
  n AS department_id,
  1 + ((n - 1) % 30) AS store_id,             -- 30개 점포에 라운드로빈
  -- 해당 점포의 4개 층 중 하나
  (1 + ((n - 1) % 30) - 1) * 4 + (1 + CRC32(CONCAT('dept_fl:', n)) % 4) AS floor_id,
  CONCAT(
    ELT(1 + CRC32(CONCAT('dept_nm:', n)) % 6,
        '명품관','여성패션','식품관','가전','리빙','뷰티'),
    ' ', LPAD(n,3,'0')) AS dept_name,
  ELT(1 + CRC32(CONCAT('dept_cat:', n)) % 6,
      'LUXURY','FASHION','FOOD','ELECTRONICS','LIVING','BEAUTY') AS dept_category
FROM seq
WHERE n BETWEEN 1 AND 200;

-- =====================================================================
-- 마스터 6) tenants : 400개 입점 브랜드
--   department 에 라운드로빈. brand_tier/contract_type/commission_rate 부여.
--   LUXURY dept 의 브랜드는 '명품' tier 확률 높게.
-- =====================================================================
INSERT INTO tenants (tenant_id, department_id, store_id, brand_name, brand_tier, contract_type, commission_rate)
SELECT
  t.n AS tenant_id,
  t.dep_id AS department_id,
  d.store_id AS store_id,
  CONCAT('브랜드', LPAD(t.n,3,'0')) AS brand_name,
  CASE
    WHEN d.dept_category = 'LUXURY' AND (CRC32(CONCAT('tn_tier:', t.n)) % 100) < 70 THEN '명품'
    WHEN (CRC32(CONCAT('tn_tier:', t.n)) % 100) < 35 THEN '명품'
    WHEN (CRC32(CONCAT('tn_tier:', t.n)) % 100) < 70 THEN '컨템포러리'
    ELSE '내셔널'
  END AS brand_tier,
  ELT(1 + CRC32(CONCAT('tn_ctr:', t.n)) % 3, '직매입','특정매입','임대') AS contract_type,
  CASE ELT(1 + CRC32(CONCAT('tn_ctr:', t.n)) % 3, '직매입','특정매입','임대')
    WHEN '임대'   THEN 0.00
    WHEN '직매입' THEN 18.00 + CRC32(CONCAT('tn_cm:', t.n)) % 8
    ELSE 28.00 + CRC32(CONCAT('tn_cm:', t.n)) % 10        -- 특정매입 수수료 높음
  END AS commission_rate
FROM (
  SELECT n, 1 + ((n - 1) % 200) AS dep_id FROM seq WHERE n BETWEEN 1 AND 400
) t
JOIN departments d ON d.department_id = t.dep_id;

-- =====================================================================
-- 마스터 7) products : 3000개 SKU
--   tenant 에 라운드로빈. dept_category 별 단가 레벨 차등 (LUXURY 고단가).
--   cost 는 unit_price 의 55~80%.
-- =====================================================================
INSERT INTO products (product_id, tenant_id, store_id, dept_category, product_name, category, unit_price, cost)
SELECT
  p.n AS product_id,
  p.ten_id AS tenant_id,
  tn.store_id AS store_id,
  dep.dept_category AS dept_category,
  CONCAT('상품', LPAD(p.n,4,'0')) AS product_name,
  ELT(1 + CRC32(CONCAT('pd_cat:', p.n)) % 6, '의류','잡화','식품','가전','화장품','리빙') AS category,
  -- dept_category 별 단가 베이스 (LATERAL 미지원 엔진 대비, 인라인 CASE)
  CASE dep.dept_category
    WHEN 'LUXURY'      THEN 800000  + (CRC32(CONCAT('pd_up:', p.n)) % 50) * 120000   -- 80만~668만
    WHEN 'ELECTRONICS' THEN 300000  + (CRC32(CONCAT('pd_up:', p.n)) % 40) * 50000    -- 30만~225만
    WHEN 'FASHION'     THEN 90000   + (CRC32(CONCAT('pd_up:', p.n)) % 40) * 12000    -- 9만~56만
    WHEN 'LIVING'      THEN 50000   + (CRC32(CONCAT('pd_up:', p.n)) % 40) * 8000     -- 5만~36만
    WHEN 'BEAUTY'      THEN 40000   + (CRC32(CONCAT('pd_up:', p.n)) % 30) * 5000     -- 4만~18만
    ELSE                     8000   + (CRC32(CONCAT('pd_up:', p.n)) % 30) * 2000     -- FOOD 8천~6.6만
  END AS unit_price,
  ROUND(
    (CASE dep.dept_category
      WHEN 'LUXURY'      THEN 800000  + (CRC32(CONCAT('pd_up:', p.n)) % 50) * 120000
      WHEN 'ELECTRONICS' THEN 300000  + (CRC32(CONCAT('pd_up:', p.n)) % 40) * 50000
      WHEN 'FASHION'     THEN 90000   + (CRC32(CONCAT('pd_up:', p.n)) % 40) * 12000
      WHEN 'LIVING'      THEN 50000   + (CRC32(CONCAT('pd_up:', p.n)) % 40) * 8000
      WHEN 'BEAUTY'      THEN 40000   + (CRC32(CONCAT('pd_up:', p.n)) % 30) * 5000
      ELSE                     8000   + (CRC32(CONCAT('pd_up:', p.n)) % 30) * 2000
    END) * (0.55 + (CRC32(CONCAT('pd_cost:', p.n)) % 26) / 100.0), 0) AS cost
FROM (
  SELECT n, 1 + ((n - 1) % 400) AS ten_id FROM seq WHERE n BETWEEN 1 AND 3000
) p
JOIN tenants tn ON tn.tenant_id = p.ten_id
JOIN departments dep ON dep.department_id = tn.department_id;

-- =====================================================================
-- 마스터 8) employees : 3000명
--   store/department 소속. role 분포 (판매 多), employment_type, 급여.
--   role/연차에 따라 급여 차등 + 점장 고연봉.
-- =====================================================================
INSERT INTO employees (employee_id, store_id, department_id, emp_name, role, employment_type, hire_date, monthly_salary)
SELECT
  e.n AS employee_id,
  d.store_id AS store_id,
  e.dep_id AS department_id,
  CONCAT('사원', LPAD(e.n,4,'0')) AS emp_name,
  CASE
    WHEN (CRC32(CONCAT('emp_role:', e.n)) % 100) < 6  THEN '점장'
    WHEN (CRC32(CONCAT('emp_role:', e.n)) % 100) < 22 THEN '매니저'
    WHEN (CRC32(CONCAT('emp_role:', e.n)) % 100) < 82 THEN '판매'
    ELSE 'CS'
  END AS role,
  ELT(1 + CRC32(CONCAT('emp_et:', e.n)) % 3, '정규','계약','파견') AS employment_type,
  DATE_ADD('2012-01-01', INTERVAL (CRC32(CONCAT('emp_hire:', e.n)) % 4900) DAY) AS hire_date,
  CASE
    WHEN (CRC32(CONCAT('emp_role:', e.n)) % 100) < 6  THEN 7000000 + (CRC32(CONCAT('emp_sal:', e.n)) % 30) * 100000
    WHEN (CRC32(CONCAT('emp_role:', e.n)) % 100) < 22 THEN 4500000 + (CRC32(CONCAT('emp_sal:', e.n)) % 25) * 80000
    WHEN (CRC32(CONCAT('emp_role:', e.n)) % 100) < 82 THEN 2800000 + (CRC32(CONCAT('emp_sal:', e.n)) % 20) * 60000
    ELSE 2600000 + (CRC32(CONCAT('emp_sal:', e.n)) % 15) * 50000
  END AS monthly_salary
FROM (
  SELECT n, 1 + ((n - 1) % 200) AS dep_id FROM seq WHERE n BETWEEN 1 AND 3000
) e
JOIN departments d ON d.department_id = e.dep_id;

-- =====================================================================
-- 마스터 9) members : 50000명
--   grade 파레토: 디아너스(최상위) 소수 + 우수(최하위) 다수.
--   home_region_id 는 수도권 편중. birth_year/gender/joined_at/opt_in.
-- =====================================================================
INSERT INTO members (member_id, grade, home_region_id, birth_year, gender, joined_at, marketing_opt_in)
SELECT
  n AS member_id,
  CASE
    WHEN (CRC32(CONCAT('mb_grd:', n)) % 1000) < 30  THEN '디아너스'   -- 상위 3%
    WHEN (CRC32(CONCAT('mb_grd:', n)) % 1000) < 130 THEN '플래티넘'   -- 다음 10%
    WHEN (CRC32(CONCAT('mb_grd:', n)) % 1000) < 400 THEN '골드'       -- 다음 27%
    ELSE '우수'                                                       -- 나머지 60%
  END AS grade,
  CASE
    WHEN (CRC32(CONCAT('mb_reg:', n)) % 100) < 60
      THEN ELT(1 + CRC32(CONCAT('mb_cap:', n)) % 3, 1, 9, 4)
    ELSE 1 + CRC32(CONCAT('mb_all:', n)) % 17
  END AS home_region_id,
  1955 + CRC32(CONCAT('mb_by:', n)) % 55 AS birth_year,             -- 1955~2009
  ELT(1 + CRC32(CONCAT('mb_g:', n)) % 2, 'M','F') AS gender,
  DATE_ADD('2018-01-01', INTERVAL (CRC32(CONCAT('mb_join:', n)) % 2900) DAY) AS joined_at,
  CASE WHEN (CRC32(CONCAT('mb_opt:', n)) % 100) < 62 THEN 1 ELSE 0 END AS marketing_opt_in
FROM seq
WHERE n BETWEEN 1 AND 50000;

-- =====================================================================
-- fact 10) visits : 150000건
--   member/store 매핑. 수도권 점포로 방문 쏠림. visited_at 시즌성(12월/명절↑).
--   channel 분포. dwell_min.
-- =====================================================================
INSERT INTO visits (visit_id, member_id, store_id, visited_at, dwell_min, channel)
SELECT
  v.n AS visit_id,
  1 + CRC32(CONCAT('vs_mb:', v.n)) % 50000 AS member_id,
  -- store: u<0.6 면 1~12번(수도권 가정 점포군)으로 쏠림
  CASE WHEN (CRC32(CONCAT('vs_st:', v.n)) % 100) < 60
       THEN 1 + CRC32(CONCAT('vs_st2:', v.n)) % 12
       ELSE 1 + CRC32(CONCAT('vs_st3:', v.n)) % 30 END AS store_id,
  v.vdt AS visited_at,
  10 + CRC32(CONCAT('vs_dw:', v.n)) % 170 AS dwell_min,
  ELT(1 + CRC32(CONCAT('vs_ch:', v.n)) % 4, '오프라인','앱','발렛','픽업') AS channel
FROM (
  SELECT
    n,
    -- 시즌 가중 날짜: 기본 균등 + 12월/2월(명절)/5월 가중. month-weighted.
    DATE_ADD(
      DATE_ADD('2023-01-01', INTERVAL (CRC32(CONCAT('vs_d:', n)) % 1095) DAY),
      INTERVAL 0 DAY) AS vdt0,
    -- 시즌 쏠림: 일부 행을 12월로 강제 이동
    CASE
      WHEN (CRC32(CONCAT('vs_seas:', n)) % 100) < 18
        THEN DATE_ADD('2024-12-01', INTERVAL (CRC32(CONCAT('vs_dec:', n)) % 31) DAY)
      WHEN (CRC32(CONCAT('vs_seas:', n)) % 100) < 28
        THEN DATE_ADD('2024-02-01', INTERVAL (CRC32(CONCAT('vs_feb:', n)) % 14) DAY)
      ELSE DATE_ADD('2023-01-01', INTERVAL (CRC32(CONCAT('vs_d:', n)) % 1095) DAY)
    END AS vdt
  FROM seq WHERE n BETWEEN 1 AND 150000
) v;

-- =====================================================================
-- fact 11) sales : 250000건 (헤더; 금액은 임시값, 나중에 sale_items 합으로 재계산)
--   store/tenant/employee 정합 매핑.
--   member_id 는 가끔 NULL (비회원).
--   sold_at 시즌성(12월 빅세일 / 11월 ↑). sale_status 분포(취소/반품 소수).
--   ★ 시그널 의도:
--     - 매출 시점 시즌성: 12월/11월 급증
--     - 카테고리 추세: FOOD 상승(후반기 ↑), ELECTRONICS 하락(후반기 ↓)
--       => sale_items 단계에서 product 의 dept_category 와 sold_at 으로 수량 가중
-- =====================================================================
INSERT INTO sales (sale_id, store_id, tenant_id, member_id, employee_id, sold_at,
                   payment_method, sale_status, gross_amount, discount_amount, net_amount, point_earned)
SELECT
  s.n AS sale_id,
  tn.store_id AS store_id,
  s.tenant_id AS tenant_id,
  -- 비회원 12%
  CASE WHEN (CRC32(CONCAT('sl_mb0:', s.n)) % 100) < 12 THEN NULL
       ELSE 1 + CRC32(CONCAT('sl_mb:', s.n)) % 50000 END AS member_id,
  emp.employee_id AS employee_id,
  s.sdt AS sold_at,
  ELT(1 + CRC32(CONCAT('sl_pm:', s.n)) % 4, '카드','현금','상품권','간편결제') AS payment_method,
  CASE
    WHEN (CRC32(CONCAT('sl_st:', s.n)) % 1000) < 35 THEN '반품'   -- 3.5%
    WHEN (CRC32(CONCAT('sl_st:', s.n)) % 1000) < 60 THEN '취소'   -- 2.5%
    ELSE '정상'
  END AS sale_status,
  0 AS gross_amount,       -- 임시값. sale_items 생성 후 UPDATE 로 재계산.
  0 AS discount_amount,
  0 AS net_amount,
  0 AS point_earned
FROM (
  SELECT
    n,
    1 + CRC32(CONCAT('sl_tn:', n)) % 400 AS tenant_id,
    CASE
      WHEN (CRC32(CONCAT('sl_seas:', n)) % 100) < 20
        THEN DATE_ADD('2024-12-01', INTERVAL (CRC32(CONCAT('sl_dec:', n)) % 31) DAY)   -- 12월 빅세일
      WHEN (CRC32(CONCAT('sl_seas:', n)) % 100) < 32
        THEN DATE_ADD('2024-11-01', INTERVAL (CRC32(CONCAT('sl_nov:', n)) % 30) DAY)   -- 11월 행사
      WHEN (CRC32(CONCAT('sl_seas:', n)) % 100) < 42
        THEN DATE_ADD('2024-02-01', INTERVAL (CRC32(CONCAT('sl_feb:', n)) % 14) DAY)   -- 설 명절
      ELSE DATE_ADD('2023-01-01', INTERVAL (CRC32(CONCAT('sl_d:', n)) % 1095) DAY)
    END AS sdt
  FROM seq WHERE n BETWEEN 1 AND 250000
) s
JOIN tenants tn ON tn.tenant_id = s.tenant_id
-- 같은 점포 소속 직원 1명을 결정적으로 선택
JOIN employees emp ON emp.employee_id = (
  -- 점포 내 직원이 없을 수 있으므로 전체에서 점포일치 우선, 폴백 균등
  1 + CRC32(CONCAT('sl_emp:', s.n)) % 3000
);

-- =====================================================================
-- fact 12) sale_items : 약 600000건 (sale 당 1~4개)
--   각 sale 의 tenant 소속 product 중에서 결정적으로 선택.
--   ★ 시그널: 카테고리 추세 — FOOD 는 2024 하반기 수량↑, ELECTRONICS 는 ↓
--   line_discount: 12월/11월 sale 은 할인율 ↑ (프로모션 효과)
-- =====================================================================
-- sale 당 품목 수 = 1 + crc%4  → 1..4 평균 2.5 → 약 62.5만건
INSERT INTO sale_items (sale_item_id, sale_id, product_id, quantity, unit_price, line_discount)
SELECT
  si.gid AS sale_item_id,
  si.sale_id AS sale_id,
  pr.product_id AS product_id,
  -- 수량: 기본 1~3. 카테고리 추세 가중.
  GREATEST(1,
    1 + CRC32(CONCAT('it_qty:', si.gid)) % 3
    + CASE
        WHEN pr.dept_category='FOOD' AND si.sale_year=2024 AND si.sale_mon>=7 THEN 2  -- FOOD 후반 상승
        WHEN pr.dept_category='ELECTRONICS' AND si.sale_year=2024 AND si.sale_mon>=7 THEN -1 -- 가전 후반 하락
        ELSE 0
      END
  ) AS quantity,
  pr.unit_price AS unit_price,
  -- 라인 할인: 시즌(11/12월) sale 은 할인율 15~35%, 평시 0~12%
  ROUND(pr.unit_price *
    CASE WHEN si.sale_mon IN (11,12) THEN (15 + CRC32(CONCAT('it_dc:', si.gid)) % 21) / 100.0
         ELSE (CRC32(CONCAT('it_dc:', si.gid)) % 13) / 100.0 END
  , 0) AS line_discount
FROM (
  -- sale 을 품목수만큼 펼친다: seq 의 small 슬라이스로 item 인덱스 0..3 조인
  SELECT
    s.sale_id,
    s.tenant_id,
    YEAR(s.sold_at)  AS sale_year,
    MONTH(s.sold_at) AS sale_mon,
    k.n AS item_idx,
    (s.sale_id * 10 + k.n) AS gid     -- 고유 sale_item_id
  FROM sales s
  JOIN seq k ON k.n BETWEEN 0 AND (CRC32(CONCAT('it_cnt:', s.sale_id)) % 4)   -- 0..3 → 1~4개
) si
JOIN tenants tn ON tn.tenant_id = si.tenant_id
-- 해당 tenant 의 product 중 하나를 결정적으로 선택 (tenant 당 product 다수 존재)
JOIN products pr ON pr.product_id = (
  -- products 는 tenant 라운드로빈으로 생성됨: tenant t 의 product 는
  -- product_id ≡ t (mod 400) 인 것들. 그 중 하나를 결정적으로 고른다.
  si.tenant_id + 400 * (CRC32(CONCAT('it_pidx:', si.gid)) % 7)
)
WHERE pr.product_id BETWEEN 1 AND 3000;

-- =====================================================================
-- ★ 헤더 금액 재계산 (reconcile) : sale_items 합으로 sales 금액 확정
--   gross = Σ(qty*unit_price), discount = Σ(line_discount), net = gross-discount
--   point = net 의 1% (정상건만), 취소/반품은 0
-- =====================================================================
UPDATE sales s
JOIN (
  SELECT sale_id,
         SUM(quantity * unit_price)  AS g,
         SUM(line_discount)          AS d
  FROM sale_items
  GROUP BY sale_id
) agg ON agg.sale_id = s.sale_id
SET s.gross_amount    = agg.g,
    s.discount_amount = agg.d,
    s.net_amount      = agg.g - agg.d,
    s.point_earned    = CASE WHEN s.sale_status='정상'
                             THEN ROUND((agg.g - agg.d) * 0.01, 0) ELSE 0 END;

-- 혹시 품목이 안 붙은 sale (이론상 없음) 안전 처리
UPDATE sales SET gross_amount=0, discount_amount=0, net_amount=0, point_earned=0
WHERE sale_id NOT IN (SELECT DISTINCT sale_id FROM sale_items);

-- =====================================================================
-- fact 13) inventory_snapshots : 120000건
--   store/product 매핑. snapshot_date 월별.
--   ★ 시그널: 일부 product 는 on_hand < safety (결품) → 기회손실 분석거리.
--     인기 카테고리(FOOD)일수록 결품 확률 높게.
-- =====================================================================
INSERT INTO inventory_snapshots (snapshot_id, store_id, product_id, snapshot_date, on_hand_qty, safety_qty)
SELECT
  i.n AS snapshot_id,
  pr.store_id AS store_id,
  pr.product_id AS product_id,
  DATE_ADD('2024-01-01', INTERVAL (CRC32(CONCAT('iv_dt:', i.n)) % 12) MONTH) AS snapshot_date,
  -- 결품 신호: FOOD 25% / 그외 10% 확률로 on_hand 를 safety 아래로
  CASE
    WHEN pr.dept_category='FOOD' AND (CRC32(CONCAT('iv_stk:', i.n)) % 100) < 25
      THEN CRC32(CONCAT('iv_low:', i.n)) % 8
    WHEN (CRC32(CONCAT('iv_stk:', i.n)) % 100) < 10
      THEN CRC32(CONCAT('iv_low:', i.n)) % 8
    ELSE 20 + CRC32(CONCAT('iv_oh:', i.n)) % 180
  END AS on_hand_qty,
  10 + CRC32(CONCAT('iv_sf:', i.n)) % 20 AS safety_qty
FROM (
  SELECT n, 1 + CRC32(CONCAT('iv_pid:', n)) % 3000 AS prod FROM seq WHERE n BETWEEN 1 AND 120000
) i
JOIN products pr ON pr.product_id = i.prod;

-- =====================================================================
-- fact 14) promotions : 300건
--   store/dept_category. promo_type. 기간. budget.
-- =====================================================================
INSERT INTO promotions (promotion_id, store_id, dept_category, promo_type, start_date, end_date, budget)
SELECT
  n AS promotion_id,
  1 + CRC32(CONCAT('pr_st:', n)) % 30 AS store_id,
  ELT(1 + CRC32(CONCAT('pr_cat:', n)) % 6,
      'LUXURY','FASHION','FOOD','ELECTRONICS','LIVING','BEAUTY') AS dept_category,
  ELT(1 + CRC32(CONCAT('pr_ty:', n)) % 3, '정기세일','사은행사','멤버십데이') AS promo_type,
  DATE_ADD('2023-01-01', INTERVAL (CRC32(CONCAT('pr_d:', n)) % 1080) DAY) AS start_date,
  DATE_ADD(
    DATE_ADD('2023-01-01', INTERVAL (CRC32(CONCAT('pr_d:', n)) % 1080) DAY),
    INTERVAL (3 + CRC32(CONCAT('pr_len:', n)) % 18) DAY) AS end_date,
  5000000 + (CRC32(CONCAT('pr_bg:', n)) % 60) * 1000000 AS budget
FROM seq
WHERE n BETWEEN 1 AND 300;

-- =====================================================================
-- 정리 : seq 헬퍼 제거 (데이터셋에 남기지 않음)
-- =====================================================================
DROP TABLE seq;

-- =====================================================================
-- 생성 완료.
-- =====================================================================
