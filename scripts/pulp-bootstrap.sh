#!/usr/bin/env bash
set -euo pipefail

# Accept both legacy PULP_* and pulp-cli native PULP_CLI_* variables.
PULP_CLI_BASE_URL="${PULP_CLI_BASE_URL:-${PULP_URL:-}}"
PULP_CLI_USERNAME="${PULP_CLI_USERNAME:-${PULP_USERNAME:-}}"
PULP_CLI_PASSWORD="${PULP_CLI_PASSWORD:-${PULP_PASSWORD:-}}"

: "${PULP_CLI_BASE_URL:?PULP_CLI_BASE_URL or PULP_URL is required}"
: "${PULP_CLI_USERNAME:?PULP_CLI_USERNAME or PULP_USERNAME is required}"
: "${PULP_CLI_PASSWORD:?PULP_CLI_PASSWORD or PULP_PASSWORD is required}"

export PULP_CLI_BASE_URL PULP_CLI_USERNAME PULP_CLI_PASSWORD

TARGET_TYPE="${TARGET_TYPE:-}"
TARGET_FAMILY="${TARGET_FAMILY:-}"
TARGET_VERSION="${TARGET_VERSION:-}"

: "${TARGET_TYPE:?TARGET_TYPE is required}"
: "${TARGET_FAMILY:?TARGET_FAMILY is required}"
: "${TARGET_VERSION:?TARGET_VERSION is required}"

REPOSITORY_NAME=""
BASE_PATH=""

log() {
  echo "[PULP] $*"
}

resolve_target() {
  case "${TARGET_TYPE}" in
    rpm)
      case "${TARGET_FAMILY}" in
        epel)
          case "${TARGET_VERSION}" in
            8|9|10) ;;
            *)
              log "Unsupported TARGET_VERSION for rpm/epel: ${TARGET_VERSION}"
              exit 1
              ;;
          esac
          ;;
        fedora)
          case "${TARGET_VERSION}" in
            43|44) ;;
            *)
              log "Unsupported TARGET_VERSION for rpm/fedora: ${TARGET_VERSION}"
              exit 1
              ;;
          esac
          ;;
        sles)
          log "TARGET_FAMILY=sles is defined but currently has no released TARGET_VERSION entries"
          exit 1
          ;;
        *)
          log "Unsupported TARGET_FAMILY for rpm: ${TARGET_FAMILY}"
          exit 1
          ;;
      esac
      REPOSITORY_NAME="rpm-${TARGET_FAMILY}-${TARGET_VERSION}"
      BASE_PATH="${TARGET_FAMILY}/${TARGET_VERSION}"
      ;;
    apt)
      case "${TARGET_FAMILY}" in
        debian)
          case "${TARGET_VERSION}" in
            bullseye|bookworm|trixie) ;;
            *)
              log "Unsupported TARGET_VERSION for apt/debian: ${TARGET_VERSION}"
              exit 1
              ;;
          esac
          REPOSITORY_NAME="debian-apt"
          BASE_PATH="debian"
          ;;
        ubuntu)
          case "${TARGET_VERSION}" in
            jammy|noble|resolute) ;;
            *)
              log "Unsupported TARGET_VERSION for apt/ubuntu: ${TARGET_VERSION}"
              exit 1
              ;;
          esac
          REPOSITORY_NAME="ubuntu-apt"
          BASE_PATH="ubuntu"
          ;;
        *)
          log "Unsupported TARGET_FAMILY for apt: ${TARGET_FAMILY}"
          exit 1
          ;;
      esac
      ;;
    *)
      log "Unsupported TARGET_TYPE: ${TARGET_TYPE}"
      exit 1
      ;;
  esac
}

ensure_rpm_repository() {
  local output
  if output=$(pulp rpm repository show --name "${REPOSITORY_NAME}" 2>&1); then
    log "RPM repository exists: ${REPOSITORY_NAME}"
  elif grep -qiE 'not found|does not exist|404' <<<"${output}"; then
    log "Creating RPM repository: ${REPOSITORY_NAME}"
    if ! output=$(pulp rpm repository create --name "${REPOSITORY_NAME}" 2>&1); then
      echo "${output}" >&2
      log "Failed to create RPM repository '${REPOSITORY_NAME}'. Check PULP_URL/PULP_USERNAME/PULP_PASSWORD and Pulp permissions."
      exit 1
    fi
  else
    echo "${output}" >&2
    log "Unable to verify RPM repository existence; aborting"
    exit 1
  fi
}

ensure_deb_repository() {
  local output
  if output=$(pulp deb repository show --name "${REPOSITORY_NAME}" 2>&1); then
    log "DEB repository exists: ${REPOSITORY_NAME}"
  elif grep -qiE 'not found|does not exist|404' <<<"${output}"; then
    log "Creating DEB repository: ${REPOSITORY_NAME}"
    if ! output=$(pulp deb repository create --name "${REPOSITORY_NAME}" 2>&1); then
      echo "${output}" >&2
      log "Failed to create DEB repository '${REPOSITORY_NAME}'. Check PULP_URL/PULP_USERNAME/PULP_PASSWORD and Pulp permissions."
      exit 1
    fi
  else
    echo "${output}" >&2
    log "Unable to verify DEB repository existence; aborting"
    exit 1
  fi
}

ensure_rpm_distribution() {
  local output
  if output=$(pulp rpm distribution show --name "${REPOSITORY_NAME}" 2>&1); then
    log "RPM distribution exists: ${REPOSITORY_NAME}"
  elif grep -qiE 'not found|does not exist|404' <<<"${output}"; then
    log "Creating RPM distribution: ${REPOSITORY_NAME} (base-path: ${BASE_PATH})"
    if ! output=$(pulp rpm distribution create --name "${REPOSITORY_NAME}" --repository "${REPOSITORY_NAME}" --base-path "${BASE_PATH}" 2>&1); then
      echo "${output}" >&2
      log "Failed to create RPM distribution '${REPOSITORY_NAME}'. Check PULP_URL/PULP_USERNAME/PULP_PASSWORD and Pulp permissions."
      exit 1
    fi
  else
    echo "${output}" >&2
    log "Unable to verify RPM distribution existence; aborting"
    exit 1
  fi
}

ensure_deb_distribution() {
  local output
  if output=$(pulp deb distribution show --name "${REPOSITORY_NAME}" 2>&1); then
    log "DEB distribution exists: ${REPOSITORY_NAME}"
  elif grep -qiE 'not found|does not exist|404' <<<"${output}"; then
    log "Creating DEB distribution: ${REPOSITORY_NAME} (base-path: ${BASE_PATH}, suite: ${TARGET_VERSION})"
    if ! output=$(pulp deb distribution create --name "${REPOSITORY_NAME}" --repository "${REPOSITORY_NAME}" --base-path "${BASE_PATH}" 2>&1); then
      echo "${output}" >&2
      log "Failed to create DEB distribution '${REPOSITORY_NAME}'. Check PULP_URL/PULP_USERNAME/PULP_PASSWORD and Pulp permissions."
      exit 1
    fi
  else
    echo "${output}" >&2
    log "Unable to verify DEB distribution existence; aborting"
    exit 1
  fi
}

resolve_target
log "Resolved target ${TARGET_TYPE}/${TARGET_FAMILY}/${TARGET_VERSION} -> repo=${REPOSITORY_NAME}, base-path=${BASE_PATH}"

if [[ "${TARGET_TYPE}" == "rpm" ]]; then
  ensure_rpm_repository
  ensure_rpm_distribution
else
  ensure_deb_repository
  ensure_deb_distribution
fi
