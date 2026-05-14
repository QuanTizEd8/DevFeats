#!/bin/bash
# version=24.7.1 + if_exists=reinstall, with conda 24.7.1 pre-installed:
# The version-match check (installed == resolved) fires before if_exists dispatch,
# so reinstall is never triggered.  Post-install steps (PATH export) still run.
set -e

source dev-container-features-test-lib

# --- conda was not reinstalled or removed ---
check "conda directory still exists" test -d /opt/conda
check "conda binary still present" test -f /opt/conda/bin/conda
check "conda binary is executable" test -x /opt/conda/bin/conda
check "mamba binary still present" test -f /opt/conda/bin/mamba
check "mamba binary is executable" test -x /opt/conda/bin/mamba

# --- version is unchanged (reinstall was skipped) ---
echo "=== conda --version ==="
/opt/conda/bin/conda --version 2>&1 || echo "(failed)"
check "conda --version succeeds" /opt/conda/bin/conda --version
check "conda version is still 24.7.1" bash -c '[ "$(/opt/conda/bin/conda --version 2>/dev/null | awk "{print \$NF}")" = "24.7.1" ]'
check "conda info --base returns /opt/conda" bash -c '[ "$(/opt/conda/bin/conda info --base 2>/dev/null)" = "/opt/conda" ]'

# --- post-install steps ran (PATH is reachable exports permanently disabled; PATH comes from containerEnv) ---
check "login PATH includes /opt/conda/bin" bash -lc 'echo "$PATH" | grep -q /opt/conda/bin'

reportResults
