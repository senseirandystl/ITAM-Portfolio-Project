-- ============================================================================
-- 03_add_constraints_and_triggers.sql
-- IT Asset Management Database - Data Integrity, Audit Triggers, Additional Constraints
-- Author: Randall James
-- Run this AFTER 01_create_schema.sql and 02_seed_data.sql
-- ============================================================================

-- ============================================================================
-- ADDITIONAL CHECK CONSTRAINTS (business rules that may have been missed or added post-seed)
-- ============================================================================

-- Ensure warranty_end_date logic is enforced even if seed had edge cases
ALTER TABLE assets 
    ADD CONSTRAINT chk_warranty_logical 
    CHECK (warranty_end_date IS NULL OR warranty_end_date >= purchase_date);

-- Prevent negative costs anywhere
ALTER TABLE assets 
    ADD CONSTRAINT chk_purchase_cost_non_negative 
    CHECK (purchase_cost >= 0);

ALTER TABLE maintenance_records 
    ADD CONSTRAINT chk_maintenance_cost_non_negative 
    CHECK (cost >= 0);

-- Ensure allocated seats don't exceed license total (soft enforcement via app or trigger; hard constraint difficult without materialized view)
-- For demo, we add a comment and rely on application logic + periodic audit query.

-- Status transition sanity (example: cannot assign asset that is Retired)
-- This is better handled in application layer or BEFORE trigger; shown here as example
-- ALTER TABLE assets ADD CONSTRAINT chk_assigned_status CHECK (
--     (assigned_to_employee_id IS NULL AND status IN ('In Storage', 'Retired', 'Disposed')) OR
--     (assigned_to_employee_id IS NOT NULL AND status = 'In Use')
-- );

-- ============================================================================
-- UPDATED_AT TRIGGER FUNCTION (reusable for any table with updated_at column)
-- ============================================================================
CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION trigger_set_updated_at() IS 'Generic trigger to maintain updated_at timestamp on row modification.';

-- Apply to tables with updated_at
CREATE TRIGGER set_updated_at_departments
    BEFORE UPDATE ON departments
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_employees
    BEFORE UPDATE ON employees
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_assets
    BEFORE UPDATE ON assets
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_software_licenses
    BEFORE UPDATE ON software_licenses
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- ============================================================================
-- AUDIT TRIGGER SYSTEM (JSONB snapshots for compliance)
-- ============================================================================
CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
DECLARE
    v_old_data JSONB;
    v_new_data JSONB;
    v_action TEXT;
    v_record_id INTEGER;
BEGIN
    IF (TG_OP = 'DELETE') THEN
        v_old_data := to_jsonb(OLD);
        v_new_data := NULL;
        v_action := 'DELETE';
        v_record_id := OLD.asset_id;  -- Adjust per table if needed; generic example uses asset_id pattern
    ELSIF (TG_OP = 'UPDATE') THEN
        v_old_data := to_jsonb(OLD);
        v_new_data := to_jsonb(NEW);
        v_action := 'UPDATE';
        v_record_id := NEW.asset_id;
    ELSIF (TG_OP = 'INSERT') THEN
        v_old_data := NULL;
        v_new_data := to_jsonb(NEW);
        v_action := 'INSERT';
        v_record_id := NEW.asset_id;
    END IF;

    -- Insert audit record (table-specific column names handled by dynamic SQL or separate functions per table in production)
    -- For simplicity in portfolio, we demonstrate on assets table. Extend pattern to employees, licenses, etc.
    INSERT INTO audit_logs (table_name, record_id, action, changed_by, old_data, new_data)
    VALUES (TG_TABLE_NAME, v_record_id, v_action, current_user, v_old_data, v_new_data);

    IF (TG_OP = 'DELETE') THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION audit_trigger_function() IS 'AFTER trigger function to log INSERT/UPDATE/DELETE with full row snapshots as JSONB. Extend per-table for production (record_id extraction).';

-- Apply audit trigger to key tables (example on assets; add to others as needed)
CREATE TRIGGER audit_assets
    AFTER INSERT OR UPDATE OR DELETE ON assets
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- Note: For full production implementation, create separate lightweight functions per table or use a more sophisticated
-- dynamic approach that inspects TG_TABLE_NAME and primary key. This version demonstrates the pattern clearly.

-- ============================================================================
-- EXAMPLE: Row-Level Security (RLS) Policy (optional advanced feature)
-- Uncomment and customize if demonstrating RLS for analyst vs admin access
-- ============================================================================
-- ALTER TABLE assets ENABLE ROW LEVEL SECURITY;
-- 
-- CREATE POLICY assets_analyst_read ON assets
--     FOR SELECT
--     TO it_data_analyst
--     USING (status != 'Disposed');  -- Analysts cannot see disposed assets for compliance reasons
--
-- CREATE POLICY assets_admin_all ON assets
--     FOR ALL
--     TO it_admin
--     USING (true);

-- ============================================================================
-- End of constraints and triggers
-- ============================================================================
SELECT 'Additional constraints, updated_at triggers, and audit trigger system applied successfully.' AS status;