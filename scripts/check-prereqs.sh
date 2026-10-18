#!/usr/bin/env bash
# Check that the tools needed to run Lecture Indexer locally are installed.
#   make doctor   (or scripts/check-prereqs.sh)
# Exits 1 if something required for `make dev-up` and the frontend is missing.
# Install instructions: docs/local-development.md
set -uo pipefail

GUIDE="docs/local-development.md"
problems=0
docker_access_pending=false

ok()       { printf '  %-9s %s\n' "ok" "$1"; }
optional() { printf '  %-9s %s\n' "optional" "$1"; }
fail()     { printf '  %-9s %s\n' "$1" "$2"; problems=$((problems + 1)); }
hint()     { printf '            → %s\n' "$1"; }

# version_ge <have> <need>: true if have >= need (both like 1.2.3)
version_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]; }

# Extract the first x.y[.z] number from a command's output.
version_of() { "$@" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1; }

require() {  # require <command> <apt package or install hint>
  if command -v "$1" >/dev/null 2>&1; then
    ok "$1 $(version_of "$1" --version)"
  else
    fail "missing" "$1"
    hint "$2"
  fi
}

echo "Required tools"
require git "sudo apt install git"
require make "sudo apt install make"
require curl "sudo apt install curl"
require python3 "sudo apt install python3"

if command -v docker >/dev/null 2>&1; then
  ok "docker $(version_of docker --version)"
  compose=$(version_of docker compose version)
  if [[ -z $compose ]]; then
    fail "missing" "docker compose (the Compose v2 plugin)"
    hint "install docker-compose-plugin; see $GUIDE#install-prerequisites-linux"
  elif version_ge "$compose" 2.20; then
    ok "docker compose $compose"
  else
    fail "too old" "docker compose $compose (needs 2.20+)"
    hint "upgrade Docker; see $GUIDE#install-prerequisites-linux"
  fi
else
  fail "missing" "docker"
  hint "Linux: Docker Engine; WSL2: Docker Desktop with WSL integration. See $GUIDE"
fi

if command -v node >/dev/null 2>&1; then
  node_version=$(version_of node --version)
  if version_ge "$node_version" 22.22; then
    ok "node $node_version"
  else
    fail "too old" "node $node_version (needs 22.22+)"
    hint "nvm install 22 (see $GUIDE#install-prerequisites-linux)"
  fi
else
  fail "missing" "node"
  hint "install nvm, then: nvm install 22 (see $GUIDE#install-prerequisites-linux)"
fi
require npm "comes with Node; see $GUIDE#install-prerequisites-linux"

echo
echo "Optional tools"
if command -v uv >/dev/null 2>&1; then
  ok "uv $(version_of uv --version) (Python tests and lint)"
else
  optional "uv not found: needed only for make install / lint / test / test-db"
  hint "curl -LsSf https://astral.sh/uv/install.sh | sh"
fi

# Only for make cloud-status / cloud-pause / cloud-resume.
cloud_missing=()
for tool in gcloud kubectl gke-gcloud-auth-plugin; do
  command -v "$tool" >/dev/null 2>&1 || cloud_missing+=("$tool")
done
if (( ${#cloud_missing[@]} == 0 )); then
  ok "gcloud $(version_of gcloud --version), kubectl $(version_of kubectl version --client), gke-gcloud-auth-plugin (make cloud-*)"
else
  optional "${cloud_missing[*]} not found: needed only for make cloud-status / cloud-pause / cloud-resume"
  hint "see $GUIDE#install-cloud-tools-optional, or run them from Cloud Shell"
fi

echo
echo "Docker access"
if command -v docker >/dev/null 2>&1; then
  if [[ ${COMPOSE:-} == sudo* ]]; then
    # Never prompt for a password from this script.
    if sudo -n docker info >/dev/null 2>&1; then
      ok "COMPOSE uses sudo, and sudo docker works"
    elif sudo -n true 2>/dev/null; then
      fail "no daemon" "sudo docker info failed: is the Docker daemon running?"
      hint "Linux: sudo systemctl start docker; WSL2: start Docker Desktop"
    else
      ok "COMPOSE uses sudo; make dev-up will ask for your password"
    fi
  else
    info=$(docker info 2>&1 >/dev/null)
    if [[ $? -eq 0 ]]; then
      ok "docker works without sudo"
    elif [[ $info == *"permission denied"* ]]; then
      # Not a failure: either fix works, and it's the developer's choice.
      docker_access_pending=true
      optional "your user can't reach the Docker daemon; pick one:"
      hint 'join the docker group: sudo usermod -aG docker $USER  (then log out and in)'
      hint 'or use sudo per command: export COMPOSE="sudo docker compose"'
      hint "details: $GUIDE#docker-permissions"
    else
      fail "no daemon" "docker info failed: is the Docker daemon running?"
      hint "Linux: sudo systemctl start docker; WSL2: start Docker Desktop and enable WSL integration"
    fi
  fi
else
  echo "  (skipped: docker not installed)"
fi

echo
if (( problems == 0 )) && $docker_access_pending; then
  echo "Almost ready: choose a Docker access option above, then run make dev-up."
elif (( problems == 0 )); then
  echo "Ready: run make dev-up, then the frontend steps in $GUIDE."
else
  echo "$problems problem(s) above. Install instructions: $GUIDE"
  exit 1
fi
