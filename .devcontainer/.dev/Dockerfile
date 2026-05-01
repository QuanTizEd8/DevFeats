FROM ubuntu:24.04

# Install Python and Python packages (not present in the javascript-node base image).
RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 python3-yaml python3-jsonschema \
  && apt-get clean \
  && { apt-get dist-clean 2>/dev/null || rm -rf /var/lib/apt/lists/*; }
