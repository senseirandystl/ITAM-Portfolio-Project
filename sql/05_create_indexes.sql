-- ============================================================================
-- 05_create_indexes.sql
-- IT Asset Management Database - Strategic Indexing for Analytical Workloads
-- Author: Randall James
-- Purpose: Optimize the most common filter, join, and sort patterns used by data analysts
-- Run after data is loaded
-- ============================================================================

-- ============================================================================
-- INDEXING STRATEGY NOTES
-- ============================================================================
-- Indexes have maintenance and storage cost. We add only those justified by realistic query patterns:
-- 1. High-cardinality columns used in WHERE / JOIN (asset_tag, serial_number, email)
-- 2. Low-to-medium cardinality columns frequently filtered (status, department_id, assigned_to_employee_id)
-- 3. Date columns used for range scans and time-series analysis (purchase_date, maintenance_date, expiration_date)
-- 4. Composite indexes for common multi-column filters (status + assigned_to, department + status)
-- 5. Partial indexes where only a subset of rows are queried (active assets, active allocations)
-- 6. GIN index on JSONB audit data for potential JSON queries (advanced)

-- ============================================================================
-- HIGH-CARDINALITY / UNIQUE-LOOKUP INDEXES (already partially covered by PK/UK constraints)
-- ============================================================================
-- PKs and UNIQUE constraints already create indexes. We add explicit ones only where INCLUDE or partial is beneficial.

-- Fast lookup by human-readable asset tag (very common in IT support tickets)
CREATE INDEX IF NOT EXISTS idx_assets_asset_tag 
    ON assets (asset_tag);

-- Serial number search (warranty claims, procurement verification)
CREATE INDEX IF NOT EXISTS idx_assets_serial_number 
    ON assets (serial_number) 
    WHERE serial_number IS NOT NULL;

-- Employee email lookup (common in join or search)
CREATE INDEX IF NOT EXISTS idx_employees_email 
    ON employees (email);

-- ============================================================================
-- FILTER & JOIN INDEXES (most important for analyst queries)
-- ============================================================================

-- Asset status filtering (very common: "show me all In Use assets")
CREATE INDEX IF NOT EXISTS idx_assets_status 
    ON assets (status);

-- Composite: status + employee assignment (dashboard of currently assigned assets)
CREATE INDEX IF NOT EXISTS idx_assets_status_assigned 
    ON assets (status, assigned_to_employee_id) 
    INCLUDE (purchase_cost, asset_type_id, warranty_end_date);

-- Employee department (department-level rollups and filters)
CREATE INDEX IF NOT EXISTS idx_employees_department 
    ON employees (department_id);

-- Asset type dimension (grouping and filtering by category)
CREATE INDEX IF NOT EXISTS idx_assets_asset_type 
    ON assets (asset_type_id);

-- License expiration (compliance reporting - "licenses expiring in next 90 days")
CREATE INDEX IF NOT EXISTS idx_software_licenses_expiration 
    ON software_licenses (expiration_date) 
    WHERE expiration_date IS NOT NULL;

-- Maintenance date range queries and time-series
CREATE INDEX IF NOT EXISTS idx_maintenance_date 
    ON maintenance_records (maintenance_date DESC);

-- Composite for asset + date (common in maintenance history queries)
CREATE INDEX IF NOT EXISTS idx_maintenance_asset_date 
    ON maintenance_records (asset_id, maintenance_date DESC);

-- License allocation active status (partial index for current allocations only)
CREATE INDEX IF NOT EXISTS idx_license_allocations_active 
    ON license_allocations (license_id, employee_id) 
    WHERE returned_date IS NULL;

-- Department + status for employee headcount + asset reports
CREATE INDEX IF NOT EXISTS idx_employees_dept_status 
    ON employees (department_id, status);

-- ============================================================================
-- PARTIAL INDEXES (space-efficient, high selectivity)
-- ============================================================================

-- Only index active (non-retired) assets - most queries exclude retired
CREATE INDEX IF NOT EXISTS idx_assets_active_only 
    ON assets (assigned_to_employee_id, status) 
    WHERE status IN ('In Use', 'In Storage', 'Under Maintenance');

-- Only index non-returned license allocations
CREATE INDEX IF NOT EXISTS idx_allocations_current 
    ON license_allocations (allocated_date DESC) 
    WHERE returned_date IS NULL;

-- ============================================================================
-- JSONB INDEX (for audit_logs - demonstrates advanced Postgres capability)
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_audit_logs_table_action 
    ON audit_logs (table_name, action);

-- GIN index on JSONB for flexible queries like "find all changes where old_data->>'status' = 'In Use'"
CREATE INDEX IF NOT EXISTS idx_audit_logs_old_data_gin 
    ON audit_logs USING GIN (old_data jsonb_path_ops);

CREATE INDEX IF NOT EXISTS idx_audit_logs_new_data_gin 
    ON audit_logs USING GIN (new_data jsonb_path_ops);

-- ============================================================================
-- COVERING INDEXES (INCLUDE columns to avoid heap fetches)
-- ============================================================================
-- Already used in idx_assets_status_assigned above.

-- ============================================================================
-- VERIFICATION & MAINTENANCE
-- ============================================================================

-- After creating indexes, always ANALYZE to update statistics
ANALYZE assets;
ANALYZE employees;
ANALYZE maintenance_records;
ANALYZE software_licenses;
ANALYZE license_allocations;

-- Verification query (FINAL FIX)
SELECT 
    schemaname,
    relname AS tablename,
    indexrelname AS indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 20;

SELECT 'Strategic indexes created and statistics updated. Query planner will now use these for common analytical patterns.' AS status;
