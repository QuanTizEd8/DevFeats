# shellcheck shell=bash

__resolve_method() {
  logging__inspect "Resolving METHOD=auto."
  # Lefthook publishes prebuilt binaries for Linux and macOS (x86_64, arm64, i386).
  case "$(os__kernel)" in
    Linux | Darwin)
      logging__info "Resolved METHOD=auto → 'binary'."
      printf 'binary\n'
      ;;
    *)
      logging__info "Resolved METHOD=auto → 'package'."
      printf 'package\n'
      ;;
  esac
}

__install_run_npm_pre() {
  if command -v npm > /dev/null 2>&1; then
    logging__skip "npm already on PATH; skipping bootstrap install."
    return 0
  fi
  logging__install "Ensuring npm is available for lefthook npm method."
  bootstrap__npm
}
