#!/usr/bin/env bash
set -euo pipefail

get_container_image() {
  local distro="$1"

  case "$distro" in
    el8)      echo "ghcr.io/pkging/build-images/almalinux:8-ci-v1" ;;
    el9)      echo "ghcr.io/pkging/build-images/almalinux:9-ci-v1" ;;
    el10)     echo "ghcr.io/pkging/build-images/almalinux:10-ci-v1" ;;
    fedora43) echo "ghcr.io/pkging/build-images/fedora:43-ci-v1" ;;
    fedora44) echo "ghcr.io/pkging/build-images/fedora:44-ci-v1" ;;
    debian12) echo "ghcr.io/pkging/build-images/debian:12-ci-v1" ;;
    debian13) echo "ghcr.io/pkging/build-images/debian:13-ci-v1" ;;
    ubuntu22) echo "ghcr.io/pkging/build-images/ubuntu:22.04-ci-v1" ;;
    ubuntu24) echo "ghcr.io/pkging/build-images/ubuntu:24.04-ci-v1" ;;
    ubuntu26) echo "ghcr.io/pkging/build-images/ubuntu:26.04-ci-v1" ;;
    *)
      echo "Unsupported distro key for container image mapping: $distro" >&2
      return 1
      ;;
  esac
}
