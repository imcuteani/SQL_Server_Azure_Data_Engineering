--Monitor resource use
--You can monitor resource usage at the database level using the following DMVs.

--sys.dm_db_resource_stats
--Because this view provides granular resource usage data, use sys.dm_db_resource_stats first for any current-state analysis or troubleshooting. For example, this query shows the average and maximum resource use for the current database over the past hour:

SELECT DB_NAME() AS database_name,
       AVG(avg_cpu_percent) AS 'Average CPU use in percent',
       MAX(avg_cpu_percent) AS 'Maximum CPU use in percent',
       AVG(avg_data_io_percent) AS 'Average data IO in percent',
       MAX(avg_data_io_percent) AS 'Maximum data IO in percent',
       AVG(avg_log_write_percent) AS 'Average log write use in percent',
       MAX(avg_log_write_percent) AS 'Maximum log write use in percent',
       AVG(avg_memory_usage_percent) AS 'Average memory use in percent',
       MAX(avg_memory_usage_percent) AS 'Maximum memory use in percent',
       MAX(max_worker_percent) AS 'Maximum worker use in percent'
FROM sys.dm_db_resource_stats;


--Similarly to sys.dm_db_resource_stats, sys.dm_elastic_pool_resource_stats provides recent and granular resource usage data for an Azure SQL Database elastic pool. 

SELECT dso.elastic_pool_name,
       AVG(eprs.avg_cpu_percent) AS avg_cpu_percent,
       MAX(eprs.avg_cpu_percent) AS max_cpu_percent,
       AVG(eprs.avg_data_io_percent) AS avg_data_io_percent,
       MAX(eprs.avg_data_io_percent) AS max_data_io_percent,
       AVG(eprs.avg_log_write_percent) AS avg_log_write_percent,
       MAX(eprs.avg_log_write_percent) AS max_log_write_percent,
       MAX(eprs.max_worker_percent) AS max_worker_percent,
       MAX(eprs.used_storage_percent) AS max_used_storage_percent,
       MAX(eprs.allocated_storage_percent) AS max_allocated_storage_percent
FROM sys.dm_elastic_pool_resource_stats AS eprs
    CROSS JOIN sys.database_service_objectives AS dso
WHERE eprs.end_time >= DATEADD(minute, -15, GETUTCDATE())
GROUP BY dso.elastic_pool_name;

--Concurrent requests

SELECT COUNT(*) AS [Concurrent_Requests]
FROM sys.dm_exec_requests;

--Average request rate

DECLARE @DbRequestSnapshot TABLE (
        database_name sysname PRIMARY KEY,
        total_request_count bigint NOT NULL,
        snapshot_time datetime2 NOT NULL DEFAULT (SYSDATETIME())
);

INSERT INTO @DbRequestSnapshot
(
database_name,
total_request_count
)
SELECT rg.database_name,
       wg.total_request_count
FROM sys.dm_resource_governor_workload_groups AS wg
INNER JOIN sys.dm_user_db_resource_governance AS rg
ON wg.name = CONCAT('UserPrimaryGroup.DBId', rg.database_id);

WAITFOR DELAY '00:00:30';

SELECT rg.database_name,
       (wg.total_request_count - drs.total_request_count) / DATEDIFF(second, drs.snapshot_time, SYSDATETIME()) AS requests_per_second
FROM sys.dm_resource_governor_workload_groups AS wg
INNER JOIN sys.dm_user_db_resource_governance AS rg
ON wg.name = CONCAT('UserPrimaryGroup.DBId', rg.database_id)
INNER JOIN @DbRequestSnapshot AS drs
ON rg.database_name = drs.database_name;

-- recent history of query 

SELECT rg.database_name,
       wg.snapshot_time,
       wg.active_request_count,
       wg.active_worker_count,
       wg.active_session_count,
       CAST (wg.delta_request_count AS DECIMAL) / duration_ms * 1000 AS requests_per_second
FROM sys.dm_resource_governor_workload_groups_history_ex AS wg
     INNER JOIN sys.dm_user_db_resource_governance AS rg
         ON wg.name = CONCAT('UserPrimaryGroup.DBId', rg.database_id)
ORDER BY snapshot_time DESC;

-- calculate database & object size 

-- Calculates the size of the database.
SELECT SUM(CAST (FILEPROPERTY(name, 'SpaceUsed') AS BIGINT) * 8192.) / 1024 / 1024 AS size_mb
FROM sys.database_files
WHERE type_desc = 'ROWS';

-- Identify CPU performance Issues 

PRINT '-- top 10 Active CPU Consuming Queries (aggregated)--';
SELECT TOP 10 GETDATE() AS runtime,
              *
FROM (SELECT query_stats.query_hash,
             SUM(query_stats.cpu_time) AS 'Total_Request_Cpu_Time_Ms',
             SUM(logical_reads) AS 'Total_Request_Logical_Reads',
             MIN(start_time) AS 'Earliest_Request_start_Time',
             COUNT(*) AS 'Number_Of_Requests',
             SUBSTRING(REPLACE(REPLACE(MIN(query_stats.statement_text), CHAR(10), ' '), CHAR(13), ' '), 1, 256) AS "Statement_Text"
      FROM (SELECT req.*,
                   SUBSTRING(ST.text, (req.statement_start_offset / 2) + 1, ((CASE statement_end_offset WHEN -1 THEN DATALENGTH(ST.text) ELSE req.statement_end_offset END - req.statement_start_offset) / 2) + 1) AS statement_text
            FROM sys.dm_exec_requests AS req
                CROSS APPLY sys.dm_exec_sql_text(req.sql_handle) AS ST) AS query_stats
      GROUP BY query_hash) AS t
ORDER BY Total_Request_Cpu_Time_Ms DESC;

-- Long running queries 

PRINT '--top 10 Active CPU Consuming Queries by sessions--';
SELECT TOP 10 req.session_id, req.start_time, cpu_time 'cpu_time_ms', OBJECT_NAME(ST.objectid, ST.dbid) 'ObjectName', SUBSTRING(REPLACE(REPLACE(SUBSTRING(ST.text, (req.statement_start_offset / 2)+1, ((CASE statement_end_offset WHEN -1 THEN DATALENGTH(ST.text)ELSE req.statement_end_offset END-req.statement_start_offset)/ 2)+1), CHAR(10), ' '), CHAR(13), ' '), 1, 512) AS statement_text
FROM sys.dm_exec_requests AS req
    CROSS APPLY sys.dm_exec_sql_text(req.sql_handle) AS ST
ORDER BY cpu_time DESC;
GO

-- CPU issues occured in the past 

-- Top 15 CPU consuming queries by query hash
-- Note that a query hash can have many query ids if not parameterized or not parameterized properly
WITH AggregatedCPU
AS (SELECT q.query_hash,
           SUM(count_executions * avg_cpu_time / 1000.0) AS total_cpu_ms,
           SUM(count_executions * avg_cpu_time / 1000.0) / SUM(count_executions) AS avg_cpu_ms,
           MAX(rs.max_cpu_time / 1000.00) AS max_cpu_ms,
           MAX(max_logical_io_reads) AS max_logical_reads,
           COUNT(DISTINCT p.plan_id) AS number_of_distinct_plans,
           COUNT(DISTINCT p.query_id) AS number_of_distinct_query_ids,
           SUM(CASE WHEN rs.execution_type_desc = 'Aborted' THEN count_executions ELSE 0 END) AS Aborted_Execution_Count,
           SUM(CASE WHEN rs.execution_type_desc = 'Regular' THEN count_executions ELSE 0 END) AS Regular_Execution_Count,
           SUM(CASE WHEN rs.execution_type_desc = 'Exception' THEN count_executions ELSE 0 END) AS Exception_Execution_Count,
           SUM(count_executions) AS total_executions,
           MIN(qt.query_sql_text) AS sampled_query_text
    FROM sys.query_store_query_text AS qt
         INNER JOIN sys.query_store_query AS q
             ON qt.query_text_id = q.query_text_id
         INNER JOIN sys.query_store_plan AS p
             ON q.query_id = p.query_id
         INNER JOIN sys.query_store_runtime_stats AS rs
             ON rs.plan_id = p.plan_id
         INNER JOIN sys.query_store_runtime_stats_interval AS rsi
             ON rsi.runtime_stats_interval_id = rs.runtime_stats_interval_id
    WHERE rs.execution_type_desc IN ('Regular', 'Aborted', 'Exception')
          AND rsi.start_time >= DATEADD(HOUR, -2, GETUTCDATE())
    GROUP BY q.query_hash),
 OrderedCPU
AS (SELECT query_hash,
           total_cpu_ms,
           avg_cpu_ms,
           max_cpu_ms,
           max_logical_reads,
           number_of_distinct_plans,
           number_of_distinct_query_ids,
           total_executions,
           Aborted_Execution_Count,
           Regular_Execution_Count,
           Exception_Execution_Count,
           sampled_query_text,
           ROW_NUMBER() OVER (ORDER BY total_cpu_ms DESC, query_hash ASC) AS query_hash_row_number
    FROM AggregatedCPU)
SELECT OD.query_hash,
       OD.total_cpu_ms,
       OD.avg_cpu_ms,
       OD.max_cpu_ms,
       OD.max_logical_reads,
       OD.number_of_distinct_plans,
       OD.number_of_distinct_query_ids,
       OD.total_executions,
       OD.Aborted_Execution_Count,
       OD.Regular_Execution_Count,
       OD.Exception_Execution_Count,
       OD.sampled_query_text,
       OD.query_hash_row_number
FROM OrderedCPU AS OD
WHERE OD.query_hash_row_number <= 15 --get top 15 rows by total_cpu_ms
ORDER BY total_cpu_ms DESC

--identify log IO issue 

SELECT DB_NAME() AS database_name,
       end_time AS UTC_time,
       rs.avg_data_io_percent AS 'Data IO In % of Limit',
       rs.avg_log_write_percent AS 'Log Write Utilization In % of Limit'
FROM sys.dm_db_resource_stats AS rs --past hour only
ORDER BY rs.end_time DESC;

-- view buffer related issue -- 

-- Top queries that waited on buffer
-- Note these are finished queries
WITH Aggregated AS (SELECT q.query_hash, SUM(total_query_wait_time_ms) total_wait_time_ms, SUM(total_query_wait_time_ms / avg_query_wait_time_ms) AS total_executions, MIN(qt.query_sql_text) AS sampled_query_text, MIN(wait_category_desc) AS wait_category_desc
                    FROM sys.query_store_query_text AS qt
                         INNER JOIN sys.query_store_query AS q ON qt.query_text_id=q.query_text_id
                         INNER JOIN sys.query_store_plan AS p ON q.query_id=p.query_id
                         INNER JOIN sys.query_store_wait_stats AS waits ON waits.plan_id=p.plan_id
                         INNER JOIN sys.query_store_runtime_stats_interval AS rsi ON rsi.runtime_stats_interval_id=waits.runtime_stats_interval_id
                    WHERE wait_category_desc='Buffer IO' AND rsi.start_time>=DATEADD(HOUR, -2, GETUTCDATE())
                    GROUP BY q.query_hash), Ordered AS (SELECT query_hash, total_executions, total_wait_time_ms, sampled_query_text, wait_category_desc, ROW_NUMBER() OVER (ORDER BY total_wait_time_ms DESC, query_hash ASC) AS query_hash_row_number
                                                        FROM Aggregated)
SELECT OD.query_hash, OD.total_executions, OD.total_wait_time_ms, OD.sampled_query_text, OD.wait_category_desc, OD.query_hash_row_number
FROM Ordered AS OD
WHERE OD.query_hash_row_number <= 15 -- get top 15 rows by total_wait_time_ms
ORDER BY total_wait_time_ms DESC;
GO

-- identify long running transactions -- 

SELECT DB_NAME(dtr.database_id) AS 'database_name',
       sess.session_id,
       atr.name AS 'tran_name',
       atr.transaction_id,
       transaction_type,
       transaction_begin_time,
       database_transaction_begin_time,
       transaction_state,
       is_user_transaction,
       sess.open_transaction_count,
       TRIM(REPLACE(
                REPLACE(
                            SUBSTRING(
                                        SUBSTRING(
                                                    txt.text,
                                                    (req.statement_start_offset / 2) + 1,
                                                    ((CASE req.statement_end_offset
                                                            WHEN -1 THEN
                                                                DATALENGTH(txt.text)
                                                            ELSE
                                                                req.statement_end_offset
                                                        END - req.statement_start_offset
                                                    ) / 2
                                                    ) + 1
                                                ),
                                        1,
                                        1000
                                    ),
                            CHAR(10),
                            ' '
                        ),
                CHAR(13),
                ' '
            )
            ) Running_stmt_text,
       recenttxt.text 'MostRecentSQLText'
FROM sys.dm_tran_active_transactions AS atr
     INNER JOIN sys.dm_tran_database_transactions AS dtr
         ON dtr.transaction_id = atr.transaction_id
     LEFT OUTER JOIN sys.dm_tran_session_transactions AS sess
         ON sess.transaction_id = atr.transaction_id
     LEFT OUTER JOIN sys.dm_exec_requests AS req
         ON req.session_id = sess.session_id
        AND req.transaction_id = sess.transaction_id
     LEFT OUTER JOIN sys.dm_exec_connections AS conn
         ON sess.session_id = conn.session_id
OUTER APPLY sys.dm_exec_sql_text(req.sql_handle) AS txt
OUTER APPLY sys.dm_exec_sql_text(conn.most_recent_sql_handle) AS recenttxt
WHERE atr.transaction_type != 2
      AND sess.session_id != @@spid
ORDER BY start_time ASC;

-- identify if resource_semaphore top wait

SELECT wait_type,
       SUM(wait_time) AS total_wait_time_ms
FROM sys.dm_exec_requests AS req
     INNER JOIN sys.dm_exec_sessions AS sess
         ON req.session_id = sess.session_id
WHERE is_user_process = 1
GROUP BY wait_type
ORDER BY SUM(wait_time) DESC;

-- identify top active 10 memory grants 

SELECT TOP 10 CONVERT(VARCHAR(30), GETDATE(), 121) AS runtime,
              r.session_id,
              r.blocking_session_id,
              r.cpu_time,
              r.total_elapsed_time,
              r.reads,
              r.writes,
              r.logical_reads,
              r.row_count,
              wait_time,
              wait_type,
              r.command,
              OBJECT_NAME(txt.objectid, txt.dbid) 'Object_Name',
              TRIM(REPLACE(REPLACE(SUBSTRING(SUBSTRING(TEXT, (r.statement_start_offset / 2) + 1, 
               (  (
                   CASE r.statement_end_offset
                       WHEN - 1
                           THEN DATALENGTH(TEXT)
                       ELSE r.statement_end_offset
                       END - r.statement_start_offset
                   ) / 2
               ) + 1), 1, 1000), CHAR(10), ' '), CHAR(13), ' ')) AS stmt_text,
              mg.dop,                                               --Degree of parallelism
              mg.request_time,                                      --Date and time when this query requested the memory grant.
              mg.grant_time,                                        --NULL means memory has not been granted
              mg.requested_memory_kb / 1024.0 requested_memory_mb,  --Total requested amount of memory in megabytes
              mg.granted_memory_kb / 1024.0 AS granted_memory_mb,   --Total amount of memory actually granted in megabytes. NULL if not granted
              mg.required_memory_kb / 1024.0 AS required_memory_mb, --Minimum memory required to run this query in megabytes.
              max_used_memory_kb / 1024.0 AS max_used_memory_mb,
              mg.query_cost,                                        --Estimated query cost.
              mg.timeout_sec,                                       --Time-out in seconds before this query gives up the memory grant request.
              mg.resource_semaphore_id,                             --Non-unique ID of the resource semaphore on which this query is waiting.
              mg.wait_time_ms,                                      --Wait time in milliseconds. NULL if the memory is already granted.
              CASE mg.is_next_candidate                             --Is this process the next candidate for a memory grant
                  WHEN 1 THEN 'Yes'
                  WHEN 0 THEN 'No'
                  ELSE 'Memory has been granted'
              END AS 'Next Candidate for Memory Grant',
              qp.query_plan
FROM sys.dm_exec_requests AS r
     INNER JOIN sys.dm_exec_query_memory_grants AS mg
         ON r.session_id = mg.session_id
        AND r.request_id = mg.request_id
CROSS APPLY sys.dm_exec_sql_text(mg.sql_handle) AS txt
CROSS APPLY sys.dm_exec_query_plan(r.plan_handle) AS qp
ORDER BY mg.granted_memory_kb DESC;

-- find top queries by CPU time -- 

SELECT TOP 15 query_stats.query_hash AS Query_Hash,
              SUM(query_stats.total_worker_time) / SUM(query_stats.execution_count) AS Avg_CPU_Time,
              MIN(query_stats.statement_text) AS Statement_Text
FROM (SELECT QS.*,
             SUBSTRING(ST.text, (QS.statement_start_offset / 2) + 1, (
             (CASE statement_end_offset
                 WHEN -1 THEN DATALENGTH(ST.text)
                 ELSE QS.statement_end_offset END
              - QS.statement_start_offset) / 2) + 1) AS statement_text
      FROM sys.dm_exec_query_stats AS QS
          CROSS APPLY sys.dm_exec_sql_text(QS.sql_handle) AS ST) AS query_stats
GROUP BY query_stats.query_hash
ORDER BY Avg_CPU_Time DESC;