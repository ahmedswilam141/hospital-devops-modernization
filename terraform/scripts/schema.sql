-- =============================================================================
-- schema.sql
-- Converted from database_con.php (which used mysql_query() for CREATE TABLE)
--
-- This file is:
--   1. Mounted into the MySQL container at /docker-entrypoint-initdb.d/
--      so the database is created automatically on first docker-compose up
--   2. Run against RDS via the bastion host during AWS deployment:
--      mysql -h <rds-endpoint> -u admin -p < scripts/schema.sql
--   3. The authoritative source of truth for the database schema
--
-- CHANGES FROM ORIGINAL:
--   - Added IF NOT EXISTS to all CREATE TABLE (safe to run multiple times)
--   - Added password column to patient table (was missing in original schema
--     but used in signup_com.php and p_logincheck.php)
--   - Added specilist column to doctor table (used in doctor_reg.php INSERT)
--   - Added admin table (used in Backend/logincheck.php — was never defined)
--   - Added proper charset/collation declarations
-- =============================================================================

CREATE DATABASE IF NOT EXISTS hospital
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE hospital;

-- ── Patient table ─────────────────────────────────────────────────────────────
-- patientID is used as the login username (email address in the app)
CREATE TABLE IF NOT EXISTS patient (
    patientID   VARCHAR(20)     NOT NULL,
    pname       VARCHAR(50)     NOT NULL,
    age         FLOAT(5,2),
    gender      VARCHAR(10),
    address     VARCHAR(70),
    phone       VARCHAR(15),
    password    VARCHAR(255)    NOT NULL DEFAULT '',   -- stores plaintext in original; keep as-is
    pimage      VARCHAR(50),
    PRIMARY KEY (patientID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── Doctor table ──────────────────────────────────────────────────────────────
-- doctorID is the doctor's login username (email)
CREATE TABLE IF NOT EXISTS doctor (
    doctorID    VARCHAR(20)     NOT NULL,
    dname       VARCHAR(50)     NOT NULL,
    address     VARCHAR(70),
    phoneno     VARCHAR(15),
    gender      VARCHAR(10),
    password    VARCHAR(255)    NOT NULL DEFAULT '',
    specilist   VARCHAR(50),                           -- specialization field added
    dimage      VARCHAR(50),
    PRIMARY KEY (doctorID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── Report table ──────────────────────────────────────────────────────────────
-- Stores metadata for uploaded PDF reports. File stored in reportfile/ volume.
CREATE TABLE IF NOT EXISTS report (
    reportID    VARCHAR(20)     NOT NULL,
    patientID   VARCHAR(20)     NOT NULL,
    date        DATE,
    time        TIME,
    reportf     VARCHAR(100),                          -- filename of the uploaded PDF
    PRIMARY KEY (reportID),
    FOREIGN KEY (patientID) REFERENCES patient(patientID)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── Appointment table ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS appointment (
    patientID   VARCHAR(20)     NOT NULL,
    doctorID    VARCHAR(20)     NOT NULL,
    app_no      VARCHAR(20)     NOT NULL,
    date        DATE,
    time        TIME,
    PRIMARY KEY (doctorID, app_no),
    FOREIGN KEY (patientID) REFERENCES patient(patientID)
        ON DELETE CASCADE,
    FOREIGN KEY (doctorID)  REFERENCES doctor(doctorID)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── History table ─────────────────────────────────────────────────────────────
-- Patient treatment history written by doctors
CREATE TABLE IF NOT EXISTS history (
    patientID   VARCHAR(20)     NOT NULL,
    doctorID    VARCHAR(20)     NOT NULL,
    details     VARCHAR(150),
    date        DATE,
    time        TIME,
    FOREIGN KEY (patientID) REFERENCES patient(patientID)
        ON DELETE CASCADE,
    FOREIGN KEY (doctorID)  REFERENCES doctor(doctorID)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── Doctor availability table ─────────────────────────────────────────────────
-- Stores which days/times each doctor is available (used in make_app.php AJAX)
CREATE TABLE IF NOT EXISTS docDays (
    doctorID    VARCHAR(20)     NOT NULL,
    days        VARCHAR(100)    NOT NULL,
    time        TIME,
    PRIMARY KEY (doctorID, days),
    FOREIGN KEY (doctorID) REFERENCES doctor(doctorID)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── Admin table ───────────────────────────────────────────────────────────────
-- Used by Backend/logincheck.php — was missing from original database_con.php
-- The original code does SELECT * FROM admin, so this table must exist.
CREATE TABLE IF NOT EXISTS admin (
    Username    VARCHAR(50)     NOT NULL,
    Password    VARCHAR(255)    NOT NULL,
    PRIMARY KEY (Username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── Seed data ─────────────────────────────────────────────────────────────────
-- Default admin account for development. Change before any public deployment.
-- Username: admin  Password: admin123 (plaintext — matches original app behaviour)
INSERT IGNORE INTO admin (Username, Password) VALUES ('admin', 'admin123');

-- Sample doctor for demo/testing
INSERT IGNORE INTO doctor (doctorID, dname, address, phoneno, gender, password, specilist, dimage)
VALUES ('doctor@hospital.com', 'Dr. Ahmed Hassan', 'Cairo Medical District', '01012345678',
        'Male', 'doctor123', 'Cardiology', 'doctor.jpg');

-- Sample availability for the demo doctor
INSERT IGNORE INTO docDays (doctorID, days, time)
VALUES
    ('doctor@hospital.com', 'Monday',    '09:00:00'),
    ('doctor@hospital.com', 'Wednesday', '09:00:00'),
    ('doctor@hospital.com', 'Thursday',  '14:00:00');

-- Sample patient for demo/testing
INSERT IGNORE INTO patient (patientID, pname, age, gender, address, phone, password, pimage)
VALUES ('patient@hospital.com', 'Sara Mohamed', 28, 'Female', 'Nasr City, Cairo',
        '01098765432', 'patient123', 'patient.jpg');