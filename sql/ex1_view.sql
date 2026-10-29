CREATE SCHEMA IF NOT EXISTS CORE;

CREATE OR REPLACE VIEW CORE.V_DOCUMENTS_ENRICHED AS
WITH supplier_spend AS (

    SELECT
        EXTERNAL_SUPPLIER_ID,
        FISCAL_YEAR,
        COUNT(*)    AS SUPPLIER_DOCUMENTS_IN_YEAR,
        SUM(AMOUNT) AS SUPPLIER_SPEND_IN_YEAR
    FROM RAW.DOCUMENTS
    WHERE EXTERNAL_SUPPLIER_ID IS NOT NULL
    GROUP BY EXTERNAL_SUPPLIER_ID, FISCAL_YEAR
),
documents AS (

    SELECT
        d.*,
        DATE_FROM_PARTS(d.FISCAL_YEAR, d.BOOKING_PERIOD, 1) AS PERIOD_START_DATE
    FROM RAW.DOCUMENTS d
    WHERE d.FISCAL_YEAR >= (SELECT MAX(FISCAL_YEAR) - 1 FROM RAW.DOCUMENTS)
      AND d.BOOKING_PERIOD BETWEEN 1 AND 12
)
SELECT
    d.ID                                                           AS DOCUMENT_ID,

    -- Period
    d.FISCAL_YEAR,
    d.BOOKING_PERIOD,
    d.FISCAL_YEAR || '-' || LPAD(d.BOOKING_PERIOD::VARCHAR, 2, '0') AS PERIOD_LABEL,
    d.PERIOD_START_DATE,
    LAST_DAY(d.PERIOD_START_DATE)                                  AS PERIOD_END_DATE,
    DATE_TRUNC('QUARTER', d.PERIOD_START_DATE)                     AS QUARTER_START_DATE,
    DATEDIFF('month', d.PERIOD_START_DATE,
             MAX(d.PERIOD_START_DATE) OVER ())                     AS MONTHS_BEFORE_LATEST_PERIOD,

    -- Account and organisation
    d.ACCOUNT_NUMBER,
    LEFT(d.ACCOUNT_NUMBER, 2)                                      AS ACCOUNT_GROUP,
    d.PROFIT_CENTER,
    d.COST_CENTER,
    COALESCE(h.NAME, 'Unknown cost center')                        AS COST_CENTER_NAME,
    COALESCE(h.ORG_UNIT, 'UNMAPPED')                               AS ORG_UNIT,
    COALESCE(UPPER(TRIM(d.FUNDING_SOURCE)), 'OWN')                 AS FUNDING_SOURCE,

    -- Supplier
    d.EXTERNAL_SUPPLIER_ID,
    d.EXTERNAL_SUPPLIER_ID IS NOT NULL                             AS IS_EXTERNAL_SUPPLIER,
    COALESCE(s.NAME, 'Internal posting')                           AS SUPPLIER_NAME,
    ss.SUPPLIER_DOCUMENTS_IN_YEAR,
    ss.SUPPLIER_SPEND_IN_YEAR,

    -- Amount
    d.AMOUNT,
    CASE
        WHEN d.AMOUNT >= 100000 THEN 'High (100k and more)'
        WHEN d.AMOUNT >= 10000  THEN 'Medium (10k to 100k)'
        ELSE 'Low (under 10k)'
    END                                                            AS AMOUNT_BAND,
    ROUND(100 * d.AMOUNT
          / SUM(d.AMOUNT) OVER (PARTITION BY d.COST_CENTER, d.FISCAL_YEAR), 2)
                                                                   AS PCT_OF_COST_CENTER_YEAR,

    d.DOCUMENT_DETAILS
FROM documents d
LEFT JOIN RAW.ORGANIZATION_HIERARCHY h
       ON h.COST_CENTER = d.COST_CENTER
LEFT JOIN RAW.EXTERNAL_SUPPLIERS s
       ON s.ID = d.EXTERNAL_SUPPLIER_ID
LEFT JOIN supplier_spend ss
       ON ss.EXTERNAL_SUPPLIER_ID = d.EXTERNAL_SUPPLIER_ID
      AND ss.FISCAL_YEAR          = d.FISCAL_YEAR;

-- =============================================================================
-- Check the result
-- =============================================================================

SELECT *
FROM CORE.V_DOCUMENTS_ENRICHED
ORDER BY AMOUNT DESC
LIMIT 10;
