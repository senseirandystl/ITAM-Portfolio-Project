-- ============================================================================
-- 04_create_roles.sql
-- IT Asset Management Database - Role-Based Access Control (RBAC)
-- Author: Randall James
-- Purpose: Demonstrate separation of duties and least-privilege access for Data Analysts vs Admins
-- Run after schema and seed data
-- ============================================================================

-- ============================================================================
-- ROLES
-- ============================================================================

-- Read-only analyst role (ideal for data analysts, reporting tools, dashboards)
CREATE ROLE it_data_analyst WITH
    LOGIN
    NOSUPERUSER
    INHERIT
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    PASSWORD 'AnalystReadOnly2026!';

COMMENT ON ROLE it_data_analyst IS 'Read-only access for data analysts and reporting tools. Can query all tables and views but cannot modify data.';

-- IT Administrator role (full operational control)
CREATE ROLE it_admin WITH
    LOGIN
    NOSUPERUSER
    INHERIT
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    PASSWORD 'ITAdminFullAccess2026!';

COMMENT ON ROLE it_admin IS 'IT operations administrators. Full read/write on asset, license, and maintenance tables.';

-- Auditor / Compliance role (read access with broader visibility, often for external audits)
CREATE ROLE it_auditor WITH
    LOGIN
    NOSUPERUSER
    INHERIT
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    PASSWORD 'AuditorReadOnly2026!';

COMMENT ON ROLE it_auditor IS 'External or internal auditors. Read access to all data including audit_logs and historical records.';

-- Application service account (for future API layer or ETL jobs)
CREATE ROLE itam_app_service WITH
    LOGIN
    NOSUPERUSER
    INHERIT
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    PASSWORD 'AppServiceAccount2026!';

COMMENT ON ROLE itam_app_service IS 'Service account for application backend or scheduled ETL jobs.';

-- ============================================================================
-- GRANTS - it_data_analyst (read + select on views)
-- ============================================================================
GRANT CONNECT ON DATABASE itam_db TO it_data_analyst;
GRANT USAGE ON SCHEMA public TO it_data_analyst;

-- Read access to all core tables
GRANT SELECT ON ALL TABLES IN SCHEMA public TO it_data_analyst;

-- Explicit grants on views (in case ALL TABLES misses them)
GRANT SELECT ON v_active_asset_assignments TO it_data_analyst;
GRANT SELECT ON v_license_utilization TO it_data_analyst;

-- No write privileges
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM it_data_analyst;

-- Future-proof: grant on sequences if needed for reporting tools that introspect
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO it_data_analyst;

-- ============================================================================
-- GRANTS - it_admin (full CRUD on operational tables, limited on audit)
-- ============================================================================
GRANT CONNECT ON DATABASE itam_db TO it_admin;
GRANT USAGE ON SCHEMA public TO it_admin;

-- Full access to mutable operational tables
GRANT SELECT, INSERT, UPDATE, DELETE ON 
    departments, employees, asset_types, assets, vendors, 
    software_products, software_licenses, license_allocations, 
    maintenance_records 
TO it_admin;

-- Read-only on audit logs (even admins should not casually delete audit history)
GRANT SELECT ON audit_logs TO it_admin;

-- Can create temporary objects for analysis
GRANT TEMPORARY ON DATABASE itam_db TO it_admin;

-- ============================================================================
-- GRANTS - it_auditor (broad read, including sensitive audit table)
-- ============================================================================
GRANT CONNECT ON DATABASE itam_db TO it_auditor;
GRANT USAGE ON SCHEMA public TO it_auditor;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO it_auditor;
GRANT SELECT ON audit_logs TO it_auditor;  -- Explicit for compliance visibility

-- ============================================================================
-- GRANTS - itam_app_service (application backend pattern)
-- ============================================================================
GRANT CONNECT ON DATABASE itam_db TO itam_app_service;
GRANT USAGE ON SCHEMA public TO itam_app_service;

-- Typical app needs: read most, write to transactional tables
GRANT SELECT, INSERT, UPDATE ON 
    assets, license_allocations, maintenance_records 
TO itam_app_service;

-- Read on reference tables
GRANT SELECT ON 
    departments, employees, asset_types, vendors, software_products, software_licenses 
TO itam_app_service;

-- ============================================================================
-- DEFAULT PRIVILEGES (for future objects created by postgres superuser)
-- ============================================================================
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
    GRANT SELECT ON TABLES TO it_data_analyst, it_auditor;

ALTER DEFAULT PRIVILEGES IN SCHEMA public 
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO it_admin;

-- ============================================================================
-- Verification query (run manually after this script)
-- ============================================================================
-- SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolcanlogin 
-- FROM pg_roles 
-- WHERE rolname LIKE 'it_%' OR rolname = 'itam_app_service';

SELECT 'RBAC roles and grants created successfully. Analyst has read-only; Admin has operational control; Auditor has full read including audit history.' AS status;