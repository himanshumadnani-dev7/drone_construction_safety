"""
Drone-based Construction Process Monitoring & Safety Inspection System
Streamlit dashboard for MySQL 8.0.16+

Install: pip install streamlit mysql-connector-python pandas
Run:     streamlit run app.py
Prereq:  run drone_safety.sql first (mysql -u root -p < drone_safety.sql)

Optional environment variables:
    DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME
"""

import os
from datetime import date
from decimal import Decimal

import mysql.connector
import pandas as pd
import streamlit as st
from mysql.connector import Error

st.set_page_config(page_title="Drone Safety Inspection System", page_icon="🚁", layout="wide")

SEVERITY_LEVELS = ["Low", "Medium", "High", "Critical"]
ALERT_STATUSES = ["Open", "Under Review", "Resolved"]
TABLE_NAMES = ["Sites", "BIM_Elements", "Drone_Flights", "Raw_Images",
               "ML_Detections", "Safety_Alerts", "Audit_Logs"]
HAZARD_TYPES = ["Missing PPE - Helmet", "Missing PPE - Harness", "Fall Hazard - Open Edge",
                "Scaffold Non-Compliance", "Excavation Collapse Risk",
                "Crane Exclusion Zone Breach", "Excavation Edge Proximity", "Other"]

# ---------------------------------------------------------------------------
# Sidebar: connection settings and navigation
# ---------------------------------------------------------------------------
with st.sidebar:
    st.header("Database Connection")
    db_host = st.text_input("Host", os.getenv("DB_HOST", "localhost"))
    db_port = st.number_input("Port", value=int(os.getenv("DB_PORT", "3306")), step=1)
    db_user = st.text_input("User", os.getenv("DB_USER", "root"))
    db_password = st.text_input("Password", os.getenv("DB_PASSWORD", ""), type="password")
    db_name = st.text_input("Database", os.getenv("DB_NAME", "drone_safety_db"))
    st.divider()
    page = st.radio("Navigation", ["Dashboard", "Add Inspection Record",
                                   "Safety Analytics", "Alert Management & Audit"])

CONFIG = {
    "host": db_host,
    "port": int(db_port),
    "user": db_user,
    "password": db_password,
    "database": db_name,
}


# ---------------------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------------------
def get_connection():
    """Open a fresh MySQL connection (transactions are explicit via commit())."""
    return mysql.connector.connect(**CONFIG, autocommit=False, connection_timeout=10)


def _clean(df: pd.DataFrame) -> pd.DataFrame:
    """Convert Decimal values to float so Streamlit can render/plot them."""
    for col in df.columns:
        df[col] = df[col].map(lambda v: float(v) if isinstance(v, Decimal) else v)
    return df


def run_query(sql: str, params=None) -> pd.DataFrame:
    """Run a SELECT and return the result as a DataFrame."""
    conn = get_connection()
    try:
        cur = conn.cursor(dictionary=True)
        cur.execute(sql, params or ())
        rows = cur.fetchall()
        columns = list(cur.column_names)
        cur.close()
        return _clean(pd.DataFrame(rows, columns=columns))
    finally:
        conn.close()


def execute_write(sql: str, params=None) -> int:
    """Run an INSERT/UPDATE/DELETE inside a transaction; returns affected rows."""
    conn = get_connection()
    try:
        cur = conn.cursor()
        cur.execute(sql, params or ())
        affected = cur.rowcount
        conn.commit()
        cur.close()
        return affected
    except Error:
        conn.rollback()
        raise
    finally:
        conn.close()


def register_detection(image_id, element_id, detected_class, confidence,
                       is_hazard, hazard_type, severity):
    """Call stored procedure sp_register_detection_with_alert; returns new detection_id."""
    conn = get_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            "CALL sp_register_detection_with_alert(%s,%s,%s,%s,%s,%s,%s,@new_detection_id)",
            (image_id, element_id, detected_class, round(float(confidence), 3),
             int(is_hazard), hazard_type, severity),
        )
        cur.execute("SELECT @new_detection_id")
        new_id = cur.fetchone()[0]
        conn.commit()
        cur.close()
        return new_id
    except Error:
        conn.rollback()
        raise
    finally:
        conn.close()


def log_flight_and_image(site_id, flight_date, pilot, image_url, lat, lon):
    """Insert a flight and its first image in ONE transaction."""
    conn = get_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO Drone_Flights (site_id, flight_date, pilot_name) VALUES (%s,%s,%s)",
            (site_id, flight_date, pilot),
        )
        flight_id = cur.lastrowid
        cur.execute(
            "INSERT INTO Raw_Images (flight_id, image_url, gps_latitude, gps_longitude) "
            "VALUES (%s,%s,%s,%s)",
            (flight_id, image_url, round(float(lat), 6), round(float(lon), 6)),
        )
        image_id = cur.lastrowid
        conn.commit()
        cur.close()
        return flight_id, image_id
    except Error:
        conn.rollback()
        raise
    finally:
        conn.close()


def call_site_report(site_id):
    """Call stored procedure sp_site_safety_report and return a DataFrame."""
    conn = get_connection()
    try:
        cur = conn.cursor()
        cur.callproc("sp_site_safety_report", (site_id,))
        frames = []
        for result in cur.stored_results():
            rows = result.fetchall()
            frames.append(_clean(pd.DataFrame(rows, columns=list(result.column_names))))
        cur.close()
        return frames[0] if frames else pd.DataFrame()
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Verify connection before rendering anything
# ---------------------------------------------------------------------------
try:
    run_query("SELECT 1 AS ok")
except Error as err:
    st.error(f"Cannot connect to the database: {err}")
    st.info("Check the credentials in the sidebar and make sure drone_safety.sql has been executed.")
    st.stop()

st.title("🚁 Drone-based Construction Monitoring & Safety Inspection")

# ---------------------------------------------------------------------------
# PAGE 1: Dashboard
# ---------------------------------------------------------------------------
if page == "Dashboard":
    kpi = run_query("""
        SELECT (SELECT COUNT(*) FROM Sites)                                   AS sites,
               (SELECT COUNT(*) FROM Raw_Images)                              AS images,
               (SELECT COUNT(*) FROM ML_Detections WHERE is_safety_hazard = 1) AS hazards,
               (SELECT COUNT(*) FROM Safety_Alerts WHERE status <> 'Resolved') AS open_alerts,
               (SELECT COUNT(*) FROM Safety_Alerts
                 WHERE status <> 'Resolved' AND severity_level = 'Critical')  AS critical_open
    """).iloc[0]

    c1, c2, c3, c4, c5 = st.columns(5)
    c1.metric("Sites", int(kpi["sites"]))
    c2.metric("Drone Images", int(kpi["images"]))
    c3.metric("Hazard Detections", int(kpi["hazards"]))
    c4.metric("Open Alerts", int(kpi["open_alerts"]))
    c5.metric("Critical Open", int(kpi["critical_open"]))

    st.subheader("Database Tables")
    tabs = st.tabs(TABLE_NAMES)
    for tab, name in zip(tabs, TABLE_NAMES):
        with tab:
            # Table names come from the fixed TABLE_NAMES list (no user input).
            st.dataframe(run_query(f"SELECT * FROM {name}"), hide_index=True)

# ---------------------------------------------------------------------------
# PAGE 2: Add Inspection Record
# ---------------------------------------------------------------------------
elif page == "Add Inspection Record":
    tab_det, tab_flight = st.tabs(["Log ML Detection / Hazard", "Log Drone Flight & Image"])

    # ---- Tab A: detection + alert via stored procedure ----
    with tab_det:
        st.subheader("Register an ML Detection")
        images = run_query("""
            SELECT i.image_id, i.image_url, s.site_id, s.site_name
            FROM Raw_Images i
            JOIN Drone_Flights f ON f.flight_id = i.flight_id
            JOIN Sites s         ON s.site_id = f.site_id
            ORDER BY i.image_id
        """)
        if images.empty:
            st.warning("No images available. Log a drone flight and image first.")
        else:
            image_lookup = {int(r.image_id): r for r in images.itertuples()}
            image_id = st.selectbox(
                "Image", list(image_lookup.keys()),
                format_func=lambda x: f"#{x} | {image_lookup[x].site_name} | {image_lookup[x].image_url}")
            site_id = int(image_lookup[image_id].site_id)

            elements = run_query(
                "SELECT element_id, element_name FROM BIM_Elements WHERE site_id = %s ORDER BY element_id",
                (site_id,))
            element_lookup = {int(r.element_id): r.element_name for r in elements.itertuples()}
            element_id = st.selectbox(
                "Linked BIM Element (optional)", [None] + list(element_lookup.keys()),
                format_func=lambda x: "None / Unmapped" if x is None else f"#{x} | {element_lookup[x]}")

            detected_class = st.text_input("Detected class", placeholder="e.g. Worker without Helmet")
            confidence = st.slider("Confidence score", 0.0, 1.0, 0.90, 0.001)
            is_hazard = st.checkbox("Is safety hazard?", value=True)
            hazard_type = st.selectbox("Hazard type", HAZARD_TYPES, disabled=not is_hazard)
            severity = st.selectbox("Severity level", SEVERITY_LEVELS, index=2, disabled=not is_hazard)

            if st.button("Save Detection", type="primary"):
                if not detected_class.strip():
                    st.error("Detected class is required.")
                else:
                    try:
                        new_id = register_detection(
                            image_id, element_id, detected_class.strip(), confidence, is_hazard,
                            hazard_type if is_hazard else None,
                            severity if is_hazard else None)
                        msg = f"Detection #{new_id} saved."
                        if is_hazard:
                            msg += " Safety alert created (High/Critical alerts are auto-logged to Audit_Logs)."
                        st.success(msg)
                    except Error as err:
                        st.error(f"Database error: {err.msg}")

    # ---- Tab B: flight + image in one transaction ----
    with tab_flight:
        st.subheader("Register a Drone Flight with its first Image")
        sites = run_query("SELECT site_id, site_name FROM Sites ORDER BY site_name")
        site_lookup = {int(r.site_id): r.site_name for r in sites.itertuples()}
        f_site = st.selectbox("Site", list(site_lookup.keys()), format_func=lambda x: site_lookup[x])
        f_date = st.date_input("Flight date", value=date.today())
        f_pilot = st.text_input("Pilot name")
        f_url = st.text_input("Image URL", placeholder="s3://drone-survey/site/2026-10-01/IMG_0500.jpg")
        col_lat, col_lon = st.columns(2)
        f_lat = col_lat.number_input("GPS latitude", min_value=-90.0, max_value=90.0,
                                     value=13.0, format="%.6f")
        f_lon = col_lon.number_input("GPS longitude", min_value=-180.0, max_value=180.0,
                                     value=80.0, format="%.6f")

        if st.button("Save Flight & Image", type="primary"):
            if not f_pilot.strip() or not f_url.strip():
                st.error("Pilot name and image URL are required.")
            else:
                try:
                    fid, iid = log_flight_and_image(f_site, f_date, f_pilot.strip(),
                                                    f_url.strip(), f_lat, f_lon)
                    st.success(f"Flight #{fid} and image #{iid} saved (single transaction).")
                except Error as err:
                    st.error(f"Database error (nothing was saved): {err.msg}")

# ---------------------------------------------------------------------------
# PAGE 3: Safety Analytics (view, function, aggregates, procedure)
# ---------------------------------------------------------------------------
elif page == "Safety Analytics":
    st.subheader("Active Safety Violations (view: vw_ActiveSafetyViolations)")
    col_a, col_b = st.columns(2)
    sev_filter = col_a.multiselect("Severity filter", SEVERITY_LEVELS, default=SEVERITY_LEVELS)
    min_conf = col_b.slider("Minimum ML confidence", 0.0, 1.0, 0.0, 0.01)

    sql = ("SELECT v.*, fn_risk_score(v.severity_level, v.confidence_score) AS risk_score "
           "FROM vw_ActiveSafetyViolations v WHERE v.confidence_score >= %s")
    params = [min_conf]
    if sev_filter:
        sql += " AND v.severity_level IN (" + ",".join(["%s"] * len(sev_filter)) + ")"
        params += sev_filter
    else:
        sql += " AND 1 = 0"
    sql += " ORDER BY risk_score DESC, v.alert_id"
    try:
        st.dataframe(run_query(sql, tuple(params)), hide_index=True)
    except Error as err:
        st.error(f"Query failed: {err.msg}")

    st.subheader("Alerts by Severity (GROUP BY)")
    sev_df = run_query("""
        SELECT a.severity_level,
               COUNT(*)                                      AS total_alerts,
               CAST(SUM(a.status <> 'Resolved') AS UNSIGNED) AS open_alerts,
               ROUND(AVG(d.confidence_score), 3)             AS avg_confidence
        FROM Safety_Alerts a
        JOIN ML_Detections d ON d.detection_id = a.detection_id
        GROUP BY a.severity_level
        ORDER BY FIELD(a.severity_level,'Critical','High','Medium','Low')
    """)
    left, right = st.columns(2)
    left.dataframe(sev_df, hide_index=True)
    if not sev_df.empty:
        right.bar_chart(sev_df.set_index("severity_level")[["total_alerts", "open_alerts"]])

    st.subheader("Site-wise Statistics (LEFT JOIN + aggregates)")
    site_df = run_query("""
        SELECT s.site_id, s.site_name,
               COUNT(DISTINCT f.flight_id)    AS flights,
               COUNT(DISTINCT i.image_id)     AS images,
               COUNT(DISTINCT d.detection_id) AS detections,
               COUNT(DISTINCT CASE WHEN d.is_safety_hazard = 1 THEN d.detection_id END) AS hazards,
               COUNT(DISTINCT a.alert_id)     AS alerts,
               fn_site_open_alerts(s.site_id) AS open_alerts
        FROM Sites s
        LEFT JOIN Drone_Flights f  ON f.site_id = s.site_id
        LEFT JOIN Raw_Images i     ON i.flight_id = f.flight_id
        LEFT JOIN ML_Detections d  ON d.image_id = i.image_id
        LEFT JOIN Safety_Alerts a  ON a.detection_id = d.detection_id
        GROUP BY s.site_id, s.site_name
        ORDER BY alerts DESC
    """)
    st.dataframe(site_df, hide_index=True)

    st.subheader("Site Safety Report (stored procedure: sp_site_safety_report)")
    sites = run_query("SELECT site_id, site_name FROM Sites ORDER BY site_name")
    site_lookup = {int(r.site_id): r.site_name for r in sites.itertuples()}
    chosen_site = st.selectbox("Select site", list(site_lookup.keys()),
                               format_func=lambda x: site_lookup[x])
    if st.button("Run Report"):
        try:
            st.dataframe(call_site_report(chosen_site), hide_index=True)
        except Error as err:
            st.error(f"Procedure failed: {err.msg}")

    st.subheader("High-Confidence Hazards (nested subquery)")
    st.dataframe(run_query("""
        SELECT detection_id, detected_class, confidence_score
        FROM ML_Detections
        WHERE is_safety_hazard = 1
          AND confidence_score > (SELECT AVG(confidence_score)
                                  FROM ML_Detections WHERE is_safety_hazard = 1)
        ORDER BY confidence_score DESC
    """), hide_index=True)

# ---------------------------------------------------------------------------
# PAGE 4: Alert Management & Audit
# ---------------------------------------------------------------------------
else:
    st.subheader("All Safety Alerts")
    alerts = run_query("""
        SELECT a.alert_id, s.site_name, a.hazard_type, a.severity_level, a.status,
               d.detected_class, d.confidence_score
        FROM Safety_Alerts a
        JOIN ML_Detections d ON d.detection_id = a.detection_id
        JOIN Raw_Images i    ON i.image_id = d.image_id
        JOIN Drone_Flights f ON f.flight_id = i.flight_id
        JOIN Sites s         ON s.site_id = f.site_id
        ORDER BY a.alert_id
    """)
    st.dataframe(alerts, hide_index=True)

    if not alerts.empty:
        st.subheader("Update Alert Status")
        alert_lookup = {int(r.alert_id): r for r in alerts.itertuples()}
        alert_id = st.selectbox(
            "Alert", list(alert_lookup.keys()),
            format_func=lambda x: f"#{x} | {alert_lookup[x].hazard_type} | "
                                  f"{alert_lookup[x].severity_level} | {alert_lookup[x].status}")
        current = alert_lookup[alert_id].status
        new_status = st.selectbox("New status", ALERT_STATUSES, index=ALERT_STATUSES.index(current))
        if st.button("Update Status", type="primary"):
            if new_status == current:
                st.info("Status is unchanged.")
            else:
                try:
                    execute_write("UPDATE Safety_Alerts SET status = %s WHERE alert_id = %s",
                                  (new_status, alert_id))
                    st.success(f"Alert #{alert_id} updated to '{new_status}'. "
                               "The change was recorded in Audit_Logs by a trigger.")
                    st.rerun()
                except Error as err:
                    st.error(f"Update failed: {err.msg}")

    st.subheader("Audit Log (latest 50, populated by triggers)")
    st.dataframe(run_query("SELECT * FROM Audit_Logs ORDER BY log_id DESC LIMIT 50"),
                 hide_index=True)