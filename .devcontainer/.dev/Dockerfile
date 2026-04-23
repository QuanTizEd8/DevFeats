FROM mcr.microsoft.com/devcontainers/javascript-node:1-20-bookworm

# Install Python and Python packages (not present in the javascript-node base image).
RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 python3-yaml python3-jsonschema \
  && apt-get clean \
  && { apt-get dist-clean 2>/dev/null || rm -rf /var/lib/apt/lists/*; }

# Copy only the files needed to install dev tools.
COPY setup.sh requirements.txt /tmp/devcontainer/

# Install all dev tools (shfmt, shellcheck, just).
# pyyaml and jsonschema are installed via apt above.
# devcontainers-cli and lefthook are npm-global and handled separately below.
RUN bash /tmp/devcontainer/setup.sh --tools shfmt,shellcheck,just \
  && rm -rf /tmp/devcontainer

# Install npm-global tools.
RUN npm install -g @devcontainers/cli lefthook

# When used as a GHA job container, the workspace is owned by a different UID
# (the runner). Git refuses to operate on it unless safe.directory is set.
# Setting it system-wide here avoids having to add a workaround step to every
# container job in every workflow.
RUN git config --system --add safe.directory '*'
