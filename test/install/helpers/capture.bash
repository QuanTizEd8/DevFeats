# shellcheck shell=bash
# Mirror production __feat_capture_version_input__ for framework unit tests.

install_test__capture_version_input() {
  if [[ -v VERSION ]]; then
    # shellcheck disable=SC2034  # read by test bodies
    declare -g VERSION_INPUT="${VERSION}"
  else
    unset VERSION_INPUT 2> /dev/null || true
  fi
}
