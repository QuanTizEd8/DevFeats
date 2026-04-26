FROM debian:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN printf '%s\n' \
      'keys:' \
      '  - url: https://nginx.org/keys/nginx_signing.key' \
      '    dest: /usr/share/keyrings/nginx-signing.key' \
      'repos:' \
      '  - content: "deb [arch=${deb_arch} signed-by=/usr/share/keyrings/nginx-signing.key] http://nginx.org/packages/debian ${version_codename} nginx"' \
      'packages:' \
      '  - nginx' \
      > /tmp/manifest.yaml
