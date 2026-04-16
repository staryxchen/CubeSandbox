#!/usr/bin/env bash
set -euo pipefail

GITHUB_REPO="tencentcloud/CubeSandbox"
GITHUB_API_BASE="https://api.github.com/repos/${GITHUB_REPO}"

DOWNLOAD_URL="${CUBE_SANDBOX_DOWNLOAD_URL:-}"
INSTALL_ARGS=()

for arg in "$@"; do
  case "${arg}" in
    --url=*) DOWNLOAD_URL="${arg#--url=}" ;;
    *)       INSTALL_ARGS+=("${arg}") ;;
  esac
done

# ---------------------------------------------------------------------------
# Helper: HTTP GET to stdout (curl or wget)
# ---------------------------------------------------------------------------
http_get() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "${url}"
  else
    echo "[online-install] ERROR: curl or wget is required" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Auto-detect latest release asset URL from GitHub if --url was not given
# ---------------------------------------------------------------------------
if [[ -z "${DOWNLOAD_URL}" ]]; then
  echo "[online-install] no --url provided, fetching latest release from github.com/${GITHUB_REPO}..." >&2

  RELEASE_JSON="$(http_get "${GITHUB_API_BASE}/releases/latest")"

  # Extract the first browser_download_url that matches our tarball pattern.
  # We use Python (already required by the build scripts) for reliable JSON
  # parsing without needing jq.
  DOWNLOAD_URL="$(python3 - "${RELEASE_JSON}" <<'PY'
import json, sys, re

data = json.loads(sys.argv[1])
pattern = re.compile(r'^cube-sandbox-one-click-[0-9a-f]+\.tar\.gz$')
for asset in data.get("assets", []):
    if pattern.match(asset.get("name", "")):
        print(asset["browser_download_url"])
        sys.exit(0)
sys.exit(1)
PY
  )" || {
    echo "[online-install] ERROR: could not find a cube-sandbox-one-click-<sha>.tar.gz asset in the latest release." >&2
    echo "[online-install] You can specify the URL manually:" >&2
    echo "[online-install]   online-install.sh --url=<download-url> [install.sh options...]" >&2
    exit 1
  }

  echo "[online-install] latest release asset: ${DOWNLOAD_URL}" >&2
fi

# ---------------------------------------------------------------------------
# Derive the expected directory name from the tarball filename.
# The tarball produced by build-release-bundle.sh is always named
#   cube-sandbox-one-click-<git-short-sha>.tar.gz
# and extracts to a single top-level directory with the same stem.
# ---------------------------------------------------------------------------
TARBALL_FILENAME="${DOWNLOAD_URL##*/}"   # basename of URL
BUNDLE_DIRNAME="${TARBALL_FILENAME%.tar.gz}"

if [[ "${BUNDLE_DIRNAME}" != cube-sandbox-one-click-* ]]; then
  echo "[online-install] ERROR: unexpected tarball filename '${TARBALL_FILENAME}'." >&2
  echo "[online-install] Expected: cube-sandbox-one-click-<sha>.tar.gz" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

echo "[online-install] downloading ${TARBALL_FILENAME}..." >&2
if command -v curl >/dev/null 2>&1; then
  curl -fSL "${DOWNLOAD_URL}" -o "${WORK_DIR}/bundle.tar.gz"
elif command -v wget >/dev/null 2>&1; then
  wget -q "${DOWNLOAD_URL}" -O "${WORK_DIR}/bundle.tar.gz"
else
  echo "[online-install] ERROR: curl or wget is required" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Extract and verify
# ---------------------------------------------------------------------------
echo "[online-install] extracting ${TARBALL_FILENAME}..." >&2
tar -xzf "${WORK_DIR}/bundle.tar.gz" -C "${WORK_DIR}"

BUNDLE_DIR="${WORK_DIR}/${BUNDLE_DIRNAME}"
if [[ ! -d "${BUNDLE_DIR}" ]]; then
  echo "[online-install] ERROR: expected directory '${BUNDLE_DIRNAME}' not found after extraction." >&2
  echo "[online-install] The archive may be corrupted or have an unexpected layout." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Run install.sh
# ---------------------------------------------------------------------------
echo "[online-install] running install.sh (version ${BUNDLE_DIRNAME#cube-sandbox-one-click-})..." >&2
chmod +x "${BUNDLE_DIR}/install.sh"
"${BUNDLE_DIR}/install.sh" "${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"}"
