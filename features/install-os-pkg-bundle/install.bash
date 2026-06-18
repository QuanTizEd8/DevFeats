# shellcheck shell=bash

__if_exists_dispatch__() {
  case "${IF_EXISTS:-skip}" in
    uninstall) __uninstall_run__ ;;
    reinstall)
      __uninstall_run__
      __install__
      ;;
    *) __install__ ;;
  esac
}

__uninstall_run__() {
  __dep_uninstall_option_bound__
}
