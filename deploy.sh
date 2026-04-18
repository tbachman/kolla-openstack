#!/usr/bin/env bash
# deploy.sh — Run kolla-ansible deployment stages
#
# Usage:
#   sudo ./deploy.sh [--multinode] [--step <stage>] [--tags <tags>]
#
# Stages (run sequentially by default):
#   bootstrap-servers  — prepare target hosts
#   prechecks          — validate environment
#   pull               — pull Docker images
#   deploy             — deploy OpenStack services
#   post-deploy        — generate openrc and clouds.yaml
#
# Examples:
#   sudo ./deploy.sh                          # full all-in-one deploy
#   sudo ./deploy.sh --multinode              # full multinode deploy
#   sudo ./deploy.sh --step prechecks         # run only prechecks
#   sudo ./deploy.sh --step deploy --tags nova,neutron

set -euo pipefail

KOLLA_VENV="${KOLLA_VENV:-/opt/kolla-venv}"
KOLLA_CONFIG_DIR="/etc/kolla"
INVENTORY_TYPE="${INVENTORY_TYPE:-all-in-one}"
STEP=""
EXTRA_TAGS=""
VERBOSITY=""

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --multinode)    INVENTORY_TYPE="multinode"; shift ;;
    --step)         STEP="$2"; shift 2 ;;
    --tags)         EXTRA_TAGS="--tags $2"; shift 2 ;;
    -v|-vv|-vvv)   VERBOSITY="$1"; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

log()  { echo -e "\n\033[1;34m[deploy]\033[0m $*"; }
die()  { echo -e "\033[1;31m[error]\033[0m $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Please run as root (sudo $0)."

# ── Activate virtualenv ───────────────────────────────────────────────────────
[[ -f "${KOLLA_VENV}/bin/activate" ]] || die "Virtualenv not found at ${KOLLA_VENV}. Run bootstrap.sh first."
# shellcheck disable=SC1091
source "${KOLLA_VENV}/bin/activate"

INVENTORY="${KOLLA_CONFIG_DIR}/${INVENTORY_TYPE}"
[[ -f "${INVENTORY}" ]] || die "Inventory not found: ${INVENTORY}"

KA="kolla-ansible -i ${INVENTORY} ${VERBOSITY}"

run_stage() {
  local stage="$1"
  log "Running stage: ${stage}"
  # shellcheck disable=SC2086
  ${KA} ${stage} ${EXTRA_TAGS}
}

# ── Stages ────────────────────────────────────────────────────────────────────
ALL_STAGES=(bootstrap-servers prechecks pull deploy post-deploy)

if [[ -n "${STEP}" ]]; then
  run_stage "${STEP}"
else
  for stage in "${ALL_STAGES[@]}"; do
    run_stage "${stage}"
  done
fi

# ── Post-deploy summary ───────────────────────────────────────────────────────
if [[ -z "${STEP}" || "${STEP}" == "post-deploy" ]]; then
  ADMIN_PASS=$(awk '/^keystone_admin_password:/{print $2}' "${KOLLA_CONFIG_DIR}/passwords.yml" 2>/dev/null || echo "<see passwords.yml>")
  KOLLA_INTERNAL_VIP=$(awk '/^kolla_internal_vip_address:/{print $2}' "${KOLLA_CONFIG_DIR}/globals.yml" 2>/dev/null || echo "<your-vip>")

  cat <<EOF

┌──────────────────────────────────────────────────────────────────────┐
│  OpenStack deployment complete!                                      │
│                                                                      │
│  Horizon dashboard:  http://${KOLLA_INTERNAL_VIP}/                   │
│  Admin password:     ${ADMIN_PASS}                                   │
│                                                                      │
│  CLI credentials:                                                    │
│    source /etc/kolla/admin-openrc.sh                                 │
│    cat /etc/kolla/clouds.yaml                                        │
│                                                                      │
│  To reconfigure:   kolla-ansible -i ${INVENTORY_TYPE} reconfigure    │
│  To upgrade:       kolla-ansible -i ${INVENTORY_TYPE} upgrade        │
│  To destroy:       kolla-ansible -i ${INVENTORY_TYPE} destroy        │
└──────────────────────────────────────────────────────────────────────┘
EOF
fi
