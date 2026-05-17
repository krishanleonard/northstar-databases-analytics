-- ===========================================================================
-- NorthStar Urban Mobility & Logistics — SQL Queries (run from R via DBI)
-- ===========================================================================
-- Each query addresses one of the questions raised in the case study.
-- They are designed to be readable, indexed-friendly, and to expose real
-- operational issues — not just to demonstrate syntax.
-- Author: <your name>
-- Module: CP60056E Databases and Analytics — S2 2025/26
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- Q1. Data quality check: count distinct (messy) zone spellings vs harmonised
--     Demonstrates: SQL on RAW vs cleaned tables, COUNT DISTINCT, UNION ALL
-- ---------------------------------------------------------------------------
SELECT 'raw_orders.pickup_zone'  AS source,
       COUNT(DISTINCT pickup_zone)  AS distinct_values
FROM raw_orders
UNION ALL
SELECT 'orders.pickup_zone (clean)' AS source,
       COUNT(DISTINCT pickup_zone)  AS distinct_values
FROM orders;


-- ---------------------------------------------------------------------------
-- Q2. Top failing zones (Operations Director's hypothesis)
--     "Some city zones consistently perform worse than others"
--     Demonstrates: GROUP BY, conditional aggregation, ORDER BY, ROUND
-- ---------------------------------------------------------------------------
SELECT  o.pickup_zone,
        COUNT(*)                                                    AS n_deliveries,
        SUM(CASE WHEN d.delivery_status = 'OnTime'  THEN 1 ELSE 0 END) AS on_time,
        SUM(CASE WHEN d.delivery_status = 'Delayed' THEN 1 ELSE 0 END) AS delayed,
        SUM(CASE WHEN d.delivery_status = 'Failed'  THEN 1 ELSE 0 END) AS failed,
        ROUND(100.0 * SUM(CASE WHEN d.delivery_status = 'Failed'  THEN 1 ELSE 0 END)
                    / COUNT(*), 2)                                  AS failure_pct,
        ROUND(100.0 * SUM(CASE WHEN d.delivery_status = 'Delayed' THEN 1 ELSE 0 END)
                    / COUNT(*), 2)                                  AS delayed_pct
FROM    orders     o
JOIN    deliveries d ON d.order_id = o.order_id
GROUP BY o.pickup_zone
ORDER BY failure_pct DESC;


-- ---------------------------------------------------------------------------
-- Q3. Hub utilisation paradox (Tech Director's concern)
--     "Capacity score" should predict performance — does it?
--     Demonstrates: 3-table JOIN, derived metrics
-- ---------------------------------------------------------------------------
SELECT  h.hub_id,
        h.hub_name,
        h.zone,
        h.hub_type,
        h.capacity_score,
        COUNT(d.delivery_id)                                        AS n_deliveries,
        ROUND(AVG(d.customer_rating_post_delivery), 2)              AS avg_rating,
        ROUND(100.0 * SUM(CASE WHEN d.delivery_status='Failed'  THEN 1 ELSE 0 END)
                    / COUNT(d.delivery_id), 2)                     AS failure_pct
FROM    hubs       h
LEFT JOIN deliveries d ON d.hub_id = h.hub_id
GROUP BY h.hub_id, h.hub_name, h.zone, h.hub_type, h.capacity_score
ORDER BY failure_pct DESC;


-- ---------------------------------------------------------------------------
-- Q4. The "hidden complaints" problem (Customer Experience Director's concern)
--     Complaints filed against deliveries that one system marks "OnTime".
--     Demonstrates: LEFT JOIN, NULL handling, share calculation via subquery
-- ---------------------------------------------------------------------------
SELECT  d.delivery_status,
        COUNT(*)                                                    AS complaint_count,
        ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM complaints), 2) AS pct_of_complaints
FROM    complaints c
LEFT JOIN deliveries d ON d.order_id = c.order_id
GROUP BY d.delivery_status
ORDER BY complaint_count DESC;


-- ---------------------------------------------------------------------------
-- Q5. Driver behaviour: high-override drivers and their failure profile
--     Demonstrates: HAVING, multi-aggregation, percentage with NULLIF
-- ---------------------------------------------------------------------------
SELECT  d.driver_id,
        dr.base_zone,
        dr.years_experience,
        dr.driver_rating,
        COUNT(*)                                                    AS n_deliveries,
        ROUND(AVG(d.manual_route_override_count), 2)                AS avg_overrides,
        SUM(CASE WHEN d.delivery_status='Failed' THEN 1 ELSE 0 END) AS n_failed,
        ROUND(100.0 *
              SUM(CASE WHEN d.delivery_status='Failed' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(*),0), 2)                              AS failure_pct
FROM    deliveries d
JOIN    drivers   dr ON dr.driver_id = d.driver_id
GROUP BY d.driver_id, dr.base_zone, dr.years_experience, dr.driver_rating
HAVING  COUNT(*) >= 4 AND AVG(d.manual_route_override_count) >= 1.5
ORDER BY avg_overrides DESC, failure_pct DESC
LIMIT 20;


-- ---------------------------------------------------------------------------
-- Q6. Profitability proxy by service type (Finance Director's concern)
--     Net = order_value − fuel/charge − any compensation tied to it.
--     Demonstrates: LEFT JOIN with aggregate subquery, COALESCE
-- ---------------------------------------------------------------------------
SELECT  o.service_type,
        COUNT(o.order_id)                                           AS orders,
        ROUND(SUM(o.order_value), 2)                                AS revenue,
        ROUND(SUM(COALESCE(d.fuel_or_charge_cost, 0)), 2)           AS direct_cost,
        ROUND(COALESCE(comp.total_comp, 0), 2)                      AS compensation_paid,
        ROUND(SUM(o.order_value)
              - SUM(COALESCE(d.fuel_or_charge_cost, 0))
              - COALESCE(comp.total_comp, 0), 2)                    AS net_proxy
FROM    orders o
LEFT JOIN deliveries d ON d.order_id = o.order_id
LEFT JOIN (
    SELECT  o2.service_type,
            SUM(c.compensation_amount) AS total_comp
    FROM    complaints c
    JOIN    orders o2 ON o2.order_id = c.order_id
    GROUP BY o2.service_type
) comp ON comp.service_type = o.service_type
GROUP BY o.service_type, comp.total_comp
ORDER BY net_proxy ASC;


-- ---------------------------------------------------------------------------
-- Q7. Vehicle health vs incident pattern (Tech Director's concern)
--     Battery alerts and vehicle faults vs current maintenance status.
--     Demonstrates: 3-table JOIN, conditional COUNT, aggregation
-- ---------------------------------------------------------------------------
SELECT  v.vehicle_type,
        v.maintenance_status,
        COUNT(DISTINCT v.vehicle_id)                                AS n_vehicles,
        ROUND(AVG(v.battery_health_pct), 1)                         AS avg_battery_pct,
        SUM(CASE WHEN i.incident_type = 'BatteryAlert'  THEN 1 ELSE 0 END) AS battery_alerts,
        SUM(CASE WHEN i.incident_type = 'VehicleFault'  THEN 1 ELSE 0 END) AS vehicle_faults
FROM    vehicles  v
LEFT JOIN deliveries d ON d.vehicle_id = v.vehicle_id
LEFT JOIN incidents  i ON i.delivery_id = d.delivery_id
GROUP BY v.vehicle_type, v.maintenance_status
ORDER BY v.vehicle_type, v.maintenance_status;


-- ---------------------------------------------------------------------------
-- Q8. Customer impact: customers with >=3 complaints AND >=1 failed delivery
--     Demonstrates: CTE, INNER JOIN, HAVING with multiple conditions
-- ---------------------------------------------------------------------------
WITH cust_complaints AS (
    SELECT customer_id, COUNT(*) AS n_complaints
    FROM   complaints
    GROUP BY customer_id
),
cust_failures AS (
    SELECT o.customer_id,
           SUM(CASE WHEN d.delivery_status='Failed' THEN 1 ELSE 0 END) AS n_failed
    FROM   orders o
    JOIN   deliveries d ON d.order_id = o.order_id
    GROUP BY o.customer_id
)
SELECT  c.customer_id,
        c.home_zone,
        c.customer_type,
        c.loyalty_score,
        cc.n_complaints,
        cf.n_failed
FROM    customers      c
JOIN    cust_complaints cc ON cc.customer_id = c.customer_id
JOIN    cust_failures   cf ON cf.customer_id = c.customer_id
WHERE   cc.n_complaints >= 3
  AND   cf.n_failed     >= 1
ORDER BY cc.n_complaints DESC, cf.n_failed DESC;


-- ---------------------------------------------------------------------------
-- Q9. Window function — driver ranking within zone by failure rate
--     Demonstrates: CTE + RANK() OVER PARTITION BY (modern SQL)
-- ---------------------------------------------------------------------------
WITH drv_perf AS (
    SELECT  dr.base_zone,
            d.driver_id,
            COUNT(*)                                              AS n_deliveries,
            1.0 * SUM(CASE WHEN d.delivery_status='Failed' THEN 1 ELSE 0 END)
                  / COUNT(*)                                      AS failure_rate
    FROM    deliveries d
    JOIN    drivers   dr ON dr.driver_id = d.driver_id
    GROUP BY dr.base_zone, d.driver_id
    HAVING  COUNT(*) >= 4
)
SELECT  base_zone,
        driver_id,
        n_deliveries,
        ROUND(failure_rate, 3) AS failure_rate,
        RANK() OVER (PARTITION BY base_zone ORDER BY failure_rate DESC) AS rank_in_zone
FROM    drv_perf
ORDER BY base_zone, rank_in_zone;


-- ---------------------------------------------------------------------------
-- Q10. Time-to-resolve: incidents that escalated within 24h
--      Demonstrates: filtering by computed value, GROUP BY with multiple keys
-- ---------------------------------------------------------------------------
SELECT  incident_type,
        severity,
        COUNT(*)                            AS n_incidents,
        ROUND(AVG(resolved_hours), 1)       AS avg_resolution_h,
        SUM(CASE WHEN resolution_status = 'Escalated' THEN 1 ELSE 0 END) AS n_escalated
FROM    incidents
WHERE   resolved_hours IS NOT NULL
GROUP BY incident_type, severity
HAVING  AVG(resolved_hours) > 10
ORDER BY avg_resolution_h DESC;
