FROM debian:13

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
        python3 \
        python3-pip \
        rsync \
        systemd \
        tar \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && touch /etc/pkging-ci-image

ENV DEBIAN_FRONTEND=
