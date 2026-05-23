# Install base build-dependencies.
if users__is_privileged || [[ "$(os__kernel)" == "Darwin" ]]; then
  _build_deps__install_base
else
  logging__info "Skipping base build-dependency install (no privilege available); ensure packages from dependencies/build/base.yaml are pre-installed."
fi
