CREATE OR REPLACE TABLE CORE.DOCUMENTS_ENRICHED (
    DOCUMENT_ID                  VARCHAR(10)   NOT NULL,

    -- Period
    FISCAL_YEAR                  NUMBER(4,0)   NOT NULL,
    BOOKING_PERIOD               NUMBER(2,0)   NOT NULL,
    PERIOD_LABEL                 VARCHAR(7),
    PERIOD_START_DATE            DATE,
    PERIOD_END_DATE              DATE,
    QUARTER_START_DATE           DATE,
    MONTHS_BEFORE_LATEST_PERIOD  NUMBER(4,0),

    -- Account and organisation
    ACCOUNT_NUMBER               VARCHAR(10)   NOT NULL,
    ACCOUNT_GROUP                VARCHAR(2),
    PROFIT_CENTER                VARCHAR(10),
    COST_CENTER                  VARCHAR(10),
    COST_CENTER_NAME             VARCHAR(100),
    ORG_UNIT                     VARCHAR(10),
    FUNDING_SOURCE               VARCHAR(10),

    -- Supplier
    EXTERNAL_SUPPLIER_ID         VARCHAR(10),
    IS_EXTERNAL_SUPPLIER         BOOLEAN,
    SUPPLIER_NAME                VARCHAR(100),
    SUPPLIER_DOCUMENTS_IN_YEAR   NUMBER(10,0),
    SUPPLIER_SPEND_IN_YEAR       NUMBER(18,2),

    -- Amount
    AMOUNT                       NUMBER(18,2)  NOT NULL,
    AMOUNT_BAND                  VARCHAR(30),
    PCT_OF_COST_CENTER_YEAR      NUMBER(10,2),

    DOCUMENT_DETAILS             VARCHAR(200),

    LOADED_AT                    TIMESTAMP_NTZ NOT NULL,

    PRIMARY KEY (DOCUMENT_ID)
);
