FROM fedora:44

RUN dnf install -y \
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
        dnf-plugins-core \
        python3 \
        python3-pip \
        diffutils \
        systemd \
    && dnf clean all \
    && touch /etc/pkging-ci-image