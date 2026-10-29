-- =============================================================================
-- 1. Create
-- =============================================================================
CREATE OR REPLACE TASK CORE.T_REFRESH_DOCUMENTS_ENRICHED
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
    SCHEDULE = 'USING CRON 0 6 * * * Europe/Bucharest'
    USER_TASK_TIMEOUT_MS = 600000
    COMMENT = 'Exercise 4: daily full refresh of CORE.DOCUMENTS_ENRICHED'
AS
    CALL FIN_COST_REPORTING.CORE.SP_REFRESH_DOCUMENTS_ENRICHED();

SHOW TASKS LIKE 'T_REFRESH_DOCUMENTS_ENRICHED' IN SCHEMA CORE;  

-- =============================================================================
-- 2. Test it manually
-- =============================================================================
EXECUTE TASK CORE.T_REFRESH_DOCUMENTS_ENRICHED;

-- =============================================================================
-- 3. Check the runs
-- =============================================================================
SELECT NAME, STATE, SCHEDULED_FROM, SCHEDULED_TIME, COMPLETED_TIME, ERROR_CODE, ERROR_MESSAGE
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
        TASK_NAME => 'T_REFRESH_DOCUMENTS_ENRICHED',
        RESULT_LIMIT => 20))
ORDER BY SCHEDULED_TIME DESC;

-- =============================================================================
-- 4. Activate: from now on it runs every day at 06:00
-- =============================================================================
ALTER TASK CORE.T_REFRESH_DOCUMENTS_ENRICHED RESUME;

-- =============================================================================
-- 5. Investigate a failed run
-- =============================================================================
ALTER TASK CORE.T_REFRESH_DOCUMENTS_ENRICHED MODIFY AS
    CALL FIN_COST_REPORTING.CORE.SP_REFRESH_DOCUMENTS_ENRICHED(TRUE);      -- the switch that simulates an error

EXECUTE TASK CORE.T_REFRESH_DOCUMENTS_ENRICHED;

SELECT NAME, STATE, SCHEDULED_TIME, ERROR_CODE, ERROR_MESSAGE
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
        TASK_NAME => 'T_REFRESH_DOCUMENTS_ENRICHED',
        ERROR_ONLY => TRUE,
        RESULT_LIMIT => 10))
ORDER BY SCHEDULED_TIME DESC;
