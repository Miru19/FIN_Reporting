-- =============================================================================
-- 1. The rules
-- =============================================================================
CREATE OR REPLACE TABLE CORE.RULESETS (
    ID               NUMBER(10,0)  NOT NULL,
    NAME             VARCHAR(100)  NOT NULL,
    RULE_DEFINITION  VARIANT       NOT NULL,
    PRIMARY KEY (ID)
);

INSERT INTO CORE.RULESETS (ID, NAME, RULE_DEFINITION)
SELECT v.ID, v.NAME, PARSE_JSON(v.RULE_DEFINITION)
FROM (VALUES
    ( 1, 'Energy Procurement',  '{"AccountNumber": ["600*", "610*"]}'),
    ( 2, 'Maintenance',         '{"AccountNumber": "630*"}'),
    ( 3, 'IT & Telecom',        '{"AccountNumber": "64*"}'),
    ( 4, 'External Services',   '{"AccountNumber": "650*", "ExternalSupplier": true}'),
    ( 5, 'Facility',            '{"AccountNumber": "660*"}'),
    ( 6, 'Travel',              '{"AccountNumber": "670*"}'),
    ( 7, 'Wages & Salaries',    '{"AccountNumber": "68*", "ExternalSupplier": false}'),
    ( 8, 'Training',            '{"AccountNumber": "684*"}'),
    ( 9, 'Depreciation',        '{"AccountNumber": "690*"}')
) AS v (ID, NAME, RULE_DEFINITION)

-- =============================================================================
-- 2. The result
-- =============================================================================
CREATE OR REPLACE TABLE CORE.DOCUMENT_COST_TYPES (
    DOCUMENT_ID    VARCHAR(10)   NOT NULL,
    COST_TYPE      VARCHAR(100)  NOT NULL,
    RULESET_ID     NUMBER(10,0)  NOT NULL,
    CLASSIFIED_AT  TIMESTAMP_NTZ NOT NULL
);

-- =============================================================================
-- 3. The Python code and the procedure
-- =============================================================================
CREATE STAGE IF NOT EXISTS CORE.PYTHON_CODE;

--- Upload python code to the stage

CREATE OR REPLACE PROCEDURE CORE.SP_CLASSIFY_DOCUMENTS()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
IMPORTS = ('@FIN_COST_REPORTING.CORE.PYTHON_CODE/classify_documents.py')
HANDLER = 'classify_documents.classify';

-- =============================================================================
-- 4. A report view: one row per document, always one cost type
--    (none -> 'Unclassified', several -> 'Several cost types', so nothing is counted twice)
-- =============================================================================
CREATE OR REPLACE VIEW CORE.V_DOCUMENTS_CLASSIFIED AS
WITH cost_types AS (
    SELECT DOCUMENT_ID,
           COUNT(DISTINCT COST_TYPE) AS COST_TYPE_COUNT,
           MIN(COST_TYPE)            AS COST_TYPE
    FROM CORE.DOCUMENT_COST_TYPES
    GROUP BY DOCUMENT_ID
)
SELECT
    d.*,
    CASE
        WHEN c.COST_TYPE_COUNT = 1 THEN c.COST_TYPE
        WHEN c.COST_TYPE_COUNT > 1 THEN 'Several cost types'
        ELSE 'Unclassified'
    END                                AS COST_TYPE,
    COALESCE(c.COST_TYPE_COUNT, 0)     AS COST_TYPE_COUNT
FROM CORE.DOCUMENTS_ENRICHED d
LEFT JOIN cost_types c
       ON c.DOCUMENT_ID = d.DOCUMENT_ID;

-- =============================================================================
-- Run it and check the result
-- =============================================================================

CALL CORE.SP_CLASSIFY_DOCUMENTS();
