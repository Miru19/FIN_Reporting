CREATE OR REPLACE PROCEDURE CORE.SP_REFRESH_DOCUMENTS_ENRICHED(P_SIMULATE_ERROR BOOLEAN DEFAULT FALSE)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    v_started_at    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP();
    v_rows_before   NUMBER        DEFAULT 0;
    v_rows_loaded   NUMBER        DEFAULT 0;
    v_total_amount  NUMBER(38,2)  DEFAULT 0;
    v_result        VARIANT;
    empty_result    EXCEPTION (-20001, 'The view returned no rows, so the table was left as it was');
    simulated_error EXCEPTION (-20002, 'Simulated error after the delete, to show that the rollback restores the table');
BEGIN
    SELECT COUNT(*) INTO :v_rows_before
    FROM FIN_COST_REPORTING.CORE.DOCUMENTS_ENRICHED;

    BEGIN TRANSACTION;

    DELETE FROM FIN_COST_REPORTING.CORE.DOCUMENTS_ENRICHED;

    IF (P_SIMULATE_ERROR) THEN
        RAISE simulated_error;
    END IF;

    INSERT INTO FIN_COST_REPORTING.CORE.DOCUMENTS_ENRICHED
    SELECT v.*, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
    FROM FIN_COST_REPORTING.CORE.V_DOCUMENTS_ENRICHED v;

    SELECT COUNT(*), COALESCE(SUM(AMOUNT), 0) INTO :v_rows_loaded, :v_total_amount
    FROM FIN_COST_REPORTING.CORE.DOCUMENTS_ENRICHED;

    IF (v_rows_loaded = 0) THEN
        RAISE empty_result;
    END IF;

    COMMIT;

    SELECT OBJECT_CONSTRUCT(
        'status',        'SUCCEEDED',
        'rows_before',   :v_rows_before,
        'rows_loaded',   :v_rows_loaded,
        'total_amount',  :v_total_amount,
        'started_at',    :v_started_at,
        'duration_s',    DATEDIFF('millisecond', :v_started_at, CURRENT_TIMESTAMP()) / 1000)
    INTO :v_result;

    RETURN v_result;

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;

-- =============================================================================
-- Tests: run the statements one at a time
-- =============================================================================

-- 1. First load: rows_before 0, rows_loaded 1200
CALL CORE.SP_REFRESH_DOCUMENTS_ENRICHED();

-- 2. Error simulation: the table is left as it was, with the same LOADED_AT
CALL CORE.SP_REFRESH_DOCUMENTS_ENRICHED(TRUE);

SELECT COUNT(*) AS ROWS_IN_TABLE, MAX(LOADED_AT) AS LOADED_AT
FROM CORE.DOCUMENTS_ENRICHED;
