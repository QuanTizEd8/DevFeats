# Auto-resolve METHOD=auto to npm-bundled (supported) or npm (fallback).
# npm__install_bundled requires pre-built glibc Node.js binaries; Alpine and
# unsupported architectures fall back to method=npm.
__resolve_method() {
  case "$(os__kernel):$(os__arch)" in
    Linux:x86_64 | Linux:amd64 | Linux:aarch64 | Linux:arm64 | \
      Darwin:x86_64 | Darwin:amd64 | Darwin:arm64 | Darwin:aarch64)
      os__is_musl 2> /dev/null && {
        printf 'npm\n'
        return 0
      }
      printf 'npm-bundled\n'
      ;;
    *)
      printf 'npm\n'
      ;;
  esac
}

# Ensure npm is on PATH before the template's __install_run_npm__ auto-impl runs.
__install_run_npm_pre() {
  command -v npm > /dev/null 2>&1 && return 0
  ospkg__install_user nodejs npm || ospkg__install_user nodejs || {
    logging__error "install-devcontainer-cli: npm is required for method=npm."
    return 1
  }
  command -v npm > /dev/null 2>&1
}

# Install xz (Node.js tarball extraction) before npm-bundled install.
__install_run_npm_bundled_pre() {
  __dep_install__ build download
}
