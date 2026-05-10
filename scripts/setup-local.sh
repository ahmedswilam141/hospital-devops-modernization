#!/usr/bin/env bash
# =============================================================================
# setup-local.sh
# Bootstraps the complete local development environment from scratch.
# Run this once after cloning the repo.
#
# WHAT IT DOES:
#   1. Checks all required tools are installed
#   2. Creates .env from .env.example if not already present
#   3. Fixes all mysql_* → mysqli_* calls in the PHP codebase
#   4. Creates placeholder directories for upload volumes
#   5. Builds all Docker images
#   6. Starts all containers
#   7. Waits for health checks to pass
#   8. Prints the URLs to access the app
#
# HOW TO RUN:
#   chmod +x scripts/setup-local.sh
#   bash scripts/setup-local.sh
# =============================================================================

set -euo pipefail

# ── Colours for output ────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m' # No Colour

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo ""
echo "==========================================="
echo "  Hospital Management System — Local Setup"
echo "==========================================="
echo ""

# ── Step 1: Check prerequisites ───────────────────────────────────────────────
log_info "Checking required tools..."

command -v docker      >/dev/null 2>&1 || log_error "Docker is not installed. Install from https://docs.docker.com/get-docker/"
command -v docker-compose >/dev/null 2>&1 || \
    docker compose version >/dev/null 2>&1 || \
    log_error "docker-compose is not installed."

DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
log_success "Docker $DOCKER_VERSION"

# ── Step 2: Environment file ──────────────────────────────────────────────────
if [ ! -f .env ]; then
    log_info "Creating .env from .env.example..."
    cp .env.example .env
    log_warn ".env created — review it before running in production"
else
    log_success ".env already exists"
fi

# ── Step 3: Fix PHP mysql_* calls ─────────────────────────────────────────────
log_info "Fixing deprecated mysql_* function calls..."
bash scripts/fix-mysql.sh
log_success "PHP codebase updated to mysqli_*"

# ── Step 4: Create placeholder dirs for volumes ───────────────────────────────
log_info "Creating upload directories..."
mkdir -p app/Frontend/imge
mkdir -p app/Backend/reportfile
touch app/Frontend/imge/.gitkeep
touch app/Backend/reportfile/.gitkeep
# www-data (uid 33) needs write access
chmod 777 app/Frontend/imge app/Backend/reportfile
log_success "Upload directories ready"

# ── Step 5: Build Docker images ───────────────────────────────────────────────
log_info "Building Docker images (this takes 2-3 minutes on first run)..."
docker-compose build --no-cache
log_success "Images built"

# ── Step 6: Start all containers ──────────────────────────────────────────────
log_info "Starting all containers..."
docker-compose up -d
log_success "Containers started"

# ── Step 7: Wait for health checks ───────────────────────────────────────────
log_info "Waiting for services to become healthy..."
MAX_WAIT=120
ELAPSED=0

while true; do
    # Check if all containers are healthy
    UNHEALTHY=$(docker-compose ps | grep -c "unhealthy\|starting" || true)
    ALL_RUNNING=$(docker-compose ps | grep -c "Up" || true)

    if [ "$UNHEALTHY" -eq 0 ] && [ "$ALL_RUNNING" -ge 5 ]; then
        break
    fi

    if [ "$ELAPSED" -ge "$MAX_WAIT" ]; then
        log_warn "Timeout waiting for healthy status. Checking individual containers..."
        docker-compose ps
        break
    fi

    printf "."
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done
echo ""

# ── Step 8: Verify endpoints ──────────────────────────────────────────────────
log_info "Verifying health endpoints..."

check_endpoint() {
    local url="$1"
    local name="$2"
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    if [ "$response" = "200" ]; then
        log_success "$name → HTTP $response"
    else
        log_warn "$name → HTTP $response (may still be initializing)"
    fi
}

sleep 5  # give nginx a moment after containers are up

check_endpoint "http://localhost/nginx-health"        "Nginx"
check_endpoint "http://localhost/health.php"          "Frontend (patient portal)"
check_endpoint "http://localhost/admin/health.php"    "Backend (admin panel)"

# ── Step 9: Print access information ─────────────────────────────────────────
echo ""
echo "==========================================="
echo -e "  ${GREEN}Setup complete!${NC}"
echo "==========================================="
echo ""
echo "  Patient Portal:  http://localhost/"
echo "  Admin Panel:     http://localhost/admin/"
echo "  Doctor Login:    http://localhost/doctor.php"
echo ""
echo "  Demo credentials:"
echo "    Admin:    admin / admin123"
echo "    Patient:  patient@hospital.com / patient123"
echo "    Doctor:   doctor@hospital.com / doctor123"
echo ""
echo "  Useful commands:"
echo "    docker-compose logs -f frontend    # stream frontend logs"
echo "    docker-compose logs -f backend     # stream backend logs"
echo "    docker-compose logs -f mysql       # stream DB logs"
echo "    docker-compose ps                  # check container status"
echo "    docker-compose down                # stop everything"
echo "    docker-compose down -v             # stop + delete all data"
echo ""