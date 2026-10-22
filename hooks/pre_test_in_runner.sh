#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/distro.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh" || true

log "Preparing runner for test..."

apt_safe() {
  local apt_timeout="${APT_TIMEOUT_SECONDS:-300}"
  local max_attempts="${APT_MAX_ATTEMPTS:-3}"
  local attempt=1
  local sleep_seconds=10

  local -a apt_opts=(
    -o Acquire::Retries=3
    -o Acquire::http::Timeout=30
    -o Acquire::https::Timeout=30
    -o Acquire::ForceIPv4=true
    -o Dpkg::Lock::Timeout=60
  )

  while :; do
    log "apt attempt ${attempt}/${max_attempts}: apt-get $*"

    if command -v timeout >/dev/null 2>&1; then
      if timeout "${apt_timeout}" sudo -n apt-get "${apt_opts[@]}" "$@"; then
        return 0
      fi
    else
      if sudo -n apt-get "${apt_opts[@]}" "$@"; then
        return 0
      fi
    fi

    if (( attempt >= max_attempts )); then
      log "apt failed permanently after ${attempt} attempts: apt-get $*"
      return 1
    fi

    log "apt attempt ${attempt} failed, retrying in ${sleep_seconds}s"
    sleep "${sleep_seconds}"
    attempt=$((attempt + 1))
  done
}

write_ubuntu_mirror_public_key() {
  cat <<'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGpvfFoBEAC8JiBxOcRBNstqW4KyaXVbR82V0GUgsSc+slZ56B7VGhpJM9/g
KegNZKfxySDH/dVepw+1bSOcVS6baKy/37X7yu0gwM2yEooIuvfh5R+3qr7+s5PD
yDIQUmotBtkeJ6N1y6SfONWseKMx07IAukXKy5r+wTVkOzrhQEy65s6HT6rcmDBz
8Ci6QB016ELejvS97MGxnLR3dJh+vf8drLFo93ssEbycIkpNTXz44xs3vzQfoWd6
3lQr6z3PYvQe+D2aVirkt/dll6GOH3MMea4J+GHx47AC/oV36Vsq0nGLtDJ6ZPHH
QOBEojzzqdft+GeKy8WAkwe+QDxGBRBd0sBkio1Z+kPhM9Atkgy8dFiZzu523NSc
z+naoTiovURgSjybUqzOLFWsoiTG6OYZoQPytFAL16q+1Ssh4x+bVUXpac1jZtQu
OZB9eBTPag1kQ7WQ9NeR2JWKcKbvZqdOU5vFT/kCKl9JTeXdvRiCWUHX+pod3aMO
o8HqiXpXgK6Lq4vGvMCvmsNUEdcIOi1Vexe6KGCSOPLprgcpV3QAUilFyoLeO4zO
X2JuukAqUs1gyj427CvgumonoesV+kPTudLBTGpTSEFjIqGOjbYrMoEPUTjV9eod
ZaVsf/TKc++8Y5ju/tUw/+xoWT2K0sEhHIyNb9Dsi6yetHnwMiQU1qR31wARAQAB
tD9wcmVmb3JrIG5ldHdvcmsgc29sdXRpb25zIChDSSBzaWduaW5nIGtleSkgPHN1
cHBvcnRAcHJlZm9yay5kZT6JAnMEEwEIAF0WIQQIiLRbqGisaiddCLG1HFalmhb2
ggUCam98WhsUgAAAAAAEAA5tYW51MiwyLjUrMS4xMiwwLDMCGwMFCQlmAYAFCwkI
BwICIgIGFQoJCAsCBBYCAwECHgcCF4AACgkQtRxWpZoW9oICuA//UKxNTu4eAcF9
cb0sosb440ClCgqsw5fAfTYo44638yudxpHVz1xaZucZkYqd4oJagXThtoAEim/R
ctAZcC4eZXKh0teC+6kTJV1SOaCwTLMTxe2RVb1IsNgdpcsgQrbPdZy/AjPhihnp
Y3qCVm9E7J2vSlwl4OP2LGzxqMCIF8xZt9VyChWdPnqdrf1tsQQbT9EKU/GiJiti
7M4splC3cxzWUoYScrj2vqYvn/Mi2vcZHEfCP6ndlvJL4j8J8oRmImTkfC+JfQkG
tz3kkFNmiKXUTnDXeH3GowP35VnXsIVwth4BupZxdI07WH+J85TCM0BqmL2W6/Gv
q3QomKnDlu+kZqgLwI/tCJ/Q/oIKcfhSzNbod+Wb9QqNtR6wRbfObOqSpoULiTO2
KyNyLISJyqfXHtQhNl3CQ3M1MAbq6+5EpLexDeKmtG3kbGepB2i5ss+o7QrI/mju
mNma++YIgrTg0p4rfs8kGjnfyMshrQP7qYkplIcczS/3DPgflGgKP2N+SLgnnw/1
4tT8LvFg4KL/hDFs671V4JSA8XKjiTiqAbzbB/a5L1ohGrcrzSMHDCqmXQr/3wzu
CNDDIa0CuvxKNQHUQYWBRqx0delgkgNtUXQTPmcPz17FmSIxkpwsKMAKWPribU92
5kr7MIeRP/iidwd2gI8zCw2Y4eXvUss=
=hlM7
-----END PGP PUBLIC KEY BLOCK-----
EOF
}

install_ubuntu_mirror_keyring() {
  local key_tmp="${TMPDIR:-/tmp}/pulp-signing-public.asc"
  local keyring_path="/usr/share/keyrings/pulp-signing.gpg"

  if ! command -v gpg >/dev/null 2>&1; then
    log "gpg is required to install the Ubuntu mirror signing key"
    return 1
  fi

  log "Installing Ubuntu mirror signing key from embedded key material"
  write_ubuntu_mirror_public_key > "$key_tmp"
  sudo install -d -m 0755 /usr/share/keyrings
  sudo gpg --batch --dearmor -o "$keyring_path" "$key_tmp"
  sudo chmod 0644 "$keyring_path"
}

configure_ubuntu_mirror() {
  local mirror_root="${APT_UBUNTU_MIRROR_ROOT:-}"
  local suite=""
  local keyring_path="/usr/share/keyrings/pulp-signing.gpg"

  if [[ -z "${mirror_root}" ]]; then
    return 0
  fi

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
      log "APT_UBUNTU_MIRROR_ROOT is set, but runner is not Ubuntu; skipping mirror rewrite"
      return 0
    fi
    suite="${VERSION_CODENAME:-}"
  fi

  if [[ -z "${suite}" ]]; then
    log "Ubuntu mirror rewrite requested but VERSION_CODENAME is unavailable"
    return 1
  fi

  mirror_root="${mirror_root%/}"
  log "Rewriting Ubuntu apt sources to ${mirror_root}"

  install_ubuntu_mirror_keyring
  sudo install -d -m 0755 /etc/apt/sources.list.d
  if sudo test -f /etc/apt/sources.list && ! sudo test -f /etc/apt/sources.list.orig; then
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.orig
  fi
  if sudo test -f /etc/apt/sources.list.d/ubuntu.sources && ! sudo test -f /etc/apt/sources.list.d/ubuntu.sources.orig; then
    sudo cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.orig
  fi
  if sudo test -f /etc/apt/sources.list.d/ubuntu.sources && ! sudo test -f /etc/apt/sources.list.d/ubuntu.sources.disabled; then
    sudo mv /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.disabled
  fi
  printf '' | sudo tee /etc/apt/sources.list >/dev/null
  cat <<EOF2 | sudo tee /etc/apt/sources.list.d/pulp-ubuntu-mirror.sources >/dev/null
Types: deb
URIs: ${mirror_root}/ubuntu-base
Suites: ${suite}
Components: main restricted universe multiverse
Signed-By: ${keyring_path}

Types: deb
URIs: ${mirror_root}/ubuntu-updates-base
Suites: ${suite}-updates
Components: main restricted universe multiverse
Signed-By: ${keyring_path}

Types: deb
URIs: ${mirror_root}/ubuntu-backports-base
Suites: ${suite}-backports
Components: main restricted universe multiverse
Signed-By: ${keyring_path}

Types: deb
URIs: ${mirror_root}/ubuntu-security-base
Suites: ${suite}-security
Components: main restricted universe multiverse
Signed-By: ${keyring_path}
EOF2
}

# hier nur Dinge, die der Runner braucht (z.B. docker, jq etc.)
# Beispiel:
if is_debian_like && ! command -v jq >/dev/null 2>&1; then
  apt_safe update -y
  apt_safe install -y --no-install-recommends jq
fi
