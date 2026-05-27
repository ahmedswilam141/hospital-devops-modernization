<?php
// =============================================================================
// app/Backend/report_upload.php — S3 VERSION
//
// WHAT CHANGED FROM THE ORIGINAL:
//   Original: move_uploaded_file() writes the PDF to reportfile/ on the container's
//             local filesystem. In K8s, each pod has its own filesystem — the file
//             would exist only on the pod that received the upload request. When
//             nginx routes the next request to a different pod, the file is gone.
//
//   New:      Uploads the PDF to S3. S3 is centralized — every pod reads from
//             the same bucket. This is the correct solution for containerized
//             file uploads.
//
// DEPENDENCIES:
//   The AWS SDK for PHP must be installed in the Docker image.
//   Add to docker/Dockerfile.backend:
//     RUN curl -sS https://getcomposer.org/installer | php && \
//         php composer.phar require aws/aws-sdk-php && \
//         rm composer.phar
//
// CREDENTIALS:
//   No hardcoded keys. The SDK reads credentials from the EC2 instance
//   metadata service (IMDS) — EKS node IAM role provides them automatically.
//   This works because the S3 IAM policy is attached to the EKS node role
//   in Terraform modules/s3/main.tf.
//
// ENVIRONMENT VARIABLES (from K8s ConfigMap):
//   S3_BUCKET  — the bucket name (e.g. hospital-devops-reports-abc123)
//   AWS_REGION — the AWS region (e.g. us-east-1)
// =============================================================================

session_start();
if (!$_SESSION['id']) {
    header("Location:index.html");
    exit;
}

require_once __DIR__ . '/vendor/autoload.php';

use Aws\S3\S3Client;
use Aws\Exception\AwsException;

include("connection.php");

// ============================================================================
// VALIDATE INPUTS
// ============================================================================

$pid   = $_POST['email']  ?? '';
$date1 = $_POST['date']   ?? '';
$time  = $_POST['time']   ?? '';

if (empty($pid) || empty($date1) || empty($time)) {
    die("<b>Error: Missing required fields.</b>");
}

if (!isset($_FILES['reportfile']) || $_FILES['reportfile']['error'] !== UPLOAD_ERR_OK) {
    die("<b>Error: No file uploaded or upload failed.</b>");
}

// ============================================================================
// GENERATE REPORT ID (same logic as original)
// ============================================================================

$count = 0;
$r = mysqli_query($con, "SELECT * FROM report WHERE date='$date1' AND patientID='$pid'");
while ($row = mysqli_fetch_row($r)) {
    $count++;
}
$count++;
$rid = "Report no." . $count;

// ============================================================================
// UPLOAD TO S3
//
// S3 key structure: reports/<patient_id>/<filename>
// This organises reports by patient in the bucket.
// ============================================================================

$originalName = basename($_FILES['reportfile']['name']);
$s3Key        = "reports/{$pid}/{$originalName}";
$tmpPath      = $_FILES['reportfile']['tmp_name'];
$s3Bucket     = getenv('S3_BUCKET');
$awsRegion    = getenv('AWS_REGION') ?: 'us-east-1';

try {
    // SDK instantiated without credentials — uses IAM role from instance metadata
    $s3 = new S3Client([
        'version' => 'latest',
        'region'  => $awsRegion,
    ]);

    $s3->putObject([
        'Bucket'      => $s3Bucket,
        'Key'         => $s3Key,
        'SourceFile'  => $tmpPath,
        'ContentType' => $_FILES['reportfile']['type'] ?: 'application/pdf',
    ]);

    // Store the S3 key in the database (not just the filename)
    // This lets report_download.php generate a pre-signed URL for download
    $docfile = $s3Key;

} catch (AwsException $e) {
    error_log("S3 upload failed: " . $e->getMessage());
    die("<b>Error: File upload to storage failed. Please try again.</b>");
}

// ============================================================================
// INSERT RECORD INTO DATABASE
// ============================================================================

$qry    = "INSERT INTO report VALUES('$rid','$pid','$date1','$time','$docfile')";
$result = mysqli_query($con, $qry);

if ($result) {
    print "<b>File Uploaded Successfully</b>&nbsp;" . htmlspecialchars($rid);
} else {
    error_log("DB insert failed: " . mysqli_error($con));
    print mysqli_error($con);
}
?>
