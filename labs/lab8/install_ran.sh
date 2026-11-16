#!/usr/bin/env bash
#
# install_oai.sh
# ---------------------------------------------------------------------------
# Installs a specific version (branch 2024.w45) of OpenAirInterface 5G from the
# duranta-project fork, builds the gNB + nrUE with the nrscope library, and
# sets up FlexRIC / E2 support for RF simulation.
#
# Reconstructed from an interactive shell history. Runtime commands
# (nr-softmodem ...) are intentionally NOT included here; see the note at the
# bottom for how to launch after building.
#
# Usage:
#   chmod +x install_oai.sh
#   ./install_oai.sh
# ---------------------------------------------------------------------------
 
set -euo pipefail
 
# --- Configuration ----------------------------------------------------------
REPO_URL="https://github.com/duranta-project/openairinterface5g.git"
OAI_DIR="$(pwd)/openairinterface5g"
OAI_BRANCH="2024.w45"
 
# --- Helpers ----------------------------------------------------------------
log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
 
# --- 1. Clone (or reuse) the repository -------------------------------------
if [ -d "${OAI_DIR}/.git" ]; then
    log "Repository already present at ${OAI_DIR}, fetching updates"
    git -C "${OAI_DIR}" fetch --all --tags
else
    log "Cloning ${REPO_URL} into ${OAI_DIR}"
    git clone "${REPO_URL}" "${OAI_DIR}"
fi
 
# --- 2. Check out the target version ----------------------------------------
log "Checking out ${OAI_BRANCH}"
cd "${OAI_DIR}"
git checkout "${OAI_BRANCH}"
 
# --- 3. Install dependencies -------------------------------------------------
cd "cmake_targets"
 
 
log "Installing OAI software dependencies (build_oai -I)"
sudo ./build_oai -I
 
# --- 4. Initialise FlexRIC / E2 submodules ----------------------------------
log "Initialising FlexRIC submodules"
cd "${OAI_DIR}/openair2/E2AP/flexric"
git submodule init
git submodule update
 
# --- 5. Build gNB + nrUE + E2 agent for RF simulation -----------------------
# -w SIMU     : target the RF simulator (no real radio hardware)
# --build-e2  : build the E2 agent so the gNB can talk to FlexRIC
log "Building gNB + nrUE + E2 agent for the RF simulator (SIMU)"
cd "${OAI_DIR}/cmake_targets"
sudo ./build_oai -I -w SIMU --gNB --nrUE --build-e2 --ninja
 
# --- Done -------------------------------------------------------------------
log "Build complete."
cat <<EOF
 
Binaries are in:
  ${OAI_DIR}/cmake_targets/ran_build/build/
 
To launch the gNB in RF simulation mode, for example:
 
  cd ${OAI_DIR}/cmake_targets/ran_build/build/
  sudo ./nr-softmodem \\
      -O ~/5G-Cell-Class/LABs/lab8/flexric_conf/gnb.conf \\
      --gNBs.[0].min_rxtxtime 6 --rfsim
 
(Adjust the -O config path to your own gnb.conf.)
EOF
