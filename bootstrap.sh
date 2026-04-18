#!/usr/bin/env bash
# bootstrap.sh — Install prerequisites and kolla-ansible on Ubuntu 22.04
# Run this once on the deployment host (can be the same as the target host
# for all-in-one, or a separate bastion for multinode).
#
# Usage:
#   sudo ./bootstrap.sh [--branch <branch>] [--venv <path>]
#
# Defaults:
#   --branch  2024.1   (OpenStack Caracal — latest stable as of early 2025)
#   --venv    /opt/kolla-venv

set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────────────────
KOLLA_BRANCH="${KOLLA_BRANCH:-2024.1}"
KOLLA_VENV="${KOLLA_VENV:-/opt/kolla-venv}"
KOLLA_CONFIG_DIR="/etc/kolla"
INVENTORY_TYPE="${INVENTORY_TYPE:-all-in-one}"   # or "multinode"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)  KOLLA_BRANCH="$2"; shift 2 ;;
    --venv)    KOLLA_VENV="$2";   shift 2 ;;
    --multinode) INVENTORY_TYPE="multinode"; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo -e "\n\033[1;34m[bootstrap]\033[0m $*"; }
die()  { echo -e "\033[1;31m[error]\033[0m $*" >&2; exit 1; }
need_root() { [[ $EUID -eq 0 ]] || die "Please run as root (sudo $0)."; }

need_root

# ── 1. System packages ────────────────────────────────────────────────────────
log "Updating apt and installing system dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  git \
  python3 \
  python3-dev \
  python3-pip \
  python3-venv \
  libffi-dev \
  gcc \
  libssl-dev \
  build-essential \
  ansible-core \
  sshpass

# ── 2. Create virtualenv ──────────────────────────────────────────────────────
log "Creating Python virtualenv at ${KOLLA_VENV}..."
python3 -m venv "${KOLLA_VENV}"
# shellcheck disable=SC1091
source "${KOLLA_VENV}/bin/activate"

pip install --upgrade pip wheel

# ── 3. Install kolla-ansible ──────────────────────────────────────────────────
log "Installing kolla-ansible (branch: ${KOLLA_BRANCH})..."
pip install \
  "kolla-ansible==${KOLLA_BRANCH}.*" \
  "ansible-core>=2.16,<2.17"

# Verify
kolla-ansible --version

# ── 4. Install Ansible Galaxy dependencies ────────────────────────────────────
log "Installing Ansible Galaxy collections required by kolla-ansible..."
kolla-ansible install-deps

# ── 5. Populate /etc/kolla ────────────────────────────────────────────────────
log "Populating ${KOLLA_CONFIG_DIR}..."
mkdir -p "${KOLLA_CONFIG_DIR}"

KOLLA_SHARE="$(python3 -c 'import kolla_ansible; import os; print(os.path.dirname(kolla_ansible.__file__))')"
KOLLA_ETC_EXAMPLES="${KOLLA_SHARE}/../share/kolla-ansible/etc_examples/kolla"

# Copy example configs (do not overwrite if already customised)
if [[ -d "${KOLLA_ETC_EXAMPLES}" ]]; then
  cp -n "${KOLLA_ETC_EXAMPLES}/globals.yml"   "${KOLLA_CONFIG_DIR}/globals.yml"   2>/dev/null || true
  cp -n "${KOLLA_ETC_EXAMPLES}/passwords.yml" "${KOLLA_CONFIG_DIR}/passwords.yml" 2>/dev/null || true
else
  # Fallback: kolla-ansible ships them in a slightly different path on newer versions
  KOLLA_SHARE2="$(pip show kolla-ansible | awk '/^Location/{print $2}')/kolla_ansible"
  find "${KOLLA_SHARE2}" -name "globals.yml"   | head -1 | xargs -I{} cp -n {} "${KOLLA_CONFIG_DIR}/globals.yml"   2>/dev/null || true
  find "${KOLLA_SHARE2}" -name "passwords.yml" | head -1 | xargs -I{} cp -n {} "${KOLLA_CONFIG_DIR}/passwords.yml" 2>/dev/null || true
fi

# Use our customised globals.yml if present in the script directory
if [[ -f "${SCRIPT_DIR}/globals.yml" ]]; then
  log "Copying project globals.yml → ${KOLLA_CONFIG_DIR}/globals.yml"
  cp "${SCRIPT_DIR}/globals.yml" "${KOLLA_CONFIG_DIR}/globals.yml"
fi

# ── 6. Copy inventory ─────────────────────────────────────────────────────────
log "Copying ${INVENTORY_TYPE} inventory..."
KOLLA_INVENTORY_DIR="$(pip show kolla-ansible | awk '/^Location/{print $2}')/kolla_ansible/ansible/inventory"
if [[ -f "${SCRIPT_DIR}/inventory/${INVENTORY_TYPE}" ]]; then
  cp "${SCRIPT_DIR}/inventory/${INVENTORY_TYPE}" "/etc/kolla/${INVENTORY_TYPE}"
elif [[ -f "${KOLLA_INVENTORY_DIR}/${INVENTORY_TYPE}" ]]; then
  cp "${KOLLA_INVENTORY_DIR}/${INVENTORY_TYPE}" "/etc/kolla/${INVENTORY_TYPE}"
else
  die "Could not find inventory file for '${INVENTORY_TYPE}'"
fi

# ── 7. Generate passwords ─────────────────────────────────────────────────────
log "Generating random passwords into ${KOLLA_CONFIG_DIR}/passwords.yml..."
kolla-genpwd

# ── 8. Activate wrapper hint ──────────────────────────────────────────────────
ACTIVATE_LINE="source ${KOLLA_VENV}/bin/activate"
cat <<EOF

┌──────────────────────────────────────────────────────────────────────┐
│  Bootstrap complete!                                                 │
│                                                                      │
│  Next steps:                                                         │
│   1. Edit ${KOLLA_CONFIG_DIR}/globals.yml (network interfaces, VIPs) │
│   2. Edit /etc/kolla/${INVENTORY_TYPE} (host addresses)             │
│   3. Run: sudo ./deploy.sh [--multinode]                             │
│                                                                      │
│  To use kolla-ansible manually:                                      │
│    ${ACTIVATE_LINE}
│                                                                      │
│  Passwords are in: ${KOLLA_CONFIG_DIR}/passwords.yml                │
│  Horizon admin password: grep keystone_admin_password passwords.yml  │
└──────────────────────────────────────────────────────────────────────┘
EOF
