FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        debhelper \
        devscripts \
        diffutils \
        fakeroot \
        git \
        gzip \
        locales \
        python3 \
        python3-pip \
        rsync \
        systemd \
        tar \
    && sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && touch /etc/pkging-ci-image

ENV DEBIAN_FRONTEND=
