# Auto-resolve METHOD=auto to npm-bundled (supported) or npm (fallback).
# npm__install_bundled requires pre-built glibc Node.js binaries; Alpine and
# unsupported architectures fall back to method=npm.
__resolve_method() {
  logging__inspect "Resolving METHOD=auto for devcontainer-cli."
  case "$(os__kernel):$(os__arch)" in
    Linux:x86_64 | Linux:amd64 | Linux:aarch64 | Linux:arm64 | \
      Darwin:x86_64 | Darwin:amd64 | Darwin:arm64 | Darwin:aarch64)
      os__is_musl 2> /dev/null && {
        logging__info "Resolved METHOD=auto → 'npm' (musl libc)."
        printf 'npm\n'
        return 0
      }
      logging__info "Resolved METHOD=auto → 'npm-bundled'."
      printf 'npm-bundled\n'
      ;;
    *)
      logging__info "Resolved METHOD=auto → 'npm' (unsupported platform)."
      printf 'npm\n'
      ;;
  esac
}

# Ensure npm is on PATH before the template's __install_run_npm__ auto-impl runs.
__install_run_npm_pre() {
  if command -v npm > /dev/null 2>&1; then
    logging__skip "npm already on PATH; skipping bootstrap install."
    return 0
  fi
  logging__install "Ensuring npm is available for devcontainer-cli npm method."
  npm__ensure_npm
}

# Install xz (Node.js tarball extraction) before npm-bundled install.
__install_run_npm_bundled_pre() {
  logging__install "Installing xz build dependency for npm-bundled."
  __dep_install__ build download
}
