FROM mcr.microsoft.com/devcontainers/javascript-node:1-20-bookworm

# Copy only the files needed to install dev tools.
COPY setup-dev.sh requirements.txt /tmp/devcontainer/

# Install all dev tools (shfmt, shellcheck, just, pyyaml, jsonschema).
# devcontainers-cli and lefthook are npm-global and handled separately below.
RUN bash /tmp/devcontainer/setup-dev.sh --tools shfmt,shellcheck,just,pyyaml,jsonschema \
  && rm -rf /tmp/devcontainer

# Install npm-global tools.
RUN npm install -g @devcontainers/cli lefthook
