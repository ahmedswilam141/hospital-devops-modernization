<?php
$db_host = getenv('DB_HOST') ?: 'mysql';
$db_user = getenv('DB_USER') ?: 'hospital_user';
$db_pass = getenv('DB_PASS') ?: '';
$db_name = getenv('DB_NAME') ?: 'hospital';

$con = mysqli_connect($db_host, $db_user, $db_pass, $db_name);

if (!$con) {
    error_log('Database connection failed: ' . mysqli_connect_error());
    http_response_code(503);
    die(json_encode(['error' => 'Service temporarily unavailable']));
}