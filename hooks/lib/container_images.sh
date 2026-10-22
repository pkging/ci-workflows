#!/usr/bin/env bash
set -euo pipefail

get_container_image() {
  local distro="$1"

  case "$distro" in
    el8)      echo "ghcr.io/pkging/build-images/almalinux:8" ;;
    el9)      echo "ghcr.io/pkging/build-images/almalinux:9" ;;
    el10)     echo "ghcr.io/pkging/build-images/almalinux:10" ;;
    fedora43) echo "ghcr.io/pkging/build-images/fedora:43" ;;
    fedora44) echo "ghcr.io/pkging/build-images/fedora:44" ;;
    debian12) echo "ghcr.io/pkging/build-images/debian:12" ;;
    debian13) echo "ghcr.io/pkging/build-images/debian:13" ;;
    ubuntu22) echo "ghcr.io/pkging/build-images/ubuntu:22.04" ;;
    ubuntu24) echo "ghcr.io/pkging/build-images/ubuntu:24.04" ;;
    ubuntu26) echo "ghcr.io/pkging/build-images/ubuntu:26.04" ;;
    *)
      echo "Unsupported distro key for container image mapping: $distro" >&2
      return 1
      ;;
  esac
}
