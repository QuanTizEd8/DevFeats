FROM ubuntu:latest
# Pre-install yq 4.44.2 so the version_match_idempotency scenario can verify
# that requesting the same version skips reinstall even when if_exists=reinstall.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && apt-get clean \
 && apt-get dist-clean 2>/dev/null || rm -rf /var/lib/apt/lists/* \
 && ARCH="$(uname -m)" \
 && case "${ARCH}" in \
      x86_64)  YQ_ARCH="amd64" ;; \
      aarch64) YQ_ARCH="arm64" ;; \
      *)        echo "Unsupported arch: ${ARCH}" && exit 1 ;; \
    esac \
 && curl --fail --location --retry 3 \
        "https://github.com/mikefarah/yq/releases/download/v4.44.2/yq_linux_${YQ_ARCH}" \
        -o /usr/local/bin/yq \
 && chmod +x /usr/local/bin/yq
