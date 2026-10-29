CREATE DATABASE IF NOT EXISTS FIN_COST_REPORTING;
CREATE SCHEMA   IF NOT EXISTS FIN_COST_REPORTING.RAW;

USE SCHEMA FIN_COST_REPORTING.RAW;

-- =============================================================================
-- Source tables
-- =============================================================================

CREATE OR REPLACE TABLE ORGANIZATION_HIERARCHY (
    PROFIT_CENTER  VARCHAR(10)  NOT NULL,
    COST_CENTER    VARCHAR(10)  NOT NULL,
    ORG_UNIT       VARCHAR(10)  NOT NULL,
    NAME           VARCHAR(100) NOT NULL,
    PRIMARY KEY (COST_CENTER)
);

CREATE OR REPLACE TABLE EXTERNAL_SUPPLIERS (
    ID    VARCHAR(10)  NOT NULL,
    NAME  VARCHAR(100) NOT NULL,
    PRIMARY KEY (ID)
);

CREATE OR REPLACE TABLE DOCUMENTS (
    ID                    VARCHAR(10)  NOT NULL,
    FISCAL_YEAR           NUMBER(4,0)  NOT NULL,
    BOOKING_PERIOD        NUMBER(2,0)  NOT NULL,
    ACCOUNT_NUMBER        VARCHAR(10)  NOT NULL,
    PROFIT_CENTER         VARCHAR(10),
    COST_CENTER           VARCHAR(10),
    FUNDING_SOURCE        VARCHAR(10),
    AMOUNT                NUMBER(18,2) NOT NULL,
    EXTERNAL_SUPPLIER_ID  VARCHAR(10),
    DOCUMENT_DETAILS      VARCHAR(200),
    PRIMARY KEY (ID)
);

-- =============================================================================
-- Master data
-- =============================================================================

INSERT INTO ORGANIZATION_HIERARCHY (PROFIT_CENTER, COST_CENTER, ORG_UNIT, NAME) VALUES
    ('PC1000', 'CC1001', 'HYD', 'Hydro plants - operations'),
    ('PC1000', 'CC1002', 'HYD', 'Hydro plants - maintenance'),
    ('PC1000', 'CC1003', 'SOL', 'Solar parks - operations'),
    ('PC2000', 'CC1004', 'NET', 'Network operations - north'),
    ('PC2000', 'CC1005', 'NET', 'Network operations - south'),
    ('PC3000', 'CC1006', 'SAL', 'Sales B2C'),
    ('PC3000', 'CC1007', 'TRD', 'Energy trading'),
    ('PC9000', 'CC1008', 'FIN', 'Finance and controlling'),
    ('PC9000', 'CC1009', 'HRM', 'Human resources'),
    ('PC9000', 'CC1010', 'ITS', 'IT infrastructure'),
    ('PC9000', 'CC1011', 'ITS', 'IT applications'),
    ('PC9000', 'CC1012', 'DAI', 'Data and AI');

INSERT INTO EXTERNAL_SUPPLIERS (ID, NAME) VALUES
    ('S001', 'Carpathia Power Exchange'),
    ('S002', 'Danubia Gas Supply'),
    ('S003', 'Alpenstrom Handel'),
    ('S004', 'Hydrotech Turbine Services'),
    ('S005', 'Voltaris Grid Maintenance'),
    ('S006', 'SolarCare Operations'),
    ('S007', 'CloudNine Software'),
    ('S008', 'Bytewise IT Services'),
    ('S009', 'Datenwerk Systems'),
    ('S010', 'Meridian Advisory Partners'),
    ('S011', 'Brightpath Training Academy'),
    ('S012', 'Urban Office Leasing'),
    ('S013', 'Skyway Travel Management'),
    ('S014', 'OfficeMart Supplies'),
    ('S015', 'TeleLink Communications');

-- =============================================================================
-- Documents: 1,200 postings from January 2025 to October 2026
-- =============================================================================

INSERT INTO DOCUMENTS
    (ID, FISCAL_YEAR, BOOKING_PERIOD, ACCOUNT_NUMBER, PROFIT_CENTER, COST_CENTER, FUNDING_SOURCE,
     AMOUNT, EXTERNAL_SUPPLIER_ID, DOCUMENT_DETAILS)
WITH cost_kinds AS (
    SELECT * FROM (VALUES
        ( 0, '600000', 'Electricity purchase',  'Stromeinkauf',                  'Achiziție energie electrică',  TRUE,  20000,  400000),
        ( 1, '610000', 'Natural gas purchase',  'Erdgaseinkauf',                 'Achiziție gaze naturale',      TRUE,  10000,  250000),
        ( 2, '630000', 'Equipment maintenance', 'Wartung von Anlagen',           'Mentenanță echipamente',       TRUE,    800,   60000),
        ( 3, '640000', 'Software licences',     'Softwarelizenzen',              'Licențe software',             TRUE,    300,   40000),
        ( 4, '641000', 'IT support services',   'IT-Supportleistungen',          'Servicii de suport IT',        TRUE,    500,   25000),
        ( 5, '650000', 'Consulting services',   'Beratungsleistungen',           'Servicii de consultanță',      TRUE,   1500,   90000),
        ( 6, '660000', 'Office rent',           'Büromiete',                     'Chirie birouri',               TRUE,   2000,   20000),
        ( 7, '670000', 'Business travel',       'Dienstreisen',                  'Deplasări de serviciu',        TRUE,     40,    2500),
        ( 8, '681000', 'Salaries',              'Löhne und Gehälter',            'Salarii',                      FALSE,  4000,  140000),
        ( 9, '682000', 'Social contributions',  'Sozialversicherungsbeiträge',   'Contribuții sociale',          FALSE,   900,   30000),
        (10, '684000', 'Training',              'Schulungen',                    'Training',                     TRUE,    250,   12000),
        (11, '690000', 'Depreciation',          'Abschreibungen',                'Amortizare',                   FALSE,  1500,   85000)
    ) AS k (KIND_ID, ACCOUNT_NUMBER, TEXT_EN, TEXT_DE, TEXT_RO, HAS_SUPPLIER, MIN_AMOUNT, MAX_AMOUNT)
),
postings AS (
    SELECT
        n.N,
        k.*,
        DATEADD(MONTH, MOD(ABS(HASH(n.N, 'month')), 22), DATE '2025-01-01') AS POSTING_MONTH   -- Jan 2025 ... Oct 2026
    FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS N FROM TABLE(GENERATOR(ROWCOUNT => 1200))) n
    JOIN cost_kinds k
      ON k.KIND_ID = MOD(n.N, 12)
)
SELECT
    'D' || LPAD(p.N::VARCHAR, 6, '0')                                        AS ID,
    YEAR(p.POSTING_MONTH)                                                    AS FISCAL_YEAR,
    MONTH(p.POSTING_MONTH)                                                   AS BOOKING_PERIOD,
    p.ACCOUNT_NUMBER,
    h.PROFIT_CENTER,
    h.COST_CENTER,
    CASE
        WHEN MOD(ABS(HASH(p.N, 'funding')), 10) < 6 THEN 'OWN'
        WHEN MOD(ABS(HASH(p.N, 'funding')), 10) < 8 THEN 'EU'
        ELSE 'NATIONAL'
    END                                                                      AS FUNDING_SOURCE,
    ROUND(p.MIN_AMOUNT + (p.MAX_AMOUNT - p.MIN_AMOUNT) * MOD(ABS(HASH(p.N, 'amount')), 1000) / 1000, 2)
                                                                             AS AMOUNT,
    IFF(p.HAS_SUPPLIER, 'S' || LPAD((1 + MOD(ABS(HASH(p.N, 'supplier')), 15))::VARCHAR, 3, '0'), NULL)
                                                                             AS EXTERNAL_SUPPLIER_ID,
    CASE MOD(ABS(HASH(p.N, 'language')), 3)
        WHEN 0 THEN p.TEXT_EN
        WHEN 1 THEN p.TEXT_DE
        ELSE p.TEXT_RO
    END                                                                      AS DOCUMENT_DETAILS
FROM postings p
JOIN ORGANIZATION_HIERARCHY h
  ON h.COST_CENTER = 'CC' || (1001 + MOD(ABS(HASH(p.N, 'cost_center')), 12))::VARCHAR;

-- =============================================================================
-- Check results
-- =============================================================================

-- 1. How much arrived (expected: 1,200 documents, 12 cost centers, 15 suppliers)
SELECT 'DOCUMENTS' AS TABLE_NAME, COUNT(*) AS ROWS_LOADED FROM DOCUMENTS
UNION ALL SELECT 'ORGANIZATION_HIERARCHY', COUNT(*) FROM ORGANIZATION_HIERARCHY
UNION ALL SELECT 'EXTERNAL_SUPPLIERS',     COUNT(*) FROM EXTERNAL_SUPPLIERS;

-- 2. What the documents cover and what they cost, per year
SELECT FISCAL_YEAR,
       COUNT(*)                          AS DOCUMENTS,
       MIN(BOOKING_PERIOD)               AS FIRST_PERIOD,
       MAX(BOOKING_PERIOD)               AS LAST_PERIOD,
       COUNT(DISTINCT ACCOUNT_NUMBER)    AS ACCOUNTS,
       COUNT(DISTINCT COST_CENTER)       AS COST_CENTERS,
       SUM(AMOUNT)                       AS TOTAL_AMOUNT
FROM DOCUMENTS
GROUP BY FISCAL_YEAR
ORDER BY FISCAL_YEAR;

