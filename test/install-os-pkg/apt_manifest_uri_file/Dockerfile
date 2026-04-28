FROM debian:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN printf '%s\n' 'packages:' '  - tree' '  - curl' > /tmp/manifest.yaml
