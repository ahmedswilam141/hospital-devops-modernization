#!/usr/bin/env bash
# =============================================================================
# fix-mysql.sh
# Replaces all deprecated mysql_* function calls with mysqli_* equivalents
# across the entire PHP codebase.
#
# WHAT IT DOES:
#   The original app uses mysql_* functions which were removed in PHP 7.
#   This script performs a mechanical find-and-replace across all PHP files.
#   It is safe to run multiple times (idempotent).
#
# IMPORTANT — WHAT THIS SCRIPT DOES NOT FIX:
#   The mysqli_* functions require $con (the connection) as the first argument.
#   e.g. mysql_query("SELECT...")  →  mysqli_query($con, "SELECT...")
#   The connection.php files are replaced entirely (not patched) because they
#   also need env var injection. All other PHP files only need the function
#   name changes — $con is already in scope via include("connection.php").
#
# HOW TO RUN:
#   chmod +x scripts/fix-mysql.sh
#   bash scripts/fix-mysql.sh
# =============================================================================

set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)/app"
echo "Fixing mysql_* calls in: $APP_DIR"
echo ""

# Count how many files need fixing before we start
BEFORE=$(grep -rl "mysql_query\|mysql_fetch\|mysql_connect\|mysql_error\|mysql_num_rows\|mysql_select_db" \
    "$APP_DIR" --include="*.php" | wc -l)
echo "Files containing mysql_* calls: $BEFORE"
echo ""

# ── Step 1: Fix mysql_query($qry) → mysqli_query($con, $qry) ─────────────────
# The connection handle ($con) must be the first argument in mysqli_query.
# The original code calls mysql_query($variable) — we add $con as first arg.
find "$APP_DIR" -name "*.php" | while read -r file; do
    # Skip connection.php files — they are replaced entirely, not patched
    if [[ "$file" == *"connection.php" ]]; then
        echo "  SKIP (will be replaced): $file"
        continue
    fi

    # mysql_query("string")  →  mysqli_query($con, "string")
    sed -i 's/mysql_query(\s*"/mysqli_query($con, "/g' "$file"
    # mysql_query($var)      →  mysqli_query($con, $var)
    sed -i 's/mysql_query(\s*\$/mysqli_query($con, \$/g' "$file"
    # mysql_query($con,...) already — skip (shouldn't exist but be safe)

    # mysql_fetch_array($result)  →  mysqli_fetch_array($result)
    sed -i 's/mysql_fetch_array(/mysqli_fetch_array(/g' "$file"

    # mysql_fetch_row($result)    →  mysqli_fetch_row($result)
    sed -i 's/mysql_fetch_row(/mysqli_fetch_row(/g' "$file"

    # mysql_num_rows($result)     →  mysqli_num_rows($result)
    sed -i 's/mysql_num_rows(/mysqli_num_rows(/g' "$file"

    # mysql_error()               →  mysqli_error($con)
    sed -i 's/mysql_error()/mysqli_error($con)/g' "$file"

    # mysql_select_db("db", $con) →  mysqli_select_db($con, "db")
    # (Only in connection.php which we skip — but handle if found elsewhere)
    sed -i 's/mysql_select_db(\s*"\([^"]*\)"\s*,\s*\$con)/mysqli_select_db($con, "\1")/g' "$file"

    # mysql_connect() — replace with include of connection.php if found standalone
    # (change_p.php line 210 has a direct call — handle it specifically)
    if grep -q "mysql_connect(" "$file"; then
        echo "  WARNING: Standalone mysql_connect() found in $file"
        echo "  → Replacing with include of connection.php"
        # Remove the standalone mysql_connect block and replace with include
        sed -i '/mysql_connect(/,/mysql_select_db/d' "$file"
        sed -i '1a include("connection.php");' "$file"
    fi
done

# ── Step 2: Fix change_p.php specifically ─────────────────────────────────────
# change_p.php has a standalone mysql_connect() at line 210 (not using connection.php)
# The sed above handles it, but let's verify
CHANGE_P="$APP_DIR/Backend/change_p.php"
if grep -q "mysql_connect\|mysqli_connect" "$CHANGE_P"; then
    echo ""
    echo "  Fixing change_p.php standalone DB connection..."
    # The file already includes connection.php at the top for other things,
    # so the standalone call is redundant — remove it
    sed -i '/mysqli_connect(/d' "$CHANGE_P"
    sed -i '/mysql_select_db/d' "$CHANGE_P"
fi

# ── Step 3: Verify ────────────────────────────────────────────────────────────
echo ""
AFTER=$(grep -rl "mysql_query\|mysql_fetch\|mysql_connect\|mysql_error\|mysql_num_rows" \
    "$APP_DIR" --include="*.php" 2>/dev/null | grep -v "connection.php" | wc -l)

echo "Files still containing unfixed mysql_* calls: $AFTER"

if [ "$AFTER" -eq 0 ]; then
    echo ""
    echo "✓ All mysql_* calls fixed successfully"
    echo "✓ Now replace both connection.php files with the versions in app/Frontend/ and app/Backend/"
    echo "✓ Those files already use mysqli with environment variables"
else
    echo ""
    echo "⚠ Some files may need manual review — check the output above"
    grep -rl "mysql_query\|mysql_fetch\|mysql_connect" "$APP_DIR" --include="*.php" \
        | grep -v "connection.php" || true
fi