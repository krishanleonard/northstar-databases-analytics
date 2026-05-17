"""
build_database.py
==================
Builds northstar.db (SQLite) from the raw NorthStar CSVs.

Two schemas in one DB:
  - raw_*  : as-loaded tables (preserve original messy values for SQL exercises that
             need to demonstrate cleaning)
  - clean_*: harmonised + typed copies for analytical SQL

Run:
  python build_database.py
"""
import os, sys, sqlite3
import pandas as pd

DATA_DIR = os.environ.get("NORTHSTAR_DATA", "data")
DB_PATH  = os.environ.get("NORTHSTAR_DB",   "northstar.db")

# ---- Zone harmonisation ----
ZONE_MAP = {
    "north": "North", "NORTH": "North", "North": "North",
    "south": "South", "SOUTH": "South", "South": "South",
    "east":  "East",  "EAST":  "East",  "East":  "East",
    "west":  "West",  "WEST":  "West",  "West":  "West",
    "central":"Central","CENTRAL":"Central","Central":"Central","Ctr":"Central",
    "riverside":"Riverside","RIVERSIDE":"Riverside","Riverside":"Riverside","RiverSide":"Riverside",
    "airport":"Airport","AIRPORT":"Airport","Airport":"Airport",
}
def harmonise_zone(s: pd.Series) -> pd.Series:
    return s.map(lambda x: ZONE_MAP.get(str(x).strip(), x) if pd.notna(x) else x)

def parse_dt(s):
    return pd.to_datetime(s, errors="coerce")

def main():
    print(f"Reading CSVs from: {DATA_DIR}")
    files = ["hubs","customers","drivers","vehicles","orders",
             "deliveries","incidents","complaints","app_events"]
    raw = {f: pd.read_csv(os.path.join(DATA_DIR, f"{f}.csv")) for f in files}

    # ---- Build clean copies ----
    customers  = raw["customers"].copy()
    customers["home_zone"]   = harmonise_zone(customers["home_zone"])
    customers["signup_date"] = parse_dt(customers["signup_date"])

    drivers   = raw["drivers"].copy()
    drivers["base_zone"] = harmonise_zone(drivers["base_zone"])

    vehicles  = raw["vehicles"].copy()
    vehicles["assigned_zone"]   = harmonise_zone(vehicles["assigned_zone"])
    vehicles["commission_date"] = parse_dt(vehicles["commission_date"])

    orders    = raw["orders"].copy()
    orders["pickup_zone"]      = harmonise_zone(orders["pickup_zone"])
    orders["dropoff_zone"]     = harmonise_zone(orders["dropoff_zone"])
    orders["order_created_at"] = parse_dt(orders["order_created_at"])

    deliveries = raw["deliveries"].copy()
    deliveries["dispatch_time"]         = parse_dt(deliveries["dispatch_time"])
    deliveries["delivery_completed_at"] = parse_dt(deliveries["delivery_completed_at"])

    incidents = raw["incidents"].copy()
    incidents["reported_at"] = parse_dt(incidents["reported_at"])

    complaints = raw["complaints"].copy()
    complaints["created_at"] = parse_dt(complaints["created_at"])

    app_events = raw["app_events"].copy()
    app_events["zone_context"]    = harmonise_zone(app_events["zone_context"])
    app_events["event_timestamp"] = parse_dt(app_events["event_timestamp"])

    hubs = raw["hubs"].copy()
    hubs["zone"] = harmonise_zone(hubs["zone"])

    clean = dict(customers=customers, drivers=drivers, vehicles=vehicles,
                 orders=orders, deliveries=deliveries, incidents=incidents,
                 complaints=complaints, app_events=app_events, hubs=hubs)

    # ---- Write SQLite ----
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()
    cur.execute("PRAGMA foreign_keys = ON;")

    for name, df in raw.items():
        df.to_sql(f"raw_{name}", con, index=False, if_exists="replace")
    for name, df in clean.items():
        df.to_sql(name, con, index=False, if_exists="replace")

    # ---- Indexes (good practice; demonstrates SQL optimisation knowledge) ----
    idx_sql = [
        "CREATE INDEX idx_orders_customer    ON orders(customer_id);",
        "CREATE INDEX idx_orders_service     ON orders(service_type);",
        "CREATE INDEX idx_orders_pickup_zone ON orders(pickup_zone);",
        "CREATE INDEX idx_deliveries_order   ON deliveries(order_id);",
        "CREATE INDEX idx_deliveries_driver  ON deliveries(driver_id);",
        "CREATE INDEX idx_deliveries_vehicle ON deliveries(vehicle_id);",
        "CREATE INDEX idx_deliveries_hub     ON deliveries(hub_id);",
        "CREATE INDEX idx_deliveries_status  ON deliveries(delivery_status);",
        "CREATE INDEX idx_incidents_delivery ON incidents(delivery_id);",
        "CREATE INDEX idx_complaints_customer ON complaints(customer_id);",
        "CREATE INDEX idx_complaints_order    ON complaints(order_id);",
        "CREATE INDEX idx_app_events_customer ON app_events(customer_id);",
        "CREATE INDEX idx_app_events_order    ON app_events(order_id);",
    ]
    for s in idx_sql:
        cur.execute(s)
    con.commit()

    # ---- Verify ----
    print("\nTables created:")
    names = [r[0] for r in cur.execute(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;").fetchall()]
    for n in names:
        cnt = con.execute(f"SELECT COUNT(*) FROM {n}").fetchone()[0]
        print(f"  {n:20s} {cnt:>6} rows")
    con.close()
    print(f"\nDatabase written to: {DB_PATH}")

if __name__ == "__main__":
    main()
