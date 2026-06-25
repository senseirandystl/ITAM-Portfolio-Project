-- ============================================================================
-- 07_maintenance.sql
-- IT Asset Management Database - Maintenance, Monitoring, and Optimization
-- Author: Randall James
-- Purpose: Demonstrate database health management, bloat control, and monitoring queries
-- These scripts would be scheduled via cron, pgAgent, or orchestration tool in production
-- ============================================================================

-- ============================================================================
-- 1. VACUUM & ANALYZE (Core maintenance - run regularly)
-- ============================================================================
-- Full vacuum reclaims space and updates statistics. Use during maintenance window.
-- For large tables, consider VACUUM (FULL, ANALYZE) but it locks tables.

VACUUM ANALYZE assets;
VACUUM ANALYZE employees;
VACUUM ANALYZE maintenance_records;
VACUUM ANALYZE license_allocations;
VACUUM ANALYZE audit_logs;

-- Targeted vacuum on high-churn tables (allocations and maintenance grow over time)
VACUUM (ANALYZE, VERBOSE) license_allocations;
VACUUM (ANALYZE, VERBOSE) maintenance_records;

-- ============================================================================
-- 2. REINDEX (when bloat suspected or after heavy deletes/updates)
-- ============================================================================
-- REINDEX TABLE CONCURRENTLY is preferred in production (allows reads/writes during rebuild)
-- Note: CONCURRENTLY cannot be used inside transaction; run directly.

-- REINDEX TABLE CONCURRENTLY assets;
-- REINDEX TABLE CONCURRENTLY maintenance_records;

-- Quick check of index bloat (approximate)
SELECT 
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    pg_size_pretty(pg_relation_size(relid)) AS table_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;

-- ============================================================================
-- 3. MONITORING QUERIES (run these regularly or via monitoring tool)
-- ============================================================================

-- Table bloat estimation (helps decide when to VACUUM FULL or reindex)
-- Source: https://wiki.postgresql.org/wiki/Show_database_bloat (simplified)
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname || '.' || tablename)) AS table_size,
    pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename) - pg_relation_size(schemaname || '.' || tablename)) AS index_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC;

-- Dead tuple / bloat check on key tables
SELECT 
    relname AS table_name,
    n_live_tup AS live_rows,
    n_dead_tup AS dead_rows,
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_pct,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
WHERE relname IN ('assets', 'license_allocations', 'maintenance_records', 'audit_logs')
ORDER BY n_dead_tup DESC;

-- Index usage stats (identify unused indexes to drop)
SELECT 
    schemaname,
    relname AS tablename,
    indexrelname AS indexname,
    idx_scan AS index_scans,
    idx_tup_read,
    idx_tup_fetch,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
  AND idx_scan < 50  -- Low usage threshold; adjust for your workload
ORDER BY idx_scan, pg_relation_size(indexrelid) DESC;

-- ============================================================================
-- 4. SLOW QUERY / PERFORMANCE (requires pg_stat_statements extension)
-- ============================================================================
-- Enable in postgresql.conf: shared_preload_libraries = 'pg_stat_statements'
-- Then: CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Top 10 slowest queries by total time (example)
-- SELECT 
--     query,
--     calls,
--     total_exec_time,
--     mean_exec_time,
--     rows,
--     100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0) AS hit_percent
-- FROM pg_stat_statements
-- ORDER BY total_exec_time DESC
-- LIMIT 10;

-- ============================================================================
-- 5. LONG-RUNNING TRANSACTIONS & LOCKS (operational health)
-- ============================================================================
SELECT 
    pid,
    usename,
    application_name,
    client_addr,
    state,
    query_start,
    NOW() - query_start AS duration,
    query
FROM pg_stat_activity
WHERE state != 'idle'
  AND query NOT ILIKE '%pg_stat_activity%'
ORDER BY duration DESC;

-- Lock monitoring
SELECT 
    blocked_locks.pid AS blocked_pid,
    blocked_activity.usename AS blocked_user,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    blocked_activity.query AS blocked_query,
    blocking_activity.query AS blocking_query
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks 
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.GRANTED;

-- ============================================================================
-- 6. AUDIT LOG MAINTENANCE (partitioning or archival strategy)
-- ============================================================================
-- For production: Partition audit_logs by month or year using declarative partitioning.
-- Example skeleton (run once at schema design time):

-- CREATE TABLE audit_logs_y2026m06 PARTITION OF audit_logs
--     FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

-- Then schedule monthly archival job:
-- 1. Create new partition for next month
-- 2. Detach old partition after retention period (e.g., 24 months)
-- 3. Dump detached partition to cold storage / S3 / compressed file
-- 4. Drop old partition

-- Simple retention example (delete logs older than 3 years - adjust per policy)
-- DELETE FROM audit_logs WHERE changed_at < CURRENT_DATE - INTERVAL '3 years';

-- ============================================================================
-- 7. RECOMMENDED PRODUCTION MAINTENANCE SCHEDULE
-- ============================================================================
-- Daily (low traffic window, e.g., 2-4 AM):
--   VACUUM (ANALYZE) on high-churn tables (license_allocations, maintenance_records)
--
-- Weekly:
--   Full VACUUM ANALYZE on all tables
--   REINDEX CONCURRENTLY on fragmented indexes (if monitoring shows bloat)
--   Run monitoring queries above and alert on dead_pct > 15% or unused indexes
--
-- Monthly:
--   Review pg_stat_statements for new slow queries
--   Archive/delete old audit_logs per retention policy
--   Update table statistics manually if autovacuum seems insufficient
--
-- Quarterly:
--   Full REINDEX of database during planned maintenance window
--   Review and prune unused indexes
--   Capacity planning review (table growth, index size)

-- ============================================================================
-- End of maintenance scripts
-- ============================================================================
SELECT 'Database maintenance routines documented and example commands executed. Schedule these in production via cron or pg_cron for ongoing health.' AS status;