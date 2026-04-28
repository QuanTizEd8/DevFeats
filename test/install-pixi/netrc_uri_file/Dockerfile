FROM ubuntu:latest
ARG GITHUB_TOKEN
ENV GITHUB_TOKEN=${GITHUB_TOKEN}
RUN printf '%s\n' 'machine github.com login token password placehold' > /tmp/test.netrc \
 && chmod 600 /tmp/test.netrc
