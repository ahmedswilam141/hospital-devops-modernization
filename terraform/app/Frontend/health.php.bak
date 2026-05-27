<?php
// =============================================================================
// health.php — Frontend container health check endpoint
//
// Called by:
//   - Docker HEALTHCHECK instruction (every 30s)
//   - Kubernetes liveness probe  → restart pod if this fails
//   - Kubernetes readiness probe → stop routing traffic here if this fails
//   - AWS ALB target group health check
//   - Your chaos-test.sh script (proves zero-downtime during pod kill)
//
// Returns HTTP 200 + JSON if healthy, HTTP 503 + JSON if not.
// K8s only cares about the status code. The JSON body is for your debugging.
// =============================================================================

header('Content-Type: application/json');

$checks = [];
$healthy = true;

// ── Check 1: MySQL (RDS in production) ───────────────────────────────────────
// If the database is unreachable, the entire app is broken — patients cannot
// log in, appointments cannot be booked, nothing works. Return 503 so K8s
// stops routing traffic to this pod immediately.
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

// ── Check 2: Redis (session store) ───────────────────────────────────────────
// If Redis is down, sessions stop working. New logins will fail and existing
// sessions will be lost. This is a critical dependency.
$redis_host = getenv('REDIS_HOST') ?: 'redis';

if (class_exists('Redis')) {
    $redis = new Redis();
    try {
        $connected = @$redis->connect($redis_host, 6379, 2.0); // 2s timeout
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

// ── Check 3: Writable upload directory ───────────────────────────────────────
// Profile photo uploads land in imge/. If this directory isn't writable,
// patient/doctor registration will silently fail on the image upload step.
$upload_dir = __DIR__ . '/imge';
if (is_dir($upload_dir) && is_writable($upload_dir)) {
    $checks['upload_dir'] = 'writable';
} else {
    $checks['upload_dir'] = 'not_writable';
    // Not marking unhealthy — app still works, just uploads fail
    // Change to $healthy = false if you want strict upload checking
}

// ── Response ──────────────────────────────────────────────────────────────────
$status_code = $healthy ? 200 : 503;
http_response_code($status_code);

echo json_encode([
    'status'    => $healthy ? 'ok' : 'unhealthy',
    'service'   => 'frontend',
    'timestamp' => date('c'),
    'checks'    => $checks,
    'php'       => PHP_VERSION,
], JSON_PRETTY_PRINT);