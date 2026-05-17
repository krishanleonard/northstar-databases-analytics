# =============================================================================
# 01_sql_in_r_and_analytics.R
# NorthStar Urban Mobility — SQL in R and R Analytics
# Module CP60056E Databases and Analytics — S2 2025/26
#
# Run with:
#   Rscript 01_sql_in_r_and_analytics.R
# Prereqs:
#   1. Run python_scripts/build_database.py first to produce ../northstar.db
#   2. install.packages(c("DBI","RSQLite","dplyr","tidyr","ggplot2",
#                         "scales","cluster","factoextra"))
# =============================================================================

suppressPackageStartupMessages({
  library(DBI);    library(RSQLite); library(dplyr);   library(tidyr)
  library(ggplot2); library(scales)
})

DB_PATH <- Sys.getenv("NORTHSTAR_DB", unset = "northstar.db")
stopifnot(file.exists(DB_PATH))
con <- dbConnect(RSQLite::SQLite(), DB_PATH)
# on.exit(dbDisconnect(conn), add = TRUE)

cat("\n=== A.1 Data quality: messy vs clean zones ===\n")
print(dbGetQuery(con, "
  SELECT 'raw_orders.pickup_zone'     AS source, COUNT(DISTINCT pickup_zone) AS n
  FROM raw_orders
  UNION ALL
  SELECT 'orders.pickup_zone (clean)' AS source, COUNT(DISTINCT pickup_zone) AS n
  FROM orders;"))

cat("\n=== A.2 Failure rate by pickup zone ===\n")
zone_perf <- dbGetQuery(con, "
  SELECT  o.pickup_zone, COUNT(*) AS n_deliveries,
          SUM(CASE WHEN d.delivery_status='OnTime'  THEN 1 ELSE 0 END) AS on_time,
          SUM(CASE WHEN d.delivery_status='Delayed' THEN 1 ELSE 0 END) AS delayed,
          SUM(CASE WHEN d.delivery_status='Failed'  THEN 1 ELSE 0 END) AS failed,
          ROUND(100.0 * SUM(CASE WHEN d.delivery_status='Failed' THEN 1 ELSE 0 END)
                      / COUNT(*), 2) AS failure_pct
  FROM    orders o JOIN deliveries d ON d.order_id = o.order_id
  GROUP BY o.pickup_zone
  ORDER BY failure_pct DESC;")
print(zone_perf)

cat("\n=== A.3 Hub paradox ===\n")
print(dbGetQuery(con, "
  SELECT  h.hub_id, h.hub_name, h.zone, h.capacity_score,
          COUNT(d.delivery_id) AS n,
          ROUND(100.0 * SUM(CASE WHEN d.delivery_status='Failed' THEN 1 ELSE 0 END)
                      / COUNT(d.delivery_id), 2) AS failure_pct
  FROM    hubs h LEFT JOIN deliveries d ON d.hub_id = h.hub_id
  GROUP BY h.hub_id, h.hub_name, h.zone, h.capacity_score
  ORDER BY failure_pct DESC;"))

cat("\n=== A.4 Hidden complaints ===\n")
print(dbGetQuery(con, "
  SELECT  d.delivery_status, COUNT(*) AS complaints,
          ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM complaints), 2) AS pct
  FROM    complaints c LEFT JOIN deliveries d ON d.order_id = c.order_id
  GROUP BY d.delivery_status
  ORDER BY complaints DESC;"))

cat("\n=== A.8 Query plan with vs without index ===\n")
cat("\n--- WITH index ---\n")
print(dbGetQuery(con, "EXPLAIN QUERY PLAN
                       SELECT * FROM deliveries WHERE driver_id = 'D001';"))
dbExecute(con, "DROP INDEX IF EXISTS idx_deliveries_driver;")
cat("\n--- WITHOUT index ---\n")
print(dbGetQuery(con, "EXPLAIN QUERY PLAN
                       SELECT * FROM deliveries WHERE driver_id = 'D001';"))
dbExecute(con, "CREATE INDEX idx_deliveries_driver ON deliveries(driver_id);")

# ----- R analytics -----
orders     <- dbGetQuery(con, "SELECT * FROM orders;")
deliveries <- dbGetQuery(con, "SELECT * FROM deliveries;")
hubs       <- dbGetQuery(con, "SELECT * FROM hubs;")
master <- orders |>
  left_join(deliveries, by = "order_id") |>
  left_join(hubs |> select(hub_id, hub_name, zone, capacity_score),
            by = "hub_id")

cat("\n=== B.1 Numeric summary by outcome ===\n")
print(master |>
  filter(!is.na(delivery_status)) |>
  group_by(delivery_status) |>
  summarise(n              = n(),
            mean_value     = round(mean(order_value, na.rm = TRUE), 2),
            mean_distance  = round(mean(route_distance_km, na.rm = TRUE), 2),
            mean_overrides = round(mean(manual_route_override_count, na.rm = TRUE), 2),
            mean_rating    = round(mean(customer_rating_post_delivery, na.rm = TRUE), 2),
            .groups = "drop"))

cat("\n=== B.4 Kruskal-Wallis test: overrides vs outcome ===\n")
kw <- kruskal.test(manual_route_override_count ~ delivery_status,
                   data = master |> filter(!is.na(delivery_status)))
print(kw)

# Save plots to disk
dir.create("../figures", showWarnings = FALSE)

hm <- master |>
  filter(!is.na(delivery_status)) |>
  group_by(pickup_zone, service_type) |>
  summarise(failure_rate = mean(delivery_status == "Failed"),
            n = n(), .groups = "drop") |>
  filter(n >= 10)

p1 <- ggplot(hm, aes(service_type, pickup_zone, fill = failure_rate)) +
  geom_tile(colour = "white") +
  geom_text(aes(label = sprintf("%.1f%%", failure_rate*100)), size = 3) +
  scale_fill_gradient(low = "#e8f4f8", high = "#b2182b") +
  labs(title = "Failure rate by zone × service type",
       x = "Service type", y = "Pickup zone", fill = "Failure rate") +
  theme_minimal()
ggsave("../figures/heatmap_zone_service.png", p1, width = 8, height = 4.5, dpi = 100)
cat("Saved figures/heatmap_zone_service.png\n")
