-- #############################################################################
-- # 현백 심화반 4주차 프로젝트 — 데이터셋 B : 온라인 커머스 플랫폼
-- # 단일 실행 파일 (스키마 + 데이터 한 방에 생성). DBeaver 에서 이 파일 전체를
-- # 실행(Execute SQL Script / Alt+X)하면 DB·테이블·데이터가 모두 만들어진다.
-- #
-- # - 엔진: MySQL 8 / MariaDB 11 공통
-- # - 재현성: 모든 값이 CRC32(seed) 기반 → 몇 번 실행해도 동일 데이터
-- # - 16개 테이블, 카테고리 3단계 자기참조 + 주문/결제/배송/반품/리뷰/쿠폰/장바구니
-- #############################################################################

CREATE DATABASE IF NOT EXISTS online_commerce DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE online_commerce;

-- =============================================================================
-- 01_schema.sql  : 온라인 커머스 플랫폼 데이터셋 (현백 심화반 4주차 최종 프로젝트)
-- 엔진          : MySQL 8 표준 문법 (MariaDB 11.x 호환 확인)
-- 인코딩        : utf8mb4 / utf8mb4_0900_ai_ci
-- FK 정책       : 물리 제약 대신 "-- logical relation" 주석으로 표기 (sql_index_lab 방식)
-- =============================================================================

SET NAMES utf8mb4;

-- ----- DROP (의존성 역순) ----------------------------------------------------
DROP TABLE IF EXISTS cart_items;
DROP TABLE IF EXISTS carts;
DROP TABLE IF EXISTS coupon_redemptions;
DROP TABLE IF EXISTS coupons;
DROP TABLE IF EXISTS reviews;
DROP TABLE IF EXISTS returns;
DROP TABLE IF EXISTS shipments;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS sessions;
DROP TABLE IF EXISTS addresses;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS sellers;
DROP TABLE IF EXISTS category;

-- =============================================================================
-- 1) category : 카테고리 (자기참조 3단계 계층  대 > 중 > 소)
-- =============================================================================
CREATE TABLE category (
  category_id   BIGINT       NOT NULL PRIMARY KEY,
  parent_id     BIGINT       NULL,            -- logical relation: category.parent_id -> category.category_id
  depth         TINYINT      NOT NULL,        -- 1=대분류, 2=중분류, 3=소분류
  name          VARCHAR(100) NOT NULL,
  sort_order    INT          NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- 2) sellers : 판매자 (자사 / 입점)
-- =============================================================================
CREATE TABLE sellers (
  seller_id     BIGINT       NOT NULL PRIMARY KEY,
  seller_name   VARCHAR(120) NOT NULL,
  seller_type   VARCHAR(10)  NOT NULL,        -- '자사' | '입점'
  region        VARCHAR(20)  NOT NULL,        -- 서울/경기/부산/...
  rating        DECIMAL(3,2) NOT NULL,        -- 0.00 ~ 5.00 (판매자 평점)
  onboarded_at  DATE         NOT NULL,
  status        VARCHAR(10)  NOT NULL         -- '활성' | '휴면' | '계약종료'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- 3) products : 상품
-- =============================================================================
CREATE TABLE products (
  product_id    BIGINT       NOT NULL PRIMARY KEY,
  seller_id     BIGINT       NOT NULL,        -- logical relation: products.seller_id -> sellers.seller_id
  category_id   BIGINT       NOT NULL,        -- logical relation: products.category_id -> category.category_id (depth=3 소분류)
  product_name  VARCHAR(200) NOT NULL,
  brand         VARCHAR(80)  NOT NULL,
  list_price    INT          NOT NULL,        -- 정가(원)
  cost          INT          NOT NULL,        -- 원가(원) -> 마진 분석용
  status        VARCHAR(10)  NOT NULL,        -- '판매중' | '품절' | '단종'
  launched_at   DATE         NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- 4) customers : 고객
-- =============================================================================
CREATE TABLE customers (
  customer_id     BIGINT       NOT NULL PRIMARY KEY,
  email           VARCHAR(160) NOT NULL,
  gender          VARCHAR(2)   NOT NULL,      -- 'M' | 'F'
  birth_year      SMALLINT     NOT NULL,
  signup_at       DATE         NOT NULL,
  acq_source      VARCHAR(10)  NOT NULL,      -- 획득채널: 검색/SNS광고/추천/오가닉
  signup_channel  VARCHAR(5)   NOT NULL,      -- 'app' | 'web'
  grade           VARCHAR(10)  NOT NULL,      -- VIP/골드/실버/일반
  region          VARCHAR(20)  NOT NULL       -- 거주 지역(대표)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- 5) addresses : 배송지 (고객 1:N)
-- =============================================================================
CREATE TABLE addresses (
  address_id    BIGINT       NOT NULL PRIMARY KEY,
  customer_id   BIGINT       NOT NULL,        -- logical relation: addresses.customer_id -> customers.customer_id
  region        VARCHAR(20)  NOT NULL,
  city          VARCHAR(40)  NOT NULL,
  zipcode       VARCHAR(10)  NOT NULL,
  is_default    TINYINT      NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- 6) sessions : 방문 세션 (퍼널/이탈, customer_id NULL 허용 = 비로그인)
-- =============================================================================
CREATE TABLE sessions (
  session_id    BIGINT       NOT NULL PRIMARY KEY,
  customer_id   BIGINT       NULL,            -- logical relation: sessions.customer_id -> customers.customer_id (NULL=비로그인)
  device        VARCHAR(10)  NOT NULL,        -- mobile/desktop/tablet
  channel       VARCHAR(10)  NOT NULL,        -- 검색/SNS광고/추천/오가닉/직접
  started_at    DATETIME     NOT NULL,
  duration_sec  INT          NOT NULL,        -- 체류시간(초)
  is_bounce     TINYINT      NOT NULL,        -- 1=이탈(단일페이지)
  did_order     TINYINT      NOT NULL         -- 1=이 세션에서 주문 발생(퍼널 전환)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- 7) orders : 주문 헤더 (금액은 order_items 생성 후 UPDATE 로 재계산)
-- =============================================================================
CREATE TABLE orders (
  order_id        BIGINT       NOT NULL PRIMARY KEY,
  customer_id     BIGINT       NOT NULL,      -- logical relation: orders.customer_id -> customers.customer_id
  ordered_at      DATETIME     NOT NULL,
  order_status    VARCHAR(10)  NOT NULL,      -- 결제완료/배송중/배송완료/취소/부분취소
  payment_method  VARCHAR(12)  NOT NULL,      -- 카드/계좌이체/간편결제/포인트
  channel         VARCHAR(5)   NOT NULL,      -- 'app' | 'web'
  items_amount    INT          NOT NULL DEFAULT 0,  -- 품목 합계(재계산)
  discount_amount INT          NOT NULL DEFAULT 0,  -- 할인 합계(재계산)
  shipping_fee    INT          NOT NULL DEFAULT 0,
  total_amount    INT          NOT NULL DEFAULT 0   -- items - discount + shipping (재계산)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- 8) order_items : 주문 품목 (주문 1:N)
-- =============================================================================
CREATE TABLE order_items (
  order_item_id BIGINT       NOT NULL PRIMARY KEY,
  order_id      BIGINT       NOT NULL,        -- logical relation: order_items.order_id -> orders.order_id
  product_id    BIGINT       NOT NULL,        -- logical relation: order_items.product_id -> products.product_id
  seller_id     BIGINT       NOT NULL,        -- logical relation: order_items.seller_id -> sellers.seller_id
  quantity      INT          NOT NULL,
  unit_price    INT          NOT NULL,        -- 판매단가(원)
  item_discount INT          NOT NULL DEFAULT 0,
  item_status   VARCHAR(10)  NOT NULL         -- 정상/취소/반품
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- 9) payments : 결제 (주문 1:1, 금액은 orders 재계산 후 동기화)
-- =============================================================================
CREATE TABLE payments (
  payment_id    BIGINT       NOT NULL PRIMARY KEY,
  order_id      BIGINT       NOT NULL,        -- logical relation: payments.order_id -> orders.order_id
  method        VARCHAR(12)  NOT NULL,
  pg_provider   VARCHAR(20)  NOT NULL,        -- 결제대행사
  amount        INT          NOT NULL,
  status        VARCHAR(10)  NOT NULL,        -- 승인/취소/부분취소
  paid_at       DATETIME     NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- 10) shipments : 배송 (주문 1:1, 취소주문은 미생성)
-- =============================================================================
CREATE TABLE shipments (
  shipment_id   BIGINT       NOT NULL PRIMARY KEY,
  order_id      BIGINT       NOT NULL,        -- logical relation: shipments.order_id -> orders.order_id
  carrier       VARCHAR(20)  NOT NULL,        -- 택배사
  region        VARCHAR(20)  NOT NULL,        -- 배송 지역
  status        VARCHAR(10)  NOT NULL,        -- 배송준비/배송중/배송완료
  shipped_at    DATETIME     NOT NULL,
  delivered_at  DATETIME     NULL,            -- NULL=미완료
  delay_days    INT          NOT NULL         -- 배송 소요일(지연 분석용)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- 11) returns : 반품/취소 (order_item 1:N - 일부 품목만)
-- =============================================================================
CREATE TABLE returns (
  return_id     BIGINT       NOT NULL PRIMARY KEY,
  order_item_id BIGINT       NOT NULL,        -- logical relation: returns.order_item_id -> order_items.order_item_id
  reason        VARCHAR(20)  NOT NULL,        -- 단순변심/사이즈/불량/오배송/배송지연
  requested_at  DATETIME     NOT NULL,
  refund_amount INT          NOT NULL,
  status        VARCHAR(10)  NOT NULL         -- 접수/완료/반려
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- 12) reviews : 리뷰 (정상 품목 일부)
-- =============================================================================
CREATE TABLE reviews (
  review_id     BIGINT       NOT NULL PRIMARY KEY,
  order_item_id BIGINT       NOT NULL,        -- logical relation: reviews.order_item_id -> order_items.order_item_id
  customer_id   BIGINT       NOT NULL,        -- logical relation: reviews.customer_id -> customers.customer_id
  product_id    BIGINT       NOT NULL,        -- logical relation: reviews.product_id -> products.product_id
  rating        TINYINT      NOT NULL,        -- 1 ~ 5
  has_photo     TINYINT      NOT NULL DEFAULT 0,
  created_at    DATETIME     NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- 13) coupons : 쿠폰 마스터
-- =============================================================================
CREATE TABLE coupons (
  coupon_id     BIGINT       NOT NULL PRIMARY KEY,
  coupon_name   VARCHAR(100) NOT NULL,
  discount_type VARCHAR(10)  NOT NULL,        -- '정액' | '정률'
  value         INT          NOT NULL,        -- 정액=원, 정률=%
  min_spend     INT          NOT NULL,        -- 최소 주문금액
  valid_from    DATE         NOT NULL,
  valid_to      DATE         NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- 14) coupon_redemptions : 쿠폰 사용 이력
-- =============================================================================
CREATE TABLE coupon_redemptions (
  redemption_id    BIGINT    NOT NULL PRIMARY KEY,
  coupon_id        BIGINT    NOT NULL,        -- logical relation: coupon_redemptions.coupon_id -> coupons.coupon_id
  customer_id      BIGINT    NOT NULL,        -- logical relation: coupon_redemptions.customer_id -> customers.customer_id
  order_id         BIGINT    NOT NULL,        -- logical relation: coupon_redemptions.order_id -> orders.order_id
  discount_applied INT       NOT NULL,        -- 실제 적용된 할인액
  redeemed_at      DATETIME  NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- 15) carts : 장바구니 (퍼널: 장바구니 -> 이탈/전환)
-- =============================================================================
CREATE TABLE carts (
  cart_id       BIGINT       NOT NULL PRIMARY KEY,
  customer_id   BIGINT       NOT NULL,        -- logical relation: carts.customer_id -> customers.customer_id
  status        VARCHAR(10)  NOT NULL,        -- 장바구니/이탈/전환
  created_at    DATETIME     NOT NULL,
  order_id      BIGINT       NULL             -- logical relation: carts.order_id -> orders.order_id (전환 시)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- 16) cart_items : 장바구니 품목
-- =============================================================================
CREATE TABLE cart_items (
  cart_item_id  BIGINT       NOT NULL PRIMARY KEY,
  cart_id       BIGINT       NOT NULL,        -- logical relation: cart_items.cart_id -> carts.cart_id
  product_id    BIGINT       NOT NULL,        -- logical relation: cart_items.product_id -> products.product_id
  quantity      INT          NOT NULL,
  added_at      DATETIME     NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- =============================================================================
-- 02_generate.sql : 결정적(재현가능) 데이터 생성  - 온라인 커머스 플랫폼
-- 방식           : CRC32(salt+n) 기반 의사난수. RAND() 미사용 -> 몇 번 실행해도 동일 결과.
-- 순서           : seq 헬퍼 -> 마스터 -> fact -> 헤더금액 재계산 -> seq DROP
-- 전제           : 01_schema.sql 로 테이블이 이미 생성돼 있어야 함.
-- =============================================================================

SET NAMES utf8mb4;

-- 안전: 재실행 대비 기존 데이터 비우기 (의존성 무관, TRUNCATE)
TRUNCATE TABLE cart_items;
TRUNCATE TABLE carts;
TRUNCATE TABLE coupon_redemptions;
TRUNCATE TABLE coupons;
TRUNCATE TABLE reviews;
TRUNCATE TABLE returns;
TRUNCATE TABLE shipments;
TRUNCATE TABLE payments;
TRUNCATE TABLE order_items;
TRUNCATE TABLE orders;
TRUNCATE TABLE sessions;
TRUNCATE TABLE addresses;
TRUNCATE TABLE customers;
TRUNCATE TABLE products;
TRUNCATE TABLE sellers;
TRUNCATE TABLE category;

-- =============================================================================
-- 0) seq : 숫자 시퀀스 헬퍼 (0 ~ 999999, 자릿수 크로스조인)
-- =============================================================================
DROP TABLE IF EXISTS seq;
CREATE TABLE seq (n BIGINT PRIMARY KEY);
INSERT INTO seq (n)
WITH d AS (SELECT 0 x UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
           UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9)
SELECT a.x + b.x*10 + c.x*100 + e.x*1000 + f.x*10000 + g.x*100000
FROM d a, d b, d c, d e, d f, d g;   -- 0..999999

-- =============================================================================
-- 마스터 1) category : 3단계 계층  (대 10 / 중 50 / 소 240) = 300
--   id 1..10      = depth1 (대분류)
--   id 11..60     = depth2 (중분류, parent = 대분류)
--   id 61..300    = depth3 (소분류, parent = 중분류)  <- 상품이 붙는 레벨
-- =============================================================================
-- 대분류 10개
INSERT INTO category (category_id, parent_id, depth, name, sort_order)
SELECT n+1, NULL, 1,
  ELT(n+1,'패션의류','뷰티','디지털가전','식품','리빙홈','스포츠레저','유아동','도서문구','반려동물','헬스건강'),
  n+1
FROM seq WHERE n < 10;

-- 중분류 50개 (parent = 1 + n%10)
INSERT INTO category (category_id, parent_id, depth, name, sort_order)
SELECT 11 + n, 1 + (n % 10), 2,
  CONCAT(ELT(1 + (n%10),'패션','뷰티','가전','식품','리빙','스포츠','유아동','도서','반려','헬스'),
         '-중', LPAD(n+1,2,'0')),
  n
FROM seq WHERE n < 50;

-- 소분류 240개 (parent = 11 + n%50)  <- 상품 연결 레벨
INSERT INTO category (category_id, parent_id, depth, name, sort_order)
SELECT 61 + n, 11 + (n % 50), 3,
  CONCAT('소분류-', LPAD(n+1,3,'0')),
  n
FROM seq WHERE n < 240;

-- =============================================================================
-- 마스터 2) sellers : 2000  (자사 약 8% / 입점 92%, 파레토용 region 가중)
-- =============================================================================
INSERT INTO sellers (seller_id, seller_name, seller_type, region, rating, onboarded_at, status)
SELECT
  n+1,
  CONCAT('셀러', LPAD(n+1,4,'0')),
  CASE WHEN (CRC32(CONCAT('stype:',n)) % 100) < 8 THEN '자사' ELSE '입점' END,
  ELT(1 + CRC32(CONCAT('sreg:',n)) % 7, '서울','경기','부산','대구','인천','광주','대전'),
  ROUND(3.0 + (CRC32(CONCAT('srate:',n)) % 200) / 100.0, 2),  -- 3.00~5.00
  DATE_ADD('2022-06-01', INTERVAL CRC32(CONCAT('sonb:',n)) % 900 DAY),
  ELT(1 + CRC32(CONCAT('sstat:',n)) % 10, '활성','활성','활성','활성','활성','활성','활성','활성','휴면','계약종료')
FROM seq WHERE n < 2000;

-- =============================================================================
-- 마스터 3) products : 20000
--   category_id : 소분류(61..300) 중에서. 단 "상승/하락" 시그널을 위해
--                 특정 소분류에 launched_at 분포를 다르게 줌.
--   seller_id   : 파레토(상위 셀러 집중) - 가중식으로 일부 셀러에 몰리게.
-- =============================================================================
INSERT INTO products (product_id, seller_id, category_id, product_name, brand, list_price, cost, status, launched_at)
SELECT
  n+1,
  -- 셀러 파레토: 60% 확률로 상위 200 셀러(1..200)에 집중, 나머지 40%는 전체
  CASE WHEN (CRC32(CONCAT('pslr_w:',n)) % 100) < 60
       THEN 1 + CRC32(CONCAT('pslr_top:',n)) % 200
       ELSE 1 + CRC32(CONCAT('pslr_all:',n)) % 2000 END,
  61 + CRC32(CONCAT('pcat:',n)) % 240,
  CONCAT('상품-', LPAD(n+1,5,'0')),
  CONCAT('BRAND', LPAD(1 + CRC32(CONCAT('pbrand:',n)) % 300, 3, '0')),
  (1 + CRC32(CONCAT('pprice:',n)) % 200) * 1000,        -- 1000 ~ 200000원
  0,  -- cost 는 아래 UPDATE 로 list_price 의 40~75%
  ELT(1 + CRC32(CONCAT('pstat:',n)) % 10, '판매중','판매중','판매중','판매중','판매중','판매중','판매중','판매중','품절','단종'),
  DATE_ADD('2022-01-01', INTERVAL CRC32(CONCAT('plaunch:',n)) % 1400 DAY)
FROM seq WHERE n < 20000;

-- cost = list_price * (0.40 ~ 0.75)
UPDATE products
SET cost = ROUND(list_price * (40 + CRC32(CONCAT('pcost:',product_id)) % 36) / 100.0);

-- =============================================================================
-- 마스터 4) customers : 80000
--   signup_at : 2023-01-01 ~ 2025-12-31 (코호트 분석용 월별 분포)
--   acq_source: 검색/SNS광고/추천/오가닉  <- 채널별 질 차이 시그널의 출발점
--   grade     : 파레토(VIP 5%, 골드 15%, 실버 30%, 일반 50%)
-- =============================================================================
INSERT INTO customers (customer_id, email, gender, birth_year, signup_at, acq_source, signup_channel, grade, region)
SELECT
  n+1,
  CONCAT('user', LPAD(n+1,6,'0'), '@example.com'),
  CASE WHEN CRC32(CONCAT('cgen:',n)) % 2 = 0 THEN 'M' ELSE 'F' END,
  1960 + CRC32(CONCAT('cby:',n)) % 45,                  -- 1960 ~ 2004
  DATE_ADD('2023-01-01', INTERVAL CRC32(CONCAT('csign:',n)) % 1095 DAY),
  -- 획득채널: SNS광고 비중 크게(질 낮은 유입 시그널)
  CASE
    WHEN (CRC32(CONCAT('cacq:',n)) % 100) < 35 THEN 'SNS광고'
    WHEN (CRC32(CONCAT('cacq:',n)) % 100) < 60 THEN '검색'
    WHEN (CRC32(CONCAT('cacq:',n)) % 100) < 80 THEN '오가닉'
    ELSE '추천' END,
  CASE WHEN CRC32(CONCAT('cch:',n)) % 100 < 65 THEN 'app' ELSE 'web' END,
  CASE
    WHEN (CRC32(CONCAT('cgrade:',n)) % 100) < 5  THEN 'VIP'
    WHEN (CRC32(CONCAT('cgrade:',n)) % 100) < 20 THEN '골드'
    WHEN (CRC32(CONCAT('cgrade:',n)) % 100) < 50 THEN '실버'
    ELSE '일반' END,
  ELT(1 + CRC32(CONCAT('creg:',n)) % 7, '서울','경기','부산','대구','인천','광주','대전')
FROM seq WHERE n < 80000;

-- =============================================================================
-- 마스터 5) addresses : 90000  (고객당 1~2개)
--   첫 80000개 = 고객 1:1 기본배송지, 나머지 10000 = 일부 고객 추가배송지
-- =============================================================================
INSERT INTO addresses (address_id, customer_id, region, city, zipcode, is_default)
SELECT
  n+1,
  CASE WHEN n < 80000 THEN n+1                          -- 1:1 기본
       ELSE 1 + CRC32(CONCAT('addr2:',n)) % 80000 END,  -- 추가배송지
  ELT(1 + CRC32(CONCAT('areg:',n)) % 7, '서울','경기','부산','대구','인천','광주','대전'),
  CONCAT('시군구', 1 + CRC32(CONCAT('acity:',n)) % 30),
  LPAD(CRC32(CONCAT('azip:',n)) % 100000, 5, '0'),
  CASE WHEN n < 80000 THEN 1 ELSE 0 END
FROM seq WHERE n < 90000;

-- =============================================================================
-- 마스터 6) coupons : 150
-- =============================================================================
INSERT INTO coupons (coupon_id, coupon_name, discount_type, value, min_spend, valid_from, valid_to)
SELECT
  n+1,
  CONCAT('쿠폰-', LPAD(n+1,3,'0')),
  CASE WHEN CRC32(CONCAT('cptype:',n)) % 2 = 0 THEN '정액' ELSE '정률' END,
  CASE WHEN CRC32(CONCAT('cptype:',n)) % 2 = 0
       THEN (1 + CRC32(CONCAT('cpval:',n)) % 20) * 1000      -- 정액 1000~20000
       ELSE 5 + CRC32(CONCAT('cpval:',n)) % 26 END,          -- 정률 5~30%
  (1 + CRC32(CONCAT('cpmin:',n)) % 10) * 10000,              -- 최소주문 1~10만
  DATE_ADD('2023-01-01', INTERVAL CRC32(CONCAT('cpfrom:',n)) % 900 DAY),
  DATE_ADD('2023-03-01', INTERVAL CRC32(CONCAT('cpto:',n)) % 1000 DAY)
FROM seq WHERE n < 150;

-- =============================================================================
-- FACT 1) sessions : 400000
--   started_at : 월별 가중(11월 빅세일 트래픽 급증)으로 분포.
--   did_order  : 채널/디바이스에 따라 전환율 차등 (SNS광고 전환 낮음).
--   is_bounce  : SNS광고 + mobile 이탈 높음 -> 퍼널 시그널.
-- =============================================================================
INSERT INTO sessions (session_id, customer_id, device, channel, started_at, duration_sec, is_bounce, did_order)
SELECT
  seq.n+1,
  -- 70% 로그인(고객 매핑), 30% 비로그인(NULL)
  CASE WHEN (CRC32(CONCAT('scust_w:',seq.n)) % 100) < 70
       THEN 1 + CRC32(CONCAT('scust:',seq.n)) % 80000 ELSE NULL END,
  ELT(1 + CRC32(CONCAT('sdev:',seq.n)) % 3, 'mobile','desktop','tablet'),
  dat.channel,
  dat.started_at,
  -- 체류시간: 이탈이면 짧게
  CASE WHEN dat.is_bounce = 1 THEN 5 + CRC32(CONCAT('sdur_b:',seq.n)) % 40
       ELSE 60 + CRC32(CONCAT('sdur:',seq.n)) % 1800 END,
  dat.is_bounce,
  dat.did_order
FROM seq
JOIN (
  SELECT s2.n,
    ELT(1 + CRC32(CONCAT('schan:',s2.n)) % 5,'검색','SNS광고','추천','오가닉','직접') AS channel,
    -- 월별 가중 날짜: u 로 월 선택(11월 비중 큼), 일은 균등
    DATE_ADD(
      DATE_ADD(CONCAT(yr.y,'-',LPAD(mo.m,2,'0'),'-01'),
               INTERVAL CRC32(CONCAT('sday:',s2.n)) % 28 DAY),
      INTERVAL CRC32(CONCAT('shour:',s2.n)) % 24 HOUR
    ) AS started_at,
    -- 이탈: SNS광고이면 더 높게
    CASE WHEN (CRC32(CONCAT('schan:',s2.n)) % 5) = 1   -- SNS광고
              THEN CASE WHEN (CRC32(CONCAT('sbnc:',s2.n)) % 100) < 65 THEN 1 ELSE 0 END
         ELSE CASE WHEN (CRC32(CONCAT('sbnc:',s2.n)) % 100) < 40 THEN 1 ELSE 0 END END AS is_bounce,
    -- 전환(주문): SNS광고 낮게, 검색/추천 높게
    CASE WHEN (CRC32(CONCAT('sord:',s2.n)) % 1000) <
              CASE ELT(1 + CRC32(CONCAT('schan:',s2.n)) % 5,'검색','SNS광고','추천','오가닉','직접')
                   WHEN '검색'   THEN 90
                   WHEN 'SNS광고' THEN 35
                   WHEN '추천'   THEN 110
                   WHEN '오가닉' THEN 70
                   ELSE 80 END
         THEN 1 ELSE 0 END AS did_order
  FROM seq s2
  JOIN (SELECT 2023 y UNION ALL SELECT 2024 UNION ALL SELECT 2025) yr
       ON yr.y = 2023 + (CRC32(CONCAT('syear:',s2.n)) % 3)
  JOIN (SELECT 1 m UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
        UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9
        UNION ALL SELECT 10 UNION ALL SELECT 11 UNION ALL SELECT 12) mo
       -- 월 가중: 11월(빅세일) & 12월 비중 크게. u<.. 임계로 월 결정
       ON mo.m = (CASE
          WHEN (CRC32(CONCAT('smonth:',s2.n)) % 1000) < 180 THEN 11   -- 18% 11월
          WHEN (CRC32(CONCAT('smonth:',s2.n)) % 1000) < 300 THEN 12   -- 12% 12월
          WHEN (CRC32(CONCAT('smonth:',s2.n)) % 1000) < 360 THEN 1
          WHEN (CRC32(CONCAT('smonth:',s2.n)) % 1000) < 420 THEN 2
          WHEN (CRC32(CONCAT('smonth:',s2.n)) % 1000) < 480 THEN 3
          WHEN (CRC32(CONCAT('smonth:',s2.n)) % 1000) < 540 THEN 4
          WHEN (CRC32(CONCAT('smonth:',s2.n)) % 1000) < 600 THEN 5
          WHEN (CRC32(CONCAT('smonth:',s2.n)) % 1000) < 660 THEN 6
          WHEN (CRC32(CONCAT('smonth:',s2.n)) % 1000) < 720 THEN 7
          WHEN (CRC32(CONCAT('smonth:',s2.n)) % 1000) < 790 THEN 8
          WHEN (CRC32(CONCAT('smonth:',s2.n)) % 1000) < 870 THEN 9
          ELSE 10 END)
  WHERE s2.n < 400000
) dat ON dat.n = seq.n
WHERE seq.n < 400000;

-- =============================================================================
-- FACT 2) orders : 250000  (헤더 금액은 임시 0, 품목 생성 후 재계산)
--   ordered_at : 11월/12월 가중 + 카테고리 추세를 위해 연도 분포 사용.
--   order_status: 대부분 배송완료, 일부 취소/부분취소.
-- =============================================================================
INSERT INTO orders (order_id, customer_id, ordered_at, order_status, payment_method, channel,
                    items_amount, discount_amount, shipping_fee, total_amount)
SELECT
  seq.n+1,
  -- 고객 파레토: 50% 는 상위 8000 고객(충성고객)에 집중 -> 재구매/LTV
  CASE WHEN (CRC32(CONCAT('ocust_w:',seq.n)) % 100) < 50
       THEN 1 + CRC32(CONCAT('ocust_top:',seq.n)) % 8000
       ELSE 1 + CRC32(CONCAT('ocust_all:',seq.n)) % 80000 END,
  od.ordered_at,
  ELT(1 + CASE
        WHEN (CRC32(CONCAT('ostat:',seq.n)) % 100) < 80 THEN 0   -- 배송완료
        WHEN (CRC32(CONCAT('ostat:',seq.n)) % 100) < 90 THEN 1   -- 배송중
        WHEN (CRC32(CONCAT('ostat:',seq.n)) % 100) < 95 THEN 2   -- 결제완료
        WHEN (CRC32(CONCAT('ostat:',seq.n)) % 100) < 98 THEN 3   -- 부분취소
        ELSE 4 END,                                          -- 취소
      '배송완료','배송중','결제완료','부분취소','취소'),
  ELT(1 + CRC32(CONCAT('opay:',seq.n)) % 4, '카드','간편결제','계좌이체','포인트'),
  CASE WHEN CRC32(CONCAT('ochan:',seq.n)) % 100 < 65 THEN 'app' ELSE 'web' END,
  0, 0,
  CASE WHEN CRC32(CONCAT('oship:',seq.n)) % 100 < 70 THEN 0 ELSE 3000 END,  -- 70% 무료배송
  0
FROM seq
JOIN (
  SELECT o2.n,
    DATE_ADD(
      DATE_ADD(CONCAT(2023 + (CRC32(CONCAT('oyear:',o2.n)) % 3),'-',
                      LPAD(CASE
                        WHEN (CRC32(CONCAT('omonth:',o2.n)) % 1000) < 190 THEN 11   -- 빅세일
                        WHEN (CRC32(CONCAT('omonth:',o2.n)) % 1000) < 320 THEN 12
                        WHEN (CRC32(CONCAT('omonth:',o2.n)) % 1000) < 380 THEN 1
                        WHEN (CRC32(CONCAT('omonth:',o2.n)) % 1000) < 440 THEN 2
                        WHEN (CRC32(CONCAT('omonth:',o2.n)) % 1000) < 500 THEN 3
                        WHEN (CRC32(CONCAT('omonth:',o2.n)) % 1000) < 560 THEN 4
                        WHEN (CRC32(CONCAT('omonth:',o2.n)) % 1000) < 620 THEN 5
                        WHEN (CRC32(CONCAT('omonth:',o2.n)) % 1000) < 680 THEN 6
                        WHEN (CRC32(CONCAT('omonth:',o2.n)) % 1000) < 740 THEN 7
                        WHEN (CRC32(CONCAT('omonth:',o2.n)) % 1000) < 810 THEN 8
                        WHEN (CRC32(CONCAT('omonth:',o2.n)) % 1000) < 880 THEN 9
                        ELSE 10 END, 2, '0'),'-01'),
               INTERVAL CRC32(CONCAT('oday:',o2.n)) % 28 DAY),
      INTERVAL CRC32(CONCAT('ohour:',o2.n)) % 24 HOUR
    ) AS ordered_at
  FROM seq o2 WHERE o2.n < 250000
) od ON od.n = seq.n
WHERE seq.n < 250000;

-- =============================================================================
-- FACT 3) order_items : 약 600000  (주문당 1~5 품목)
--   각 주문 n 에 대해 품목 수 cnt = 1 + CRC32%5 -> 평균 ~2.4 -> 약 600k.
--   상품/단가/수량/할인. "상승 카테고리/하락 카테고리" 시그널은
--   주문 시점(연도)과 상품 카테고리 매핑으로 구현 (아래 별도 보정 UPDATE).
-- =============================================================================
-- 품목: seq 의 n 을 글로벌 품목 인덱스로 쓰고, 주문에 분배.
-- 주문 i (1..250000) 의 품목 개수 = 1 + CRC32%5. 누적합으로 매핑하면 복잡하므로
-- "각 주문마다 최대 5개 슬롯 중 채택 여부" 방식으로 생성 -> 결정적.
INSERT INTO order_items (order_item_id, order_id, product_id, seller_id, quantity, unit_price, item_discount, item_status)
SELECT
  ROW_NUMBER() OVER (ORDER BY oi.order_id, oi.slot) AS order_item_id,
  oi.order_id,
  oi.product_id,
  p.seller_id,
  oi.quantity,
  oi.unit_price,
  oi.item_discount,
  oi.item_status
FROM (
  SELECT
    o.order_id,
    slot.s AS slot,
    1 + CRC32(CONCAT('oiprod:',o.order_id,':',slot.s)) % 20000 AS product_id,
    1 + CRC32(CONCAT('oiqty:',o.order_id,':',slot.s)) % 3 AS quantity,
    -- 단가: 임시(상품 정가 반영은 아래 UPDATE)
    (1 + CRC32(CONCAT('oiprice:',o.order_id,':',slot.s)) % 200) * 1000 AS unit_price,
    0 AS item_discount,
    ELT(1 + CASE
          WHEN (CRC32(CONCAT('oistat:',o.order_id,':',slot.s)) % 100) < 90 THEN 0  -- 정상
          WHEN (CRC32(CONCAT('oistat:',o.order_id,':',slot.s)) % 100) < 96 THEN 1  -- 취소
          ELSE 2 END, '정상','취소','반품') AS item_status
  FROM orders o
  JOIN (SELECT 1 s UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5) slot
    -- 슬롯 채택: 슬롯1 항상, 2..5 는 확률적 -> 주문당 1~5 품목
    ON ( slot.s = 1
         OR (slot.s = 2 AND (CRC32(CONCAT('oislot2:',o.order_id)) % 100) < 60)
         OR (slot.s = 3 AND (CRC32(CONCAT('oislot3:',o.order_id)) % 100) < 40)
         OR (slot.s = 4 AND (CRC32(CONCAT('oislot4:',o.order_id)) % 100) < 22)
         OR (slot.s = 5 AND (CRC32(CONCAT('oislot5:',o.order_id)) % 100) < 12) )
) oi
JOIN products p ON p.product_id = oi.product_id;

-- 단가를 상품 정가로 보정 (정가의 70~100% 판매)
UPDATE order_items oi
JOIN products p ON p.product_id = oi.product_id
SET oi.unit_price = ROUND(p.list_price * (70 + CRC32(CONCAT('oirealp:',oi.order_item_id)) % 31) / 100.0);

-- 품목 할인: 30% 품목에만 단가의 5~20% (쿠폰/프로모션 잠식 시그널 출발점)
UPDATE order_items
SET item_discount = ROUND(unit_price * quantity * (5 + CRC32(CONCAT('oidisc:',order_item_id)) % 16) / 100.0)
WHERE CRC32(CONCAT('oidiscflag:',order_item_id)) % 100 < 30;

-- =============================================================================
-- 시그널 보정) 카테고리 믹스 시프트 (상승 1 / 하락 1)
--   - '디지털가전'(대분류3) 산하 상품: 2025년 주문에서 수량 가중(상승)
--   - '도서문구'(대분류8) 산하 상품: 2025년 주문에서 수량 축소(하락)
--   상품 -> 소분류 -> 중분류 -> 대분류 경로로 대분류 식별.
-- =============================================================================
-- 상품별 대분류 매핑 임시 컬럼 대신 조인으로 처리
UPDATE order_items oi
JOIN orders o          ON o.order_id = oi.order_id
JOIN products p        ON p.product_id = oi.product_id
JOIN category c3       ON c3.category_id = p.category_id        -- 소
JOIN category c2       ON c2.category_id = c3.parent_id          -- 중
SET oi.quantity = oi.quantity + 1 + CRC32(CONCAT('rise:',oi.order_item_id)) % 3
WHERE c2.parent_id = 3                                           -- 디지털가전 (상승)
  AND YEAR(o.ordered_at) = 2025;

UPDATE order_items oi
JOIN orders o          ON o.order_id = oi.order_id
JOIN products p        ON p.product_id = oi.product_id
JOIN category c3       ON c3.category_id = p.category_id
JOIN category c2       ON c2.category_id = c3.parent_id
SET oi.quantity = 1                                              -- 도서문구 (하락: 2025 수량 1로 눌림)
WHERE c2.parent_id = 8
  AND YEAR(o.ordered_at) = 2025
  AND CRC32(CONCAT('fall:',oi.order_item_id)) % 100 < 70;

-- =============================================================================
-- 헤더 금액 재계산 (orders) : items / discount / total  = SUM(order_items)
--   취소 품목(item_status='취소')은 금액에서 제외하여 정합성.
-- =============================================================================
UPDATE orders o
JOIN (
  SELECT order_id,
         SUM(CASE WHEN item_status <> '취소' THEN unit_price * quantity ELSE 0 END) AS items_amt,
         SUM(CASE WHEN item_status <> '취소' THEN item_discount ELSE 0 END)         AS disc_amt
  FROM order_items
  GROUP BY order_id
) s ON s.order_id = o.order_id
SET o.items_amount    = s.items_amt,
    o.discount_amount = s.disc_amt,
    o.total_amount    = s.items_amt - s.disc_amt + o.shipping_fee;

-- 무료배송 임계 보정: 5만원 이상이면 배송비 0 (정합성/현실감)
UPDATE orders
SET shipping_fee = 0,
    total_amount = items_amount - discount_amount
WHERE items_amount - discount_amount >= 50000 AND shipping_fee > 0;

-- =============================================================================
-- FACT 4) payments : 250000  (주문 1:1, 취소주문 status 동기화)
-- =============================================================================
INSERT INTO payments (payment_id, order_id, method, pg_provider, amount, status, paid_at)
SELECT
  o.order_id,
  o.order_id,
  o.payment_method,
  ELT(1 + CRC32(CONCAT('pg:',o.order_id)) % 5, 'TossPay','KakaoPay','NaverPay','KCP','NICE'),
  o.total_amount,
  CASE o.order_status
    WHEN '취소'     THEN '취소'
    WHEN '부분취소' THEN '부분취소'
    ELSE '승인' END,
  DATE_ADD(o.ordered_at, INTERVAL CRC32(CONCAT('paid:',o.order_id)) % 600 SECOND)
FROM orders o;

-- =============================================================================
-- FACT 5) shipments : 약 230000  (취소 주문 제외)
--   delay_days : 지역/택배사별 차등 -> 배송지연 시그널.
--     특정 지역(부산/광주/대전 = 원거리)과 특정 택배사(C택배)에서 지연 큼.
-- =============================================================================
INSERT INTO shipments (shipment_id, order_id, carrier, region, status, shipped_at, delivered_at, delay_days)
SELECT
  o.order_id,
  o.order_id,
  carr.carrier,
  reg.region,
  CASE WHEN o.order_status = '배송완료' THEN '배송완료'
       WHEN o.order_status = '배송중'   THEN '배송중'
       ELSE '배송준비' END,
  DATE_ADD(o.ordered_at, INTERVAL 1 DAY) AS shipped_at,
  CASE WHEN o.order_status = '배송완료'
       THEN DATE_ADD(o.ordered_at, INTERVAL (1 + dly.delay_days) DAY)
       ELSE NULL END AS delivered_at,
  dly.delay_days
FROM orders o
JOIN (SELECT order_id,
        ELT(1 + CRC32(CONCAT('carr:',order_id)) % 4,'A택배','B택배','C택배','D택배') AS carrier
      FROM orders) carr ON carr.order_id = o.order_id
JOIN (SELECT order_id,
        ELT(1 + CRC32(CONCAT('shipreg:',order_id)) % 7,'서울','경기','부산','대구','인천','광주','대전') AS region
      FROM orders) reg ON reg.order_id = o.order_id
JOIN (SELECT o3.order_id,
        -- 기본 1~3일 + 원거리지역 가산 + C택배 가산
        ( 1 + CRC32(CONCAT('dly:',o3.order_id)) % 3
          + CASE WHEN ELT(1 + CRC32(CONCAT('shipreg:',o3.order_id)) % 7,'서울','경기','부산','대구','인천','광주','대전')
                      IN ('부산','광주','대전') THEN 2 + CRC32(CONCAT('dlyreg:',o3.order_id)) % 3 ELSE 0 END
          + CASE WHEN ELT(1 + CRC32(CONCAT('carr:',o3.order_id)) % 4,'A택배','B택배','C택배','D택배') = 'C택배'
                 THEN 2 + CRC32(CONCAT('dlycarr:',o3.order_id)) % 3 ELSE 0 END
        ) AS delay_days
      FROM orders o3) dly ON dly.order_id = o.order_id
WHERE o.order_status <> '취소';

-- =============================================================================
-- FACT 6) returns : 약 30000  (반품/취소 품목 기반)
--   item_status IN ('취소','반품') 인 품목 + 일부 정상품목 반품.
--   카테고리별 반품율 차이: 패션의류(대분류1) 반품 가산 -> 의류 반품 높음.
-- =============================================================================
INSERT INTO returns (return_id, order_item_id, reason, requested_at, refund_amount, status)
SELECT
  ROW_NUMBER() OVER (ORDER BY oi.order_item_id) AS return_id,
  oi.order_item_id,
  ELT(1 + CRC32(CONCAT('rret:',oi.order_item_id)) % 5,'단순변심','사이즈','불량','오배송','배송지연'),
  DATE_ADD(o.ordered_at, INTERVAL 2 + CRC32(CONCAT('rdt:',oi.order_item_id)) % 10 DAY),
  ROUND(oi.unit_price * oi.quantity - oi.item_discount),
  ELT(1 + CRC32(CONCAT('rstat:',oi.order_item_id)) % 10,'완료','완료','완료','완료','완료','완료','완료','완료','접수','반려')
FROM order_items oi
JOIN orders o    ON o.order_id = oi.order_id
JOIN products p  ON p.product_id = oi.product_id
JOIN category c3 ON c3.category_id = p.category_id
JOIN category c2 ON c2.category_id = c3.parent_id
WHERE oi.item_status IN ('취소','반품')
   OR ( oi.item_status = '정상'
        AND ( CRC32(CONCAT('rflag:',oi.order_item_id)) % 1000 <
              CASE WHEN c2.parent_id = 1 THEN 60     -- 패션의류: 반품율 높음
                   WHEN c2.parent_id = 2 THEN 25     -- 뷰티
                   ELSE 12 END ) );

-- =============================================================================
-- FACT 7) reviews : 약 150000  (정상 품목 일부)
--   배송 지연이 큰 주문 -> 평점 낮게 (배송지연->낮은 평점 시그널).
-- =============================================================================
INSERT INTO reviews (review_id, order_item_id, customer_id, product_id, rating, has_photo, created_at)
SELECT
  ROW_NUMBER() OVER (ORDER BY oi.order_item_id) AS review_id,
  oi.order_item_id,
  o.customer_id,
  oi.product_id,
  -- 기본 4~5점이나, 배송 지연(delay_days>=6) 주문은 1~3점으로 하향
  CASE WHEN sh.delay_days >= 6
       THEN 1 + CRC32(CONCAT('rvbad:',oi.order_item_id)) % 3       -- 1~3
       ELSE 4 + CRC32(CONCAT('rvgood:',oi.order_item_id)) % 2 END, -- 4~5
  CASE WHEN CRC32(CONCAT('rvphoto:',oi.order_item_id)) % 100 < 35 THEN 1 ELSE 0 END,
  DATE_ADD(o.ordered_at, INTERVAL 5 + CRC32(CONCAT('rvdt:',oi.order_item_id)) % 20 DAY)
FROM order_items oi
JOIN orders o      ON o.order_id = oi.order_id
LEFT JOIN shipments sh ON sh.order_id = oi.order_id
WHERE oi.item_status = '정상'
  AND CRC32(CONCAT('rvflag:',oi.order_item_id)) % 100 < 35;        -- 정상품목 35% 가 리뷰

-- =============================================================================
-- FACT 8) carts : 200000  (장바구니/이탈/전환)
--   전환된 카트는 order_id 연결. 이탈율 높게(퍼널 이탈 시그널).
-- =============================================================================
INSERT INTO carts (cart_id, customer_id, status, created_at, order_id)
SELECT
  seq.n+1,
  1 + CRC32(CONCAT('ctcust:',seq.n)) % 80000,
  st.status,
  st.created_at,
  CASE WHEN st.status = '전환' THEN 1 + CRC32(CONCAT('ctord:',seq.n)) % 250000 ELSE NULL END
FROM seq
JOIN (
  SELECT c2.n,
    CASE WHEN (CRC32(CONCAT('ctst:',c2.n)) % 100) < 30 THEN '전환'
         WHEN (CRC32(CONCAT('ctst:',c2.n)) % 100) < 75 THEN '이탈'    -- 이탈 큼
         ELSE '장바구니' END AS status,
    DATE_ADD(
      DATE_ADD(CONCAT(2023 + (CRC32(CONCAT('ctyr:',c2.n)) % 3),'-',
                      LPAD(1 + CRC32(CONCAT('ctmo:',c2.n)) % 12,2,'0'),'-01'),
               INTERVAL CRC32(CONCAT('ctdy:',c2.n)) % 28 DAY),
      INTERVAL CRC32(CONCAT('cthr:',c2.n)) % 24 HOUR) AS created_at
  FROM seq c2 WHERE c2.n < 200000
) st ON st.n = seq.n
WHERE seq.n < 200000;

-- =============================================================================
-- FACT 9) cart_items : 약 450000  (카트당 1~4 품목)
-- =============================================================================
INSERT INTO cart_items (cart_item_id, cart_id, product_id, quantity, added_at)
SELECT
  ROW_NUMBER() OVER (ORDER BY ci.cart_id, ci.slot) AS cart_item_id,
  ci.cart_id,
  1 + CRC32(CONCAT('ciprod:',ci.cart_id,':',ci.slot)) % 20000 AS product_id,
  1 + CRC32(CONCAT('ciqty:',ci.cart_id,':',ci.slot)) % 3 AS quantity,
  c.created_at
FROM (
  SELECT c.cart_id, slot.s AS slot
  FROM carts c
  JOIN (SELECT 1 s UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4) slot
    ON ( slot.s = 1
         OR (slot.s = 2 AND (CRC32(CONCAT('cislot2:',c.cart_id)) % 100) < 70)
         OR (slot.s = 3 AND (CRC32(CONCAT('cislot3:',c.cart_id)) % 100) < 45)
         OR (slot.s = 4 AND (CRC32(CONCAT('cislot4:',c.cart_id)) % 100) < 25) )
) ci
JOIN carts c ON c.cart_id = ci.cart_id;

-- =============================================================================
-- FACT 10) coupon_redemptions : 약 60000
--   할인 주문(discount_amount>0) 의 일부에 쿠폰 사용 기록.
--   쿠폰 ROI / 잠식: 일부는 어차피 살 고가주문에 쿠폰 -> 잠식 시그널.
-- =============================================================================
INSERT INTO coupon_redemptions (redemption_id, coupon_id, customer_id, order_id, discount_applied, redeemed_at)
SELECT
  ROW_NUMBER() OVER (ORDER BY o.order_id) AS redemption_id,
  1 + CRC32(CONCAT('crcp:',o.order_id)) % 150,
  o.customer_id,
  o.order_id,
  GREATEST(1000, ROUND(o.discount_amount * (50 + CRC32(CONCAT('crval:',o.order_id)) % 51) / 100.0)),
  DATE_ADD(o.ordered_at, INTERVAL CRC32(CONCAT('crdt:',o.order_id)) % 120 SECOND)
FROM orders o
WHERE o.discount_amount > 0
  AND CRC32(CONCAT('crflag:',o.order_id)) % 100 < 40           -- 할인주문의 40%
  AND o.order_status <> '취소';

-- =============================================================================
-- 정리) seq 헬퍼 제거 - 데이터셋에 남기지 않음
-- =============================================================================
DROP TABLE seq;
