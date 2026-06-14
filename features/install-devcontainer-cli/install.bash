# Ensure npm is on PATH before the template's __install_run_npm__ auto-impl runs.
__install_run_npm_pre() {
  if command -v npm > /dev/null 2>&1; then
    logging__skip "npm already on PATH; skipping bootstrap install."
    return 0
  fi
  logging__install "Ensuring npm is available for devcontainer-cli npm method."
  bootstrap__npm
}
