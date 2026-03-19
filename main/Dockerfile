FROM ubuntu:24.04

ARG AWSCLI_ARCH=amd64
ARG DOCKER_GID=998
ARG HOST_UID=1000
ARG HOST_GID=1000
ARG HOST_USER=ubuntu

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/local/bin:${PATH}"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      docker.io \
      git \
      jq \
      less \
      ripgrep \
      shellcheck \
      sudo \
      unzip && \
    rm -rf /var/lib/apt/lists/*

RUN case "${AWSCLI_ARCH}" in \
      amd64) aws_pkg_arch="x86_64" ;; \
      arm64) aws_pkg_arch="aarch64" ;; \
      *) aws_pkg_arch="x86_64" ;; \
    esac && \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_pkg_arch}.zip" -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/aws /tmp/awscliv2.zip

RUN set -eux; \
    if getent group "${DOCKER_GID}" >/dev/null; then \
      docker_group="$(getent group "${DOCKER_GID}" | cut -d: -f1)"; \
    else \
      docker_group="dockerhost"; \
      groupadd -g "${DOCKER_GID}" "${docker_group}"; \
    fi; \
    if getent group "${HOST_GID}" >/dev/null; then \
      host_group="$(getent group "${HOST_GID}" | cut -d: -f1)"; \
    else \
      host_group="${HOST_USER}"; \
      groupadd -g "${HOST_GID}" "${host_group}"; \
    fi; \
    if getent passwd "${HOST_UID}" >/dev/null; then \
      existing_user="$(getent passwd "${HOST_UID}" | cut -d: -f1)"; \
      if [ "${existing_user}" != "${HOST_USER}" ] && ! id -u "${HOST_USER}" >/dev/null 2>&1; then \
        usermod -l "${HOST_USER}" "${existing_user}"; \
        if [ -d "/home/${existing_user}" ]; then \
          usermod -d "/home/${HOST_USER}" -m "${HOST_USER}"; \
        fi; \
      fi; \
    elif ! id -u "${HOST_USER}" >/dev/null 2>&1; then \
      useradd -m -u "${HOST_UID}" -g "${HOST_GID}" -s /bin/bash "${HOST_USER}"; \
    fi; \
    usermod -u "${HOST_UID}" "${HOST_USER}" || true; \
    usermod -g "${HOST_GID}" "${HOST_USER}" || true; \
    usermod -aG "${docker_group}" "${HOST_USER}"; \
    usermod -aG sudo "${HOST_USER}"; \
    mkdir -p "/home/${HOST_USER}" && chown "${HOST_UID}:${HOST_GID}" "/home/${HOST_USER}"; \
    echo "${HOST_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${HOST_USER}"; \
    chmod 0440 "/etc/sudoers.d/${HOST_USER}"

WORKDIR /workspace
USER ${HOST_USER}
ENV HOME=/home/${HOST_USER}
CMD ["bash", "-lc", "tail -f /dev/null"]
