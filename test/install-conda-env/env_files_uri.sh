#!/bin/bash
# env_files=file:///tmp/test-envs/simple.yml — same as env_files.sh but exercises
# the file:// URI resolver.
set -e

source dev-container-features-test-lib

check "YAML file exists" test -f /tmp/test-envs/simple.yml
check "simple environment is listed" bash -c '/opt/conda/bin/conda env list | grep -q simple'
check "simple environment directory exists" test -d /opt/conda/envs/simple
check "python binary exists in simple" test -f /opt/conda/envs/simple/bin/python
check "numpy importable in simple" /opt/conda/envs/simple/bin/python -c 'import numpy'

reportResults
