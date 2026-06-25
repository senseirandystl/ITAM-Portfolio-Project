-- ============================================================================
-- 06_analytical_queries.sql
-- IT Asset Management Database - Analytical Queries for Data Analyst Interviews
-- Author: Randall James
-- Purpose: Demonstrate production-quality SQL for reporting, compliance, cost analysis, and trends
-- These queries are the heart of the portfolio for IT Data Analyst roles.
-- ============================================================================

-- ============================================================================
-- QUERY 1: Assets with Warranty Expiring in Next 90 Days (Compliance Alert)
-- Business use: Procurement + IT planning for renewals/replacements
-- ============================================================================
WITH expiring_warranty AS (
    SELECT 
        a.asset_id,
        a.asset_tag,
        a.serial_number,
        at.name AS asset_type,
        a.manufacturer || ' ' || a.model AS full_model,
        a.purchase_date,
        a.warranty_end_date,
        a.purchase_cost,
        e.first_name || ' ' || e.last_name AS assigned_to,
        e.email,
        d.name AS department,
        (a.warranty_end_date - CURRENT_DATE) AS days_until_expiry
    FROM assets a
    JOIN asset_types at ON a.asset_type_id = at.asset_type_id
    LEFT JOIN employees e ON a.assigned_to_employee_id = e.employee_id
    LEFT JOIN departments d ON e.department_id = d.department_id
    WHERE a.warranty_end_date IS NOT NULL
      AND a.warranty_end_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '90 days'
      AND a.status IN ('In Use', 'In Storage')
)
SELECT 
    *,
    CASE 
        WHEN days_until_expiry <= 30 THEN 'CRITICAL - Renew/Replace Immediately'
        WHEN days_until_expiry <= 60 THEN 'HIGH - Plan Replacement'
        ELSE 'MEDIUM - Monitor'
    END AS urgency
FROM expiring_warranty
ORDER BY days_until_expiry ASC, department;

-- ============================================================================
-- QUERY 2: License Utilization & Compliance Dashboard (Window + CTE)
-- Business use: Monthly license audit, renewal planning, cost optimization
-- ============================================================================
WITH current_allocations AS (
    SELECT 
        license_id,
        SUM(seats_allocated) AS currently_allocated
    FROM license_allocations
    WHERE returned_date IS NULL
    GROUP BY license_id
),
license_status AS (
    SELECT 
        sl.license_id,
        sp.name AS software,
        sp.publisher,
        sl.total_seats,
        COALESCE(ca.currently_allocated, 0) AS allocated,
        sl.total_seats - COALESCE(ca.currently_allocated, 0) AS available_seats,
        ROUND(100.0 * COALESCE(ca.currently_allocated, 0) / NULLIF(sl.total_seats, 0), 1) AS utilization_pct,
        sl.expiration_date,
        sl.total_cost AS annual_cost,
        CASE 
            WHEN sl.expiration_date < CURRENT_DATE THEN 'EXPIRED'
            WHEN sl.expiration_date <= CURRENT_DATE + INTERVAL '90 days' THEN 'EXPIRING SOON'
            ELSE 'ACTIVE'
        END AS renewal_status
    FROM software_licenses sl
    JOIN software_products sp ON sl.product_id = sp.product_id
    LEFT JOIN current_allocations ca ON sl.license_id = ca.license_id
)
SELECT 
    *,
    RANK() OVER (ORDER BY utilization_pct DESC NULLS LAST) AS utilization_rank,
    RANK() OVER (PARTITION BY renewal_status ORDER BY annual_cost DESC) AS cost_rank_within_status
FROM license_status
ORDER BY renewal_status, utilization_pct DESC NULLS LAST;

-- ============================================================================
-- QUERY 3: Total Asset Value & Depreciation by Department (Simple TCO)
-- Business use: Budgeting, showback/chargeback, department-level accountability
-- ============================================================================
SELECT 
    d.name AS department,
    COUNT(a.asset_id) AS total_assets,
    COUNT(*) FILTER (WHERE a.status = 'In Use') AS assets_in_use,
    SUM(a.purchase_cost) AS total_original_cost,
    ROUND(AVG(a.purchase_cost), 2) AS avg_asset_cost,
    -- Simple straight-line depreciation example (assume 4-year life, ignore salvage)
    ROUND(SUM(
        a.purchase_cost * 
        GREATEST(0, 1 - (EXTRACT(YEAR FROM AGE(CURRENT_DATE, a.purchase_date)) / 4.0))
    ), 2) AS estimated_current_book_value,
    ROUND(SUM(a.purchase_cost) / NULLIF(COUNT(DISTINCT e.employee_id), 0), 2) AS cost_per_employee
FROM departments d
LEFT JOIN employees e ON d.department_id = e.department_id AND e.status = 'Active'
LEFT JOIN assets a ON e.employee_id = a.assigned_to_employee_id 
                   AND a.status IN ('In Use', 'In Storage')
GROUP BY d.department_id, d.name
ORDER BY total_original_cost DESC;

-- ============================================================================
-- QUERY 4: Employee Asset Footprint with Ranking (Window Functions)
-- Business use: Identify power users, equity analysis, onboarding/offboarding planning
-- ============================================================================
WITH employee_asset_cost AS (
    SELECT 
        e.employee_id,
        e.first_name || ' ' || e.last_name AS employee_name,
        e.job_title,
        d.name AS department,
        COUNT(a.asset_id) AS asset_count,
        COALESCE(SUM(a.purchase_cost), 0) AS total_asset_value,
        STRING_AGG(DISTINCT at.name, ', ' ORDER BY at.name) AS asset_types_owned
    FROM employees e
    JOIN departments d ON e.department_id = d.department_id
    LEFT JOIN assets a ON e.employee_id = a.assigned_to_employee_id 
                       AND a.status = 'In Use'
    LEFT JOIN asset_types at ON a.asset_type_id = at.asset_type_id
    WHERE e.status = 'Active'
    GROUP BY e.employee_id, e.first_name, e.last_name, e.job_title, d.name
)
SELECT 
    *,
    RANK() OVER (ORDER BY total_asset_value DESC) AS value_rank,
    RANK() OVER (PARTITION BY department ORDER BY total_asset_value DESC) AS dept_value_rank,
    NTILE(4) OVER (ORDER BY total_asset_value DESC) AS value_quartile,
    LAG(total_asset_value) OVER (ORDER BY total_asset_value DESC) AS next_highest_value
FROM employee_asset_cost
ORDER BY total_asset_value DESC
LIMIT 25;

-- ============================================================================
-- QUERY 5: Maintenance Cost Trends with YoY Comparison (Time Series + Window)
-- Business use: Reliability engineering, vendor performance, budget forecasting
-- ============================================================================
WITH monthly_maintenance AS (
    SELECT 
        DATE_TRUNC('month', m.maintenance_date) AS month,
        m.maintenance_type,
        COUNT(*) AS work_orders,
        SUM(m.cost) AS total_cost,
        SUM(m.downtime_hours) AS total_downtime_hours,
        AVG(m.downtime_hours) AS avg_downtime_per_job
    FROM maintenance_records m
    WHERE m.maintenance_date >= CURRENT_DATE - INTERVAL '24 months'
    GROUP BY DATE_TRUNC('month', m.maintenance_date), m.maintenance_type
),
monthly_with_trends AS (
    SELECT 
        month,
        maintenance_type,
        work_orders,
        total_cost,
        total_downtime_hours,
        LAG(total_cost) OVER (PARTITION BY maintenance_type ORDER BY month) AS prev_month_cost,
        LAG(total_cost, 12) OVER (PARTITION BY maintenance_type ORDER BY month) AS prev_year_cost,
        ROUND(
            100.0 * (total_cost - LAG(total_cost, 12) OVER (PARTITION BY maintenance_type ORDER BY month)) / 
            NULLIF(LAG(total_cost, 12) OVER (PARTITION BY maintenance_type ORDER BY month), 0), 
        1) AS yoy_change_pct
    FROM monthly_maintenance
)
SELECT 
    TO_CHAR(month, 'YYYY-MM') AS reporting_month,
    maintenance_type,
    work_orders,
    total_cost,
    prev_year_cost,
    yoy_change_pct,
    CASE 
        WHEN yoy_change_pct > 20 THEN '↑ Significant Increase'
        WHEN yoy_change_pct < -20 THEN '↓ Significant Decrease'
        ELSE '→ Stable'
    END AS trend_flag
FROM monthly_with_trends
WHERE month >= CURRENT_DATE - INTERVAL '12 months'
ORDER BY month DESC, maintenance_type;

-- ============================================================================
-- QUERY 6: Orphaned / Underutilized High-Value Assets
-- Business use: Asset recovery, reduce waste, identify process gaps in assignment
-- ============================================================================
SELECT 
    a.asset_tag,
    a.serial_number,
    at.name AS asset_type,
    a.manufacturer || ' ' || a.model AS model,
    a.purchase_date,
    a.purchase_cost,
    a.status,
    a.location,
    CASE 
        WHEN a.assigned_to_employee_id IS NULL THEN 'UNASSIGNED'
        ELSE 'ASSIGNED BUT LOW ACTIVITY'
    END AS issue_type,
    (CURRENT_DATE - a.purchase_date) / 365.0 AS age_years
FROM assets a
JOIN asset_types at ON a.asset_type_id = at.asset_type_id
WHERE a.purchase_cost > 1500
  AND (
      a.assigned_to_employee_id IS NULL 
      OR a.status != 'In Use'
  )
  AND a.status NOT IN ('Retired', 'Disposed')
ORDER BY a.purchase_cost DESC, age_years DESC;

-- ============================================================================
-- QUERY 7: License Allocation History for a Specific Employee (Audit Trail)
-- Business use: Offboarding compliance, access review, forensic investigation
-- ============================================================================
SELECT 
    sp.name AS software,
    sl.license_type,
    la.allocated_date,
    la.returned_date,
    la.seats_allocated,
    CASE 
        WHEN la.returned_date IS NULL THEN 'CURRENTLY ASSIGNED'
        ELSE 'RETURNED'
    END AS current_status,
    la.notes
FROM license_allocations la
JOIN software_licenses sl ON la.license_id = sl.license_id
JOIN software_products sp ON sl.product_id = sp.product_id
WHERE la.employee_id = 11  -- Example: James Lee (Senior Software Engineer)
ORDER BY la.allocated_date DESC;

-- ============================================================================
-- QUERY 8: Department-Level Software Spend vs Asset Spend (Cross-Domain Analysis)
-- Business use: Total cost of ownership (TCO) by business unit
-- ============================================================================
WITH dept_asset_cost AS (
    SELECT 
        d.department_id,
        d.name AS department,
        SUM(a.purchase_cost) AS hardware_spend
    FROM departments d
    LEFT JOIN employees e ON d.department_id = e.department_id
    LEFT JOIN assets a ON e.employee_id = a.assigned_to_employee_id
    GROUP BY d.department_id, d.name
),
dept_license_cost AS (
    SELECT 
        d.department_id,
        SUM(sl.total_cost) AS software_spend
    FROM departments d
    JOIN employees e ON d.department_id = e.department_id
    JOIN license_allocations la ON e.employee_id = la.employee_id AND la.returned_date IS NULL
    JOIN software_licenses sl ON la.license_id = sl.license_id
    GROUP BY d.department_id
)
SELECT 
    da.department,
    da.hardware_spend,
    COALESCE(dl.software_spend, 0) AS software_spend,
    da.hardware_spend + COALESCE(dl.software_spend, 0) AS total_it_spend_per_dept,
    ROUND(100.0 * da.hardware_spend / NULLIF(da.hardware_spend + COALESCE(dl.software_spend, 0), 0), 1) AS hardware_pct
FROM dept_asset_cost da
LEFT JOIN dept_license_cost dl ON da.department_id = dl.department_id
ORDER BY total_it_spend_per_dept DESC;

-- ============================================================================
-- QUERY 9: Top Maintenance Cost Drivers (Asset + Type Analysis)
-- Business use: Identify problematic models or vendors for procurement decisions
-- ============================================================================
SELECT 
    a.asset_tag,
    at.name AS asset_type,
    a.manufacturer || ' ' || a.model AS model,
    COUNT(m.record_id) AS maintenance_events,
    SUM(m.cost) AS total_maintenance_cost,
    ROUND(AVG(m.cost), 2) AS avg_cost_per_event,
    SUM(m.downtime_hours) AS total_downtime,
    MAX(m.maintenance_date) AS last_maintenance_date
FROM assets a
JOIN asset_types at ON a.asset_type_id = at.asset_type_id
JOIN maintenance_records m ON a.asset_id = m.asset_id
GROUP BY a.asset_id, a.asset_tag, at.name, a.manufacturer, a.model
HAVING SUM(m.cost) > 200 OR COUNT(m.record_id) >= 3
ORDER BY total_maintenance_cost DESC;

-- ============================================================================
-- QUERY 10: Headcount vs Asset Ratio & "Ghost Assets" Check
-- Business use: Efficiency metric, identify assets not tied to active employees
-- ============================================================================
SELECT 
    'Active Employees' AS metric,
    COUNT(*) AS count,
    NULL AS notes
FROM employees
WHERE status = 'Active'

UNION ALL

SELECT 
    'Assets Currently Assigned to Active Employees' AS metric,
    COUNT(DISTINCT a.asset_id) AS count,
    'May be lower than headcount due to shared devices or contractors' AS notes
FROM assets a
JOIN employees e ON a.assigned_to_employee_id = e.employee_id
WHERE e.status = 'Active' AND a.status = 'In Use'

UNION ALL

SELECT 
    'Assets Assigned to Terminated Employees (Ghost Assets)' AS metric,
    COUNT(*) AS count,
    'Action required: reassign or retire these assets' AS notes
FROM assets a
JOIN employees e ON a.assigned_to_employee_id = e.employee_id
WHERE e.status = 'Terminated' AND a.status = 'In Use';

-- ============================================================================
-- QUERY 11: JSONB Audit Log Example - Recent Changes to High-Value Assets
-- Business use: Change auditing, compliance evidence for SOX/ISO audits
-- ============================================================================
SELECT 
    al.changed_at,
    al.action,
    al.changed_by,
    al.table_name,
    al.record_id AS asset_id,
    al.old_data ->> 'status' AS old_status,
    al.new_data ->> 'status' AS new_status,
    al.old_data ->> 'assigned_to_employee_id' AS old_assigned_id,
    al.new_data ->> 'assigned_to_employee_id' AS new_assigned_id
FROM audit_logs al
WHERE al.table_name = 'assets'
  AND (al.old_data ->> 'purchase_cost')::numeric > 2000 
     OR (al.new_data ->> 'purchase_cost')::numeric > 2000
ORDER BY al.changed_at DESC
LIMIT 20;

-- ============================================================================
-- End of analytical queries
-- These queries demonstrate: CTEs, Window Functions (RANK, LAG, LEAD, NTILE), 
-- date arithmetic, conditional aggregation, JSONB querying, complex multi-table joins,
-- and business-contextualized result sets ready for stakeholder consumption.
-- ============================================================================
SELECT 'Analytical query suite complete. These represent the types of questions hiring managers expect Data Analysts to answer fluently in SQL.' AS status;