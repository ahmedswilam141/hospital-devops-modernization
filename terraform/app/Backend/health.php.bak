<?php
// =============================================================================
// health.php — Backend (Admin) container health check endpoint
//
// Same role as Frontend/health.php but checks the backend-specific
// upload directory: reportfile/ where PDF reports are stored.
// =============================================================================

header('Content-Type: application/json');

$checks = [];
$healthy = true;

// ── Check 1: MySQL ────────────────────────────────────────────────────────────
$db_host = getenv('DB_HOST') ?: 'mysql';
$db_user = getenv('DB_USER') ?: 'hospital_user';
$db_pass = getenv('DB_PASS') ?: '';
$db_name = getenv('DB_NAME') ?: 'hospital';

$con = @mysqli_connect($db_host, $db_user, $db_pass, $db_name);
if ($con) {
    $checks['database'] = 'ok';
    mysqli_close($con);
} else {
    $checks['database'] = 'unreachable';
    $healthy = false;
}

// ── Check 2: Redis ────────────────────────────────────────────────────────────
$redis_host = getenv('REDIS_HOST') ?: 'redis';

if (class_exists('Redis')) {
    $redis = new Redis();
    try {
        $connected = @$redis->connect($redis_host, 6379, 2.0);
        if ($connected) {
            $redis->ping();
            $checks['redis'] = 'ok';
        } else {
            $checks['redis'] = 'unreachable';
            $healthy = false;
        }
    } catch (Exception $e) {
        $checks['redis'] = 'error: ' . $e->getMessage();
        $healthy = false;
    }
} else {
    $checks['redis'] = 'extension_not_loaded';
    $healthy = false;
}

// ── Check 3: Report file upload directory ────────────────────────────────────
// This is the critical backend-specific check.
// reportfile/ is where PDF reports land when admin uploads them.
// In Docker: this is a named volume shared with the frontend container.
// In K8s:    this is a PersistentVolumeClaim or S3 mount.
// If not writable, report uploads silently fail — patients can't get reports.
$report_dir = __DIR__ . '/reportfile';
if (is_dir($report_dir) && is_writable($report_dir)) {
    $checks['reportfile_dir'] = 'writable';
} else {
    $checks['reportfile_dir'] = 'not_writable';
    $healthy = false; // This IS critical for the backend — mark unhealthy
}

// ── Check 4: Profile image directory ─────────────────────────────────────────
// Backend writes doctor/patient photos to the shared imge/ volume.
// Mounted from the same named volume as frontend's imge/ directory.
$imge_dir = __DIR__ . '/imge';
if (is_dir($imge_dir) && is_writable($imge_dir)) {
    $checks['imge_dir'] = 'writable';
} else {
    $checks['imge_dir'] = 'not_writable';
    // Warn but don't fail — registration still works, photo just won't save
}

// ── Response ──────────────────────────────────────────────────────────────────
$status_code = $healthy ? 200 : 503;
http_response_code($status_code);

echo json_encode([
    'status'    => $healthy ? 'ok' : 'unhealthy',
    'service'   => 'backend',
    'timestamp' => date('c'),
    'checks'    => $checks,
    'php'       => PHP_VERSION,
], JSON_PRETTY_PRINT);