-- ============================================================
-- Drone-based Construction Process Monitoring & Safety Inspection System
-- Target: MySQL 8.0.16+ (InnoDB)
-- ============================================================

DROP DATABASE IF EXISTS drone_safety_db;
CREATE DATABASE drone_safety_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE drone_safety_db;

-- ------------------------------------------------------------
-- 1. SITES
-- ------------------------------------------------------------
CREATE TABLE Sites (
    site_id    INT UNSIGNED NOT NULL AUTO_INCREMENT,
    site_name  VARCHAR(100) NOT NULL,
    location   VARCHAR(200) NOT NULL,
    CONSTRAINT pk_sites      PRIMARY KEY (site_id),
    CONSTRAINT uq_sites_name UNIQUE (site_name)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 2. BIM_ELEMENTS
-- ------------------------------------------------------------
CREATE TABLE BIM_Elements (
    element_id    INT UNSIGNED NOT NULL AUTO_INCREMENT,
    site_id       INT UNSIGNED NOT NULL,
    revit_guid    VARCHAR(45)  NOT NULL,
    element_name  VARCHAR(120) NOT NULL,
    planned_stage ENUM('Foundation','Structure','Masonry','MEP','Finishing') NOT NULL,
    CONSTRAINT pk_bim      PRIMARY KEY (element_id),
    CONSTRAINT uq_bim_guid UNIQUE (revit_guid),
    CONSTRAINT fk_bim_site FOREIGN KEY (site_id) REFERENCES Sites(site_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 3. DRONE_FLIGHTS
-- ------------------------------------------------------------
CREATE TABLE Drone_Flights (
    flight_id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
    site_id     INT UNSIGNED NOT NULL,
    flight_date DATE         NOT NULL,
    pilot_name  VARCHAR(80)  NOT NULL,
    CONSTRAINT pk_flights     PRIMARY KEY (flight_id),
    CONSTRAINT fk_flight_site FOREIGN KEY (site_id) REFERENCES Sites(site_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 4. RAW_IMAGES
-- ------------------------------------------------------------
CREATE TABLE Raw_Images (
    image_id      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    flight_id     INT UNSIGNED  NOT NULL,
    image_url     VARCHAR(255)  NOT NULL,
    gps_latitude  DECIMAL(9,6)  NOT NULL,
    gps_longitude DECIMAL(9,6)  NOT NULL,
    CONSTRAINT pk_images      PRIMARY KEY (image_id),
    CONSTRAINT uq_image_url   UNIQUE (image_url),
    CONSTRAINT fk_image_flight FOREIGN KEY (flight_id) REFERENCES Drone_Flights(flight_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_lat CHECK (gps_latitude  BETWEEN -90  AND 90),
    CONSTRAINT chk_lon CHECK (gps_longitude BETWEEN -180 AND 180)
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 5. ML_DETECTIONS
-- ------------------------------------------------------------
CREATE TABLE ML_Detections (
    detection_id     INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    image_id         INT UNSIGNED  NOT NULL,
    element_id       INT UNSIGNED  NULL,
    detected_class   VARCHAR(80)   NOT NULL,
    confidence_score DECIMAL(4,3)  NOT NULL,
    is_safety_hazard TINYINT(1)    NOT NULL DEFAULT 0,
    CONSTRAINT pk_detections   PRIMARY KEY (detection_id),
    CONSTRAINT fk_det_image    FOREIGN KEY (image_id)   REFERENCES Raw_Images(image_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_det_element  FOREIGN KEY (element_id) REFERENCES BIM_Elements(element_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT chk_confidence  CHECK (confidence_score BETWEEN 0 AND 1),
    CONSTRAINT chk_hazard_flag CHECK (is_safety_hazard IN (0,1))
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 6. SAFETY_ALERTS
-- ------------------------------------------------------------
CREATE TABLE Safety_Alerts (
    alert_id       INT UNSIGNED NOT NULL AUTO_INCREMENT,
    detection_id   INT UNSIGNED NOT NULL,
    hazard_type    VARCHAR(80)  NOT NULL,
    severity_level ENUM('Low','Medium','High','Critical') NOT NULL,
    status         ENUM('Open','Under Review','Resolved') NOT NULL DEFAULT 'Open',
    CONSTRAINT pk_alerts       PRIMARY KEY (alert_id),
    CONSTRAINT uq_alert_det    UNIQUE (detection_id),
    CONSTRAINT fk_alert_det    FOREIGN KEY (detection_id) REFERENCES ML_Detections(detection_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 7. AUDIT_LOGS
-- ------------------------------------------------------------
CREATE TABLE Audit_Logs (
    log_id      INT UNSIGNED NOT NULL AUTO_INCREMENT,
    action_type VARCHAR(40)  NOT NULL,
    log_message VARCHAR(500) NOT NULL,
    logged_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_audit PRIMARY KEY (log_id)
) ENGINE=InnoDB;

-- Supporting indexes for frequent filters
CREATE INDEX idx_alert_status_severity ON Safety_Alerts (status, severity_level);
CREATE INDEX idx_det_hazard_conf       ON ML_Detections (is_safety_hazard, confidence_score);
CREATE INDEX idx_flight_date           ON Drone_Flights (flight_date);




INSERT INTO Sites (site_id, site_name, location) VALUES
(1, 'Marina Heights Tower',     'Besant Nagar, Chennai, Tamil Nadu'),
(2, 'Orchid Business Park',     'Whitefield, Bengaluru, Karnataka'),
(3, 'Riverfront Metro Station', 'Nampally, Hyderabad, Telangana'),
(4, 'Coastal Bridge Project',   'Vypin, Kochi, Kerala');

INSERT INTO BIM_Elements (element_id, site_id, revit_guid, element_name, planned_stage) VALUES
(1, 1, '8f1c2a9e-4b7d-4c3a-9e51-1a2b3c4d5e01', 'Column C-12 Level 5',            'Structure'),
(2, 1, '8f1c2a9e-4b7d-4c3a-9e51-1a2b3c4d5e02', 'Slab S-05 Level 5',              'Structure'),
(3, 1, '8f1c2a9e-4b7d-4c3a-9e51-1a2b3c4d5e03', 'Scaffold Zone SZ-3 East Facade', 'Masonry'),
(4, 2, '5d7b3e10-91aa-4f6c-b2d4-7c8e9f0a1b04', 'Foundation Footing F-08',        'Foundation'),
(5, 2, '5d7b3e10-91aa-4f6c-b2d4-7c8e9f0a1b05', 'Shear Wall SW-02',               'Structure'),
(6, 3, 'a41e6f20-33c8-48d1-8a7b-2e3f4a5b6c06', 'Excavation Pit EX-01',           'Foundation'),
(7, 3, 'a41e6f20-33c8-48d1-8a7b-2e3f4a5b6c07', 'Crane Pad CP-01',                'Foundation'),
(8, 4, 'c92d8b35-6e1f-4a07-95c3-9d0e1f2a3b08', 'Pier P-04',                      'Structure');

INSERT INTO Drone_Flights (flight_id, site_id, flight_date, pilot_name) VALUES
(1, 1, '2026-09-02', 'Arjun Mehta'),
(2, 1, '2026-09-16', 'Arjun Mehta'),
(3, 2, '2026-09-05', 'Priya Nair'),
(4, 3, '2026-09-10', 'Karthik Raman'),
(5, 4, '2026-09-20', 'Priya Nair');

INSERT INTO Raw_Images (image_id, flight_id, image_url, gps_latitude, gps_longitude) VALUES
(1,  1, 's3://drone-survey/marina-heights/2026-09-02/IMG_0001.jpg', 13.000214, 80.266842),
(2,  1, 's3://drone-survey/marina-heights/2026-09-02/IMG_0002.jpg', 13.000391, 80.266975),
(3,  2, 's3://drone-survey/marina-heights/2026-09-16/IMG_0101.jpg', 13.000298, 80.266901),
(4,  2, 's3://drone-survey/marina-heights/2026-09-16/IMG_0102.jpg', 13.000455, 80.267012),
(5,  3, 's3://drone-survey/orchid-park/2026-09-05/IMG_0201.jpg',    12.969800, 77.749700),
(6,  3, 's3://drone-survey/orchid-park/2026-09-05/IMG_0202.jpg',    12.969912, 77.749811),
(7,  4, 's3://drone-survey/riverfront-metro/2026-09-10/IMG_0301.jpg', 17.376900, 78.475300),
(8,  4, 's3://drone-survey/riverfront-metro/2026-09-10/IMG_0302.jpg', 17.377015, 78.475412),
(9,  5, 's3://drone-survey/coastal-bridge/2026-09-20/IMG_0401.jpg', 9.997500, 76.236400),
(10, 5, 's3://drone-survey/coastal-bridge/2026-09-20/IMG_0402.jpg', 9.997612, 76.236521),
(11, 5, 's3://drone-survey/coastal-bridge/2026-09-20/IMG_0403.jpg', 9.997733, 76.236610);

INSERT INTO ML_Detections (detection_id, image_id, element_id, detected_class, confidence_score, is_safety_hazard) VALUES
(1,  1,  1, 'Worker without Helmet',        0.962, 1),
(2,  1,  1, 'Rebar Cage',                   0.915, 0),
(3,  2,  2, 'Unprotected Slab Edge',        0.887, 1),
(4,  3,  3, 'Scaffold Missing Guardrail',   0.934, 1),
(5,  4,  3, 'Scaffold',                     0.978, 0),
(6,  5,  4, 'Concrete Footing',             0.951, 0),
(7,  6,  5, 'Worker without Harness',       0.812, 1),
(8,  7,  6, 'Unshored Excavation',          0.941, 1),
(9,  8,  7, 'Mobile Crane',                 0.969, 0),
(10, 8,  7, 'Crane Exclusion Zone Breach',  0.723, 1),
(11, 9,  8, 'Worker without Helmet',        0.684, 1),
(12, 10, 8, 'Pier Formwork',                0.902, 0);

INSERT INTO Safety_Alerts (alert_id, detection_id, hazard_type, severity_level, status) VALUES
(1, 1,  'Missing PPE - Helmet',        'High',     'Open'),
(2, 3,  'Fall Hazard - Open Edge',     'Critical', 'Open'),
(3, 4,  'Scaffold Non-Compliance',     'High',     'Under Review'),
(4, 7,  'Missing PPE - Harness',       'Medium',   'Open'),
(5, 8,  'Excavation Collapse Risk',    'Critical', 'Under Review'),
(6, 10, 'Crane Exclusion Zone Breach', 'Medium',   'Resolved'),
(7, 11, 'Missing PPE - Helmet',        'Low',      'Resolved');

INSERT INTO Audit_Logs (action_type, log_message, logged_at) VALUES
('SYSTEM_INIT',   'Drone safety database initialised.',                     '2026-09-01 08:00:00'),
('FLIGHT_UPLOAD', 'Flight #1 imagery uploaded for Marina Heights Tower.',   '2026-09-02 17:45:12'),
('ML_BATCH_RUN',  'YOLO inference batch completed for flights #1 to #5.',   '2026-09-21 06:30:00');




-- ============================================================
-- 3.1 CRUD OPERATIONS
-- ============================================================

-- CREATE: new hazard detection on image 2 plus its alert
INSERT INTO ML_Detections (image_id, element_id, detected_class, confidence_score, is_safety_hazard)
VALUES (2, 2, 'Worker without Helmet', 0.905, 1);

INSERT INTO Safety_Alerts (detection_id, hazard_type, severity_level, status)
VALUES (LAST_INSERT_ID(), 'Missing PPE - Helmet', 'Medium', 'Open');

-- CREATE: temporary image (used to demonstrate DELETE)
INSERT INTO Raw_Images (flight_id, image_url, gps_latitude, gps_longitude)
VALUES (5, 's3://drone-survey/coastal-bridge/2026-09-20/tmp_test.jpg', 9.997800, 76.236700);

-- READ: open critical/high alerts, most severe first
SELECT alert_id, hazard_type, severity_level, status
FROM Safety_Alerts
WHERE severity_level IN ('Critical','High') AND status <> 'Resolved'
ORDER BY FIELD(severity_level,'Critical','High'), alert_id;

-- UPDATE: move alert 1 into review
UPDATE Safety_Alerts SET status = 'Under Review' WHERE alert_id = 1;

-- DELETE: remove the temporary image
DELETE FROM Raw_Images WHERE image_url LIKE '%tmp_test.jpg';

-- ============================================================
-- 3.2 JOINS
-- ============================================================

-- INNER JOIN: images -> detections -> alerts (only images that triggered alerts)
SELECT i.image_id, i.image_url, d.detected_class, d.confidence_score,
       a.alert_id, a.hazard_type, a.severity_level, a.status
FROM Raw_Images i
INNER JOIN ML_Detections d ON d.image_id = i.image_id
INNER JOIN Safety_Alerts a ON a.detection_id = d.detection_id
ORDER BY a.severity_level DESC, d.confidence_score DESC;

-- LEFT JOIN: all images, with their detections and alerts if any
SELECT i.image_id, i.image_url,
       d.detected_class, d.confidence_score,
       a.alert_id, a.severity_level
FROM Raw_Images i
LEFT JOIN ML_Detections d ON d.image_id = i.image_id
LEFT JOIN Safety_Alerts a ON a.detection_id = d.detection_id
ORDER BY i.image_id, d.detection_id;

-- LEFT JOIN: images with no detections at all
SELECT i.image_id, i.image_url
FROM Raw_Images i
LEFT JOIN ML_Detections d ON d.image_id = i.image_id
WHERE d.detection_id IS NULL;

-- LEFT JOIN: hazard detections that have no alert raised
SELECT d.detection_id, d.detected_class, d.confidence_score
FROM ML_Detections d
LEFT JOIN Safety_Alerts a ON a.detection_id = d.detection_id
WHERE d.is_safety_hazard = 1 AND a.alert_id IS NULL;

-- ============================================================
-- 3.3 SUBQUERIES / NESTED QUERIES
-- ============================================================

-- Hazards whose confidence is above the average hazard confidence
SELECT detection_id, detected_class, confidence_score
FROM ML_Detections
WHERE is_safety_hazard = 1
  AND confidence_score > (SELECT AVG(confidence_score)
                          FROM ML_Detections
                          WHERE is_safety_hazard = 1)
ORDER BY confidence_score DESC;

-- Alerts backed by high-confidence (>= 0.90) hazard detections
SELECT alert_id, hazard_type, severity_level, status
FROM Safety_Alerts
WHERE detection_id IN (SELECT detection_id
                       FROM ML_Detections
                       WHERE is_safety_hazard = 1 AND confidence_score >= 0.90);

-- Sites that currently have NO critical alert (correlated NOT EXISTS)
SELECT s.site_id, s.site_name
FROM Sites s
WHERE NOT EXISTS (
    SELECT 1
    FROM Drone_Flights f
    JOIN Raw_Images i      ON i.flight_id = f.flight_id
    JOIN ML_Detections d   ON d.image_id = i.image_id
    JOIN Safety_Alerts a   ON a.detection_id = d.detection_id
    WHERE f.site_id = s.site_id AND a.severity_level = 'Critical'
);

-- ============================================================
-- 3.4 AGGREGATE FUNCTIONS
-- ============================================================

-- Alerts grouped by severity
SELECT a.severity_level,
       COUNT(*)                                   AS total_alerts,
       CAST(SUM(a.status <> 'Resolved') AS UNSIGNED) AS open_alerts,
       ROUND(AVG(d.confidence_score), 3)          AS avg_confidence,
       MAX(d.confidence_score)                    AS max_confidence
FROM Safety_Alerts a
JOIN ML_Detections d ON d.detection_id = a.detection_id
GROUP BY a.severity_level
ORDER BY FIELD(a.severity_level,'Critical','High','Medium','Low');

-- Site-wise statistics (all sites shown, even with zero alerts)
SELECT s.site_id, s.site_name,
       COUNT(DISTINCT f.flight_id)    AS flights,
       COUNT(DISTINCT i.image_id)     AS images,
       COUNT(DISTINCT d.detection_id) AS detections,
       COUNT(DISTINCT CASE WHEN d.is_safety_hazard = 1 THEN d.detection_id END) AS hazards,
       COUNT(DISTINCT a.alert_id)     AS alerts
FROM Sites s
LEFT JOIN Drone_Flights f  ON f.site_id = s.site_id
LEFT JOIN Raw_Images i     ON i.flight_id = f.flight_id
LEFT JOIN ML_Detections d  ON d.image_id = i.image_id
LEFT JOIN Safety_Alerts a  ON a.detection_id = d.detection_id
GROUP BY s.site_id, s.site_name
ORDER BY alerts DESC;

-- Sites with 2 or more alerts (HAVING)
SELECT s.site_name, COUNT(a.alert_id) AS alert_count
FROM Sites s
JOIN Drone_Flights f  ON f.site_id = s.site_id
JOIN Raw_Images i     ON i.flight_id = f.flight_id
JOIN ML_Detections d  ON d.image_id = i.image_id
JOIN Safety_Alerts a  ON a.detection_id = d.detection_id
GROUP BY s.site_id, s.site_name
HAVING COUNT(a.alert_id) >= 2;

-- ============================================================
-- 3.5 VIEW
-- ============================================================
CREATE OR REPLACE VIEW vw_ActiveSafetyViolations AS
SELECT a.alert_id,
       s.site_name,
       f.flight_id,
       f.flight_date,
       f.pilot_name,
       i.image_id,
       i.image_url,
       COALESCE(e.element_name, 'Unmapped') AS element_name,
       d.detected_class,
       d.confidence_score,
       a.hazard_type,
       a.severity_level,
       a.status
FROM Safety_Alerts a
JOIN ML_Detections d     ON d.detection_id = a.detection_id
JOIN Raw_Images i        ON i.image_id = d.image_id
JOIN Drone_Flights f     ON f.flight_id = i.flight_id
JOIN Sites s             ON s.site_id = f.site_id
LEFT JOIN BIM_Elements e ON e.element_id = d.element_id
WHERE a.status <> 'Resolved';

SELECT * FROM vw_ActiveSafetyViolations
ORDER BY FIELD(severity_level,'Critical','High','Medium','Low'), confidence_score DESC;

-- ============================================================
-- 3.6 USER-DEFINED FUNCTIONS, STORED PROCEDURES, TRIGGERS
-- ============================================================
DELIMITER $$

-- Function 1: risk score (0-100) from severity and ML confidence
CREATE FUNCTION fn_risk_score(p_severity VARCHAR(10), p_confidence DECIMAL(4,3))
RETURNS DECIMAL(6,2)
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_weight INT;
    SET v_weight = CASE p_severity
                       WHEN 'Low'      THEN 1
                       WHEN 'Medium'   THEN 2
                       WHEN 'High'     THEN 3
                       WHEN 'Critical' THEN 4
                       ELSE 0
                   END;
    RETURN ROUND(v_weight * p_confidence * 25, 2);
END$$

-- Function 2: number of unresolved alerts at a site
CREATE FUNCTION fn_site_open_alerts(p_site_id INT UNSIGNED)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_count INT DEFAULT 0;
    SELECT COUNT(*) INTO v_count
    FROM Safety_Alerts a
    JOIN ML_Detections d ON d.detection_id = a.detection_id
    JOIN Raw_Images i    ON i.image_id = d.image_id
    JOIN Drone_Flights f ON f.flight_id = i.flight_id
    WHERE f.site_id = p_site_id AND a.status <> 'Resolved';
    RETURN v_count;
END$$

-- Procedure 1: register a detection (and alert if hazardous) atomically
CREATE PROCEDURE sp_register_detection_with_alert(
    IN  p_image_id       INT UNSIGNED,
    IN  p_element_id     INT UNSIGNED,
    IN  p_detected_class VARCHAR(80),
    IN  p_confidence     DECIMAL(4,3),
    IN  p_is_hazard      TINYINT,
    IN  p_hazard_type    VARCHAR(80),
    IN  p_severity       VARCHAR(10),
    OUT p_detection_id   INT UNSIGNED
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF NOT EXISTS (SELECT 1 FROM Raw_Images WHERE image_id = p_image_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Image does not exist.';
    END IF;

    IF p_element_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM Raw_Images ri
        JOIN Drone_Flights df ON df.flight_id = ri.flight_id
        JOIN BIM_Elements be  ON be.site_id = df.site_id
        WHERE ri.image_id = p_image_id AND be.element_id = p_element_id
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BIM element does not belong to the same site as the image.';
    END IF;

    IF p_is_hazard = 1 AND (p_hazard_type IS NULL OR p_severity IS NULL) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Hazard type and severity are required for hazards.';
    END IF;

    START TRANSACTION;

    INSERT INTO ML_Detections (image_id, element_id, detected_class, confidence_score, is_safety_hazard)
    VALUES (p_image_id, p_element_id, p_detected_class, p_confidence, p_is_hazard);

    SET p_detection_id = LAST_INSERT_ID();

    IF p_is_hazard = 1 THEN
        INSERT INTO Safety_Alerts (detection_id, hazard_type, severity_level, status)
        VALUES (p_detection_id, p_hazard_type, p_severity, 'Open');
    END IF;

    COMMIT;
END$$

-- Procedure 2: safety report for one site
CREATE PROCEDURE sp_site_safety_report(IN p_site_id INT UNSIGNED)
BEGIN
    SELECT s.site_name,
           COUNT(DISTINCT f.flight_id)    AS flights,
           COUNT(DISTINCT i.image_id)     AS images,
           COUNT(DISTINCT d.detection_id) AS detections,
           COUNT(DISTINCT CASE WHEN d.is_safety_hazard = 1 THEN d.detection_id END) AS hazards,
           COUNT(DISTINCT a.alert_id)     AS total_alerts,
           COUNT(DISTINCT CASE WHEN a.status <> 'Resolved' THEN a.alert_id END)     AS open_alerts,
           COUNT(DISTINCT CASE WHEN a.severity_level = 'Critical' THEN a.alert_id END) AS critical_alerts
    FROM Sites s
    LEFT JOIN Drone_Flights f  ON f.site_id = s.site_id
    LEFT JOIN Raw_Images i     ON i.flight_id = f.flight_id
    LEFT JOIN ML_Detections d  ON d.image_id = i.image_id
    LEFT JOIN Safety_Alerts a  ON a.detection_id = d.detection_id
    WHERE s.site_id = p_site_id
    GROUP BY s.site_id, s.site_name;
END$$

-- Procedure 3: resolve an alert
CREATE PROCEDURE sp_resolve_alert(IN p_alert_id INT UNSIGNED)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Safety_Alerts WHERE alert_id = p_alert_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Alert not found.';
    END IF;
    UPDATE Safety_Alerts SET status = 'Resolved' WHERE alert_id = p_alert_id;
END$$

-- Trigger 1: auto-log High/Critical alerts
CREATE TRIGGER trg_alert_after_insert
AFTER INSERT ON Safety_Alerts
FOR EACH ROW
BEGIN
    IF NEW.severity_level IN ('High','Critical') THEN
        INSERT INTO Audit_Logs (action_type, log_message)
        VALUES ('HIGH_SEVERITY_ALERT',
                CONCAT(NEW.severity_level, ' alert #', NEW.alert_id, ' raised: ',
                       NEW.hazard_type, ' (detection #', NEW.detection_id, ')'));
    END IF;
END$$

-- Trigger 2: log alert status changes
CREATE TRIGGER trg_alert_after_update
AFTER UPDATE ON Safety_Alerts
FOR EACH ROW
BEGIN
    IF OLD.status <> NEW.status THEN
        INSERT INTO Audit_Logs (action_type, log_message)
        VALUES ('ALERT_STATUS_CHANGE',
                CONCAT('Alert #', NEW.alert_id, ' status changed from ',
                       OLD.status, ' to ', NEW.status));
    END IF;
END$$

-- Trigger 3: log alert deletions
CREATE TRIGGER trg_alert_after_delete
AFTER DELETE ON Safety_Alerts
FOR EACH ROW
BEGIN
    INSERT INTO Audit_Logs (action_type, log_message)
    VALUES ('ALERT_DELETED',
            CONCAT('Alert #', OLD.alert_id, ' (', OLD.severity_level, ', ', OLD.hazard_type, ') deleted'));
END$$

DELIMITER ;

-- ---- Using the functions, procedures and triggers ----

-- Function usage: ranked risk of active violations
SELECT alert_id, site_name, hazard_type, severity_level, confidence_score,
       fn_risk_score(severity_level, confidence_score) AS risk_score
FROM vw_ActiveSafetyViolations
ORDER BY risk_score DESC;

-- Function usage: open alerts per site
SELECT site_id, site_name, fn_site_open_alerts(site_id) AS open_alerts FROM Sites;

-- Procedure usage: register a critical hazard (also fires trg_alert_after_insert)
CALL sp_register_detection_with_alert(7, 6, 'Worker near Unshored Trench Edge', 0.921, 1,
                                      'Excavation Edge Proximity', 'Critical', @new_detection_id);
SELECT @new_detection_id AS new_detection_id;

-- Procedure usage: site report
CALL sp_site_safety_report(1);

-- Trigger verification
SELECT * FROM Audit_Logs ORDER BY log_id;

-- ============================================================
-- 3.7 TRANSACTIONS: COMMIT, ROLLBACK, SAVEPOINT
-- ============================================================

-- T1: SAVEPOINT with partial rollback, then COMMIT
START TRANSACTION;
    UPDATE Safety_Alerts SET status = 'Under Review' WHERE alert_id = 4;
    SAVEPOINT sp_after_first_update;
    UPDATE Safety_Alerts SET status = 'Resolved' WHERE alert_id = 5;
    ROLLBACK TO SAVEPOINT sp_after_first_update;   -- undoes only the alert 5 change
COMMIT;                                            -- alert 4 change is saved

SELECT alert_id, status FROM Safety_Alerts WHERE alert_id IN (4,5);

-- T2: full ROLLBACK
START TRANSACTION;
    UPDATE Safety_Alerts SET status = 'Resolved' WHERE alert_id = 2;
    DELETE FROM Safety_Alerts WHERE alert_id > 0;
    SELECT COUNT(*) AS alerts_inside_transaction FROM Safety_Alerts;
ROLLBACK;

SELECT COUNT(*) AS alerts_after_rollback FROM Safety_Alerts;



