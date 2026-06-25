-- ============================================================================
-- 01_create_schema.sql
-- IT Asset Management Database (ITAM DB) - CS103 Portfolio Project
-- Author: Randall James
-- Description: Core table creation with primary keys, foreign keys, and basic constraints.
-- Run this first after creating the 'itam_db' database.
-- ============================================================================

-- Enable useful extensions (idempotent)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;  -- For potential trigram indexes on names/serial search

-- ============================================================================
-- TABLE: departments
-- ============================================================================
CREATE TABLE departments (
    department_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name              VARCHAR(100) NOT NULL UNIQUE,
    location          VARCHAR(100),
    budget            NUMERIC(14, 2) CHECK (budget >= 0),
    created_at        TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at        TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

COMMENT ON TABLE departments IS 'Organizational units that own IT assets and employees.';

-- ============================================================================
-- TABLE: employees
-- Self-referencing FK for manager hierarchy
-- ============================================================================
CREATE TABLE employees (
    employee_id       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name        VARCHAR(50) NOT NULL,
    last_name         VARCHAR(50) NOT NULL,
    email             VARCHAR(120) NOT NULL UNIQUE,
    phone             VARCHAR(25),
    department_id     INTEGER REFERENCES departments(department_id) ON DELETE SET NULL,
    manager_id        INTEGER REFERENCES employees(employee_id) ON DELETE SET NULL,
    job_title         VARCHAR(100),
    hire_date         DATE NOT NULL,
    status            VARCHAR(20) DEFAULT 'Active' NOT NULL 
                      CHECK (status IN ('Active', 'On Leave', 'Terminated')),
    created_at        TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at        TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

COMMENT ON TABLE employees IS 'All company personnel who can be assigned assets or perform maintenance.';
COMMENT ON COLUMN employees.manager_id IS 'Self-referencing FK to support organizational hierarchy. Top-level managers have NULL.';

-- ============================================================================
-- TABLE: asset_types
-- Lookup / dimension table for categorization
-- ============================================================================
CREATE TABLE asset_types (
    asset_type_id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                   VARCHAR(60) NOT NULL UNIQUE,
    category               VARCHAR(30) NOT NULL 
                           CHECK (category IN ('Hardware', 'Peripheral', 'Mobile Device', 'Server', 'Networking', 'Other')),
    typical_lifespan_years INTEGER CHECK (typical_lifespan_years > 0),
    created_at             TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

COMMENT ON TABLE asset_types IS 'Controlled vocabulary for asset classification (Laptop, Monitor, etc.).';

-- ============================================================================
-- TABLE: assets
-- Central fact table for physical and virtual IT assets
-- ============================================================================
CREATE TABLE assets (
    asset_id                  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    asset_tag                 VARCHAR(25) NOT NULL UNIQUE,
    serial_number             VARCHAR(60) UNIQUE,
    asset_type_id             INTEGER NOT NULL REFERENCES asset_types(asset_type_id) ON DELETE RESTRICT,
    manufacturer              VARCHAR(60),
    model                     VARCHAR(120),
    purchase_date             DATE NOT NULL,
    purchase_cost             NUMERIC(12, 2) NOT NULL CHECK (purchase_cost >= 0),
    warranty_end_date         DATE CHECK (warranty_end_date IS NULL OR warranty_end_date >= purchase_date),
    status                    VARCHAR(25) DEFAULT 'In Storage' NOT NULL 
                              CHECK (status IN ('In Use', 'In Storage', 'Under Maintenance', 'Retired', 'Disposed')),
    assigned_to_employee_id   INTEGER REFERENCES employees(employee_id) ON DELETE SET NULL,
    location                  VARCHAR(120),  -- Could be normalized to locations table later
    notes                     TEXT,
    created_at                TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at                TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

COMMENT ON TABLE assets IS 'Core IT asset registry. One row per physical device or major software asset.';
COMMENT ON COLUMN assets.asset_tag IS 'Human-readable unique identifier used by IT team (e.g., AD-2024-0087).';
COMMENT ON COLUMN assets.status IS 'Lifecycle state. Retired/Disposed assets kept for historical reporting.';

-- ============================================================================
-- TABLE: vendors
-- Suppliers of hardware and software
-- ============================================================================
CREATE TABLE vendors (
    vendor_id       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(120) NOT NULL UNIQUE,
    contact_email   VARCHAR(120),
    support_phone   VARCHAR(25),
    website         VARCHAR(150),
    created_at      TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

COMMENT ON TABLE vendors IS 'External suppliers for procurement and support tracking.';

-- ============================================================================
-- TABLE: software_products
-- Master list of software titles (independent of licensing)
-- ============================================================================
CREATE TABLE software_products (
    product_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          VARCHAR(120) NOT NULL,
    publisher     VARCHAR(80),
    category      VARCHAR(50),
    description   TEXT,
    created_at    TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

COMMENT ON TABLE software_products IS 'Catalog of software applications used in the organization.';

-- ============================================================================
-- TABLE: software_licenses
-- Purchased license entitlements (one row per purchase/batch)
-- ============================================================================
CREATE TABLE software_licenses (
    license_id       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id       INTEGER NOT NULL REFERENCES software_products(product_id) ON DELETE RESTRICT,
    vendor_id        INTEGER REFERENCES vendors(vendor_id) ON DELETE SET NULL,
    license_type     VARCHAR(30) NOT NULL 
                     CHECK (license_type IN ('Subscription', 'Perpetual', 'Volume', 'Named User', 'Site License', 'Other')),
    total_seats      INTEGER NOT NULL CHECK (total_seats > 0),
    cost_per_seat    NUMERIC(10, 2) CHECK (cost_per_seat >= 0),
    total_cost       NUMERIC(12, 2) GENERATED ALWAYS AS (total_seats * COALESCE(cost_per_seat, 0)) STORED,
    purchase_date    DATE,
    start_date       DATE,
    expiration_date  DATE CHECK (expiration_date IS NULL OR expiration_date >= COALESCE(start_date, purchase_date)),
    notes            TEXT,
    created_at       TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at       TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

COMMENT ON TABLE software_licenses IS 'License purchases/entitlements. total_cost is auto-calculated via generated column.';
COMMENT ON COLUMN software_licenses.total_seats IS 'Maximum concurrent or named users allowed under this license record.';

-- ============================================================================
-- TABLE: license_allocations
-- Junction table resolving many-to-many between licenses and employees/assets
-- Supports historical tracking via returned_date
-- ============================================================================
CREATE TABLE license_allocations (
    allocation_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    license_id        INTEGER NOT NULL REFERENCES software_licenses(license_id) ON DELETE CASCADE,
    employee_id       INTEGER REFERENCES employees(employee_id) ON DELETE CASCADE,
    asset_id          INTEGER REFERENCES assets(asset_id) ON DELETE SET NULL,
    allocated_date    DATE NOT NULL DEFAULT CURRENT_DATE,
    returned_date     DATE CHECK (returned_date IS NULL OR returned_date >= allocated_date),
    seats_allocated   INTEGER NOT NULL DEFAULT 1 CHECK (seats_allocated > 0),
    notes             TEXT,
    created_at        TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

COMMENT ON TABLE license_allocations IS 'Tracks assignment of license seats to employees and/or specific assets. Historical via returned_date IS NOT NULL.';
COMMENT ON COLUMN license_allocations.seats_allocated IS 'Usually 1, but supports multi-seat allocations per record.';

-- ============================================================================
-- TABLE: maintenance_records
-- Service, repair, and upgrade history for assets
-- ============================================================================
CREATE TABLE maintenance_records (
    record_id                   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    asset_id                    INTEGER NOT NULL REFERENCES assets(asset_id) ON DELETE CASCADE,
    maintenance_date            DATE NOT NULL,
    maintenance_type            VARCHAR(25) NOT NULL 
                                CHECK (maintenance_type IN ('Preventive', 'Corrective', 'Upgrade', 'Inspection', 'Warranty Repair')),
    description                 TEXT NOT NULL,
    cost                        NUMERIC(10, 2) DEFAULT 0 CHECK (cost >= 0),
    performed_by_employee_id    INTEGER REFERENCES employees(employee_id) ON DELETE SET NULL,
    downtime_hours              NUMERIC(6, 2) DEFAULT 0 CHECK (downtime_hours >= 0),
    resolution_notes            TEXT,
    created_at                  TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

COMMENT ON TABLE maintenance_records IS 'Full service history for assets. Critical for TCO and reliability analysis.';

-- ============================================================================
-- TABLE: audit_logs
-- Immutable change history populated by triggers (see 03_add_constraints_and_triggers.sql)
-- ============================================================================
CREATE TABLE audit_logs (
    log_id        BIGSERIAL PRIMARY KEY,
    table_name    VARCHAR(60) NOT NULL,
    record_id     INTEGER NOT NULL,
    action        VARCHAR(10) NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    changed_by    VARCHAR(120),
    changed_at    TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    old_data      JSONB,
    new_data      JSONB
);

COMMENT ON TABLE audit_logs IS 'Append-only audit trail for compliance and forensic analysis. Populated exclusively via AFTER triggers.';
COMMENT ON COLUMN audit_logs.old_data IS 'JSON snapshot of row before change (UPDATE/DELETE).';
COMMENT ON COLUMN audit_logs.new_data IS 'JSON snapshot of row after change (INSERT/UPDATE).';

-- ============================================================================
-- Helpful Views (created early for convenience)
-- ============================================================================

-- Current active asset assignments with employee context
CREATE OR REPLACE VIEW v_active_asset_assignments AS
SELECT 
    a.asset_id,
    a.asset_tag,
    a.serial_number,
    at.name AS asset_type,
    a.manufacturer,
    a.model,
    a.status,
    a.purchase_cost,
    e.first_name || ' ' || e.last_name AS assigned_employee,
    e.email AS employee_email,
    d.name AS department,
    a.location,
    a.warranty_end_date
FROM assets a
JOIN asset_types at ON a.asset_type_id = at.asset_type_id
LEFT JOIN employees e ON a.assigned_to_employee_id = e.employee_id
LEFT JOIN departments d ON e.department_id = d.department_id
WHERE a.status = 'In Use';

COMMENT ON VIEW v_active_asset_assignments IS 'Convenience view for dashboards and common analyst queries.';

-- Current license utilization summary
CREATE OR REPLACE VIEW v_license_utilization AS
WITH allocation_counts AS (
    SELECT 
        license_id,
        SUM(seats_allocated) AS seats_allocated
    FROM license_allocations
    WHERE returned_date IS NULL
    GROUP BY license_id
)
SELECT 
    sl.license_id,
    sp.name AS software_name,
    sp.publisher,
    sl.total_seats,
    COALESCE(ac.seats_allocated, 0) AS seats_allocated,
    ROUND(100.0 * COALESCE(ac.seats_allocated, 0) / sl.total_seats, 1) AS utilization_pct,
    sl.expiration_date,
    CASE 
        WHEN sl.expiration_date IS NOT NULL AND sl.expiration_date < CURRENT_DATE THEN 'Expired'
        WHEN sl.expiration_date IS NOT NULL AND sl.expiration_date <= CURRENT_DATE + INTERVAL '90 days' THEN 'Expiring Soon'
        ELSE 'Active'
    END AS license_status
FROM software_licenses sl
JOIN software_products sp ON sl.product_id = sp.product_id
LEFT JOIN allocation_counts ac ON sl.license_id = ac.license_id;

COMMENT ON VIEW v_license_utilization IS 'Real-time license compliance view. Use for monthly audits and renewal planning.';

-- ============================================================================
-- End of schema creation
-- ============================================================================
SELECT 'Schema creation complete. Tables, FKs, CHECKs, and initial views created successfully.' AS status;
