FROM ubuntu:latest
# Pre-install jq 1.8.1 so the version_match_idempotency scenario can verify
# that requesting the same version skips reinstall even when if_exists=fail.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
 && ARCH="$(uname -m)" \
 && case "${ARCH}" in \
      x86_64)  JQ_ARCH="amd64" ;; \
      aarch64) JQ_ARCH="arm64" ;; \
      *)        echo "Unsupported arch: ${ARCH}" && exit 1 ;; \
    esac \
 && curl --fail --location --retry 3 \
        "https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-linux-${JQ_ARCH}" \
        -o /usr/local/bin/jq \
 && chmod +x /usr/local/bin/jq
