#!/usr/bin/env bash
set -euo pipefail

source /workspace/.ci-workflows/hooks/lib/distro.sh
source /workspace/.ci-workflows/hooks/lib/common.sh || true

log "Running global pre-build container setup for distro: $ID ($ID_LIKE)"

# ---------------------------------------------------------------------------
# Install build dependencies
# ---------------------------------------------------------------------------
if is_el || is_fedora; then
  log "Preparing rpmbuild environment..."
  if [[ -f /etc/pkging-ci-image ]]; then
    log "Preloaded CI image detected; skipping common build-tool installation."
  else
    dnf install -y --allowerasing \
      rpm-build \
      rpmdevtools \
      redhat-rpm-config \
      make \
      gcc \
      gcc-c++ \
      tar \
      gzip \
      bzip2 \
      patch \
      which \
      git \
      wget \
      dnf-plugins-core
    dnf clean all
  fi

  mkdir -p /workspace/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
elif is_debian_like; then
  log "Preparing debian build environment..."
  if [[ -f /etc/pkging-ci-image ]]; then
    log "Preloaded CI image detected; skipping common build-tool installation."
  else
    apt-get update -y
    apt-get install -y \
      build-essential \
      git \
      tar \
      gzip \
      devscripts \
      debhelper \
      fakeroot \
      curl \
      rsync \
      ca-certificates
  fi

  log "DEBUG: Searching for packaging debian directory..."
  find / -maxdepth 5 -type d -name debian 2>/dev/null | grep -v build-src

  IS_NATIVE_DEB=false
  if [[ -f /workspace/debian/source/format ]] && grep -Fq '3.0 (native)' /workspace/debian/source/format; then
    IS_NATIVE_DEB=true
    log "Detected native Debian source format (3.0 native); skipping uscan/orig tarball flow."
  fi

  rm -rf /workspace/upstream

  if [[ "$IS_NATIVE_DEB" == "true" ]]; then
    mkdir -p /workspace/upstream
    rsync -a \
      --exclude '.git/' \
      --exclude '.github/' \
      --exclude 'upstream/' \
      --exclude 'rpmbuild/' \
      /workspace/ /workspace/upstream/
  else
    HAS_WATCH=false
    IS_RUBYGEMS=false
    if [[ -f /workspace/debian/watch ]]; then
      HAS_WATCH=true
      if grep -q 'rubygems\.org/api/v1/versions' /workspace/debian/watch; then
        IS_RUBYGEMS=true
        log "Rubygems API watch detected; downloading the packaged gem version directly."
      fi
    fi

    PKG=$(dpkg-parsechangelog -S Source)
    VER_FULL=$(dpkg-parsechangelog -S Version)
    VER=${VER_FULL%-*}

    validate_upstream_archive() {
      if [[ ! -s "$ORIG" ]]; then
        echo "[ERROR] Upstream source archive is empty: $ORIG" >&2
        return 1
      fi

      log "Extracting upstream source..."
      if ! tar --extract --file "$ORIG" --directory ../build-src; then
        echo "[ERROR] Cannot extract upstream source archive: $ORIG" >&2
        return 1
      fi

      log "Detecting upstream directory..."
      UPSTREAM_DIRS=()
      if ! find ../build-src -mindepth 1 -maxdepth 1 -type d -print0 > ../build-src/.ci-directories; then
        echo "[ERROR] Cannot inspect extracted upstream directories: $ORIG" >&2
        return 1
      fi
      while IFS= read -r -d '' directory; do
        UPSTREAM_DIRS+=("$directory")
      done < ../build-src/.ci-directories
      rm -f ../build-src/.ci-directories
      if (( ${#UPSTREAM_DIRS[@]} != 1 )); then
        echo "[ERROR] Upstream archive must contain exactly one top-level source directory; found ${#UPSTREAM_DIRS[@]}: $ORIG" >&2
        return 1
      fi
      UPSTREAM_DIR="${UPSTREAM_DIRS[0]}"
      if ! SOURCE_FILE=$(find "$UPSTREAM_DIR" -type f ! -path "$UPSTREAM_DIR/debian/*" -print -quit); then
        echo "[ERROR] Cannot inspect upstream source files: $UPSTREAM_DIR" >&2
        return 1
      fi
      if [[ -z "$SOURCE_FILE" ]]; then
        echo "[ERROR] Upstream source directory contains no source files: $UPSTREAM_DIR" >&2
        return 1
      fi
    }

    SOURCE_VALID=false
    MAX_ATTEMPTS=1
    if [[ "$HAS_WATCH" == "true" && "$IS_RUBYGEMS" == "false" ]]; then
      MAX_ATTEMPTS=3
    fi
    for (( attempt=1; attempt<=MAX_ATTEMPTS; attempt++ )); do
      DOWNLOAD_OK=true
      if (( MAX_ATTEMPTS > 1 )); then
        log "Upstream source download attempt ${attempt}/${MAX_ATTEMPTS}"
        # Do not let a stale or partial archive satisfy a fresh download.
        for archive in ../"${PKG}_${VER}".orig.tar.*; do
          [[ ! -e "$archive" && ! -L "$archive" ]] || rm -f -- "$archive"
        done
        if ! uscan --download-current-version --force-download; then
          echo "[ERROR] Upstream source download via uscan failed." >&2
          DOWNLOAD_OK=false
        fi
      fi

      ORIG="../${PKG}_${VER}.orig.tar.xz"
      for archive in ../"${PKG}_${VER}".orig.tar.*; do
        if [[ -f "$archive" ]]; then
          ORIG="$archive"
          break
        fi
      done

      rm -rf ../build-src
      mkdir ../build-src
      if [[ "$DOWNLOAD_OK" == "true" ]]; then
        if [[ -f "$ORIG" ]]; then
          if validate_upstream_archive; then
            SOURCE_VALID=true
            break
          fi
        elif (( MAX_ATTEMPTS > 1 )); then
          echo "[ERROR] uscan produced no upstream archive for ${PKG} ${VER}." >&2
        else
          break
        fi
      fi

      for archive in ../"${PKG}_${VER}".orig.tar.*; do
        [[ ! -e "$archive" && ! -L "$archive" ]] || rm -f -- "$archive"
      done
      if [[ "$IS_RUBYGEMS" == "true" ]]; then
        log "Discarding invalid cached upstream archive; downloading Rubygems source anew."
        break
      fi
      if (( attempt == MAX_ATTEMPTS )); then
        echo "[ERROR] Upstream sources unavailable or invalid after ${attempt} attempt(s); refusing fallback sources." >&2
        exit 1
      fi
      log "Retrying upstream source download in 10 seconds..."
      sleep 10
    done

    if [[ "$SOURCE_VALID" == "true" ]]; then
      log "Copying orig tarball into /workspace..."
      cp "$ORIG" /workspace/
      log "Upstream directory is: $UPSTREAM_DIR"

      log "Removing upstream debian/ directory..."
      rm -rf "$UPSTREAM_DIR/debian"

      log "Copying upstream code into /workspace..."
      mkdir -p /workspace/upstream
      rsync -a "$UPSTREAM_DIR"/ /workspace/upstream/

      log "Copying packaging debian/ into upstream/"
      cp -a /workspace/debian /workspace/upstream/
    else
      if [[ "$IS_RUBYGEMS" == "true" ]]; then
        GEM_NAME="$(sed -n 's#.*/versions/\([^/]*\)/latest\.json.*#\1#p' /workspace/debian/watch | head -n1)"
        if [[ -z "$GEM_NAME" ]]; then
          echo "[ERROR] Cannot determine gem name from debian/watch; refusing a fallback gem name." >&2
          exit 1
        fi
        GEM_FILE="${GEM_NAME}-${VER}.gem"
        GEM_URL="https://rubygems.org/downloads/${GEM_FILE}"
        ORIG_TOPDIR="${PKG}-${VER}"
        ORIG_STAGE="../build-src/${ORIG_TOPDIR}"

        for (( attempt=1; attempt<=3; attempt++ )); do
          log "Downloading Rubygems source: ${GEM_FILE} (attempt ${attempt}/3)"
          rm -f -- "/workspace/${GEM_FILE}"
          if ! curl -fL --connect-timeout 30 --max-time 300 \
            -o "/workspace/${GEM_FILE}" "${GEM_URL}"; then
            echo "[ERROR] Rubygems source download failed: ${GEM_FILE}" >&2
          elif [[ ! -s "/workspace/${GEM_FILE}" ]]; then
            echo "[ERROR] Downloaded Rubygems source is empty: ${GEM_FILE}" >&2
          else
            break
          fi
          rm -f -- "/workspace/${GEM_FILE}"
          if (( attempt == 3 )); then
            echo "[ERROR] Rubygems sources unavailable after 3 attempts; refusing fallback sources." >&2
            exit 1
          fi
          log "Retrying Rubygems source download in 10 seconds..."
          sleep 10
        done

        mkdir -p /workspace/upstream
        rsync -a \
          --exclude '.git/' \
          --exclude '.github/' \
          --exclude 'upstream/' \
          --exclude 'rpmbuild/' \
          /workspace/ /workspace/upstream/

        log "Creating synthetic orig tarball for source build..."
        rm -rf ../build-src
        mkdir -p "$ORIG_STAGE"
        rsync -a /workspace/upstream/ "$ORIG_STAGE"/
        rm -rf "$ORIG_STAGE/debian"

        tar --create --xz --file "$ORIG" --directory ../build-src "$ORIG_TOPDIR"
        cp "$ORIG" /workspace/
      else
        if [[ "$HAS_WATCH" == "true" ]]; then
          echo "[ERROR] uscan produced no upstream archive for ${PKG} ${VER}; refusing to build from fallback sources." >&2
          exit 1
        fi
        ORIG_TOPDIR="${PKG}-${VER}"
        ORIG_STAGE="../build-src/${ORIG_TOPDIR}"

        log "No watch-based upstream archive available; creating synthetic orig tarball from workspace sources."
        rm -rf ../build-src
        mkdir -p "$ORIG_STAGE"

        rsync -a \
          --exclude '.git/' \
          --exclude '.github/' \
          --exclude 'upstream/' \
          --exclude 'rpmbuild/' \
          --exclude 'debian/' \
          /workspace/ "$ORIG_STAGE"/

        tar --create --xz --file "$ORIG" --directory ../build-src "$ORIG_TOPDIR"
        cp "$ORIG" /workspace/

        mkdir -p /workspace/upstream
        rsync -a "$ORIG_STAGE"/ /workspace/upstream/
        cp -a /workspace/debian /workspace/upstream/
      fi
    fi
  fi

  log "Applying distro-specific Debian version suffix..."
  cd /workspace/upstream
  CURRENT_VERSION="$(dpkg-parsechangelog -S Version)"
  DIST_SUFFIX="${ID}${VERSION_ID//[^0-9A-Za-z]/}"
  TARGET_BASE_VERSION="$CURRENT_VERSION"

  if [[ "$IS_NATIVE_DEB" == "true" ]]; then
    TARGET_BASE_VERSION="${CURRENT_VERSION%%-*}"
    if [[ "$TARGET_BASE_VERSION" != "$CURRENT_VERSION" ]]; then
      log "Native Debian package detected with revision in version ($CURRENT_VERSION); normalizing to $TARGET_BASE_VERSION"
    fi
  fi

  TARGET_VERSION="${TARGET_BASE_VERSION}+${DIST_SUFFIX}"

  if [[ "$CURRENT_VERSION" == "$TARGET_VERSION" ]]; then
    log "Debian package version already contains suffix: $CURRENT_VERSION"
  else
    MAINTAINER="$(dpkg-parsechangelog -S Maintainer)"
    export DEBFULLNAME="${MAINTAINER% <*}"
    export DEBEMAIL="${MAINTAINER##*<}"
    DEBEMAIL="${DEBEMAIL%>}"
    export DEBEMAIL

    dch --distribution stable --force-distribution --newversion "$TARGET_VERSION" \
      "CI rebuild for ${ID} ${VERSION_ID}." >/dev/null

    log "Debian package version set to: $(dpkg-parsechangelog -S Version)"
  fi
else
  echo "❌ Unsupported distro for RPM build: $ID"
  exit 1
fi

log "Global pre-build container completed successfully."
