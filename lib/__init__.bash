# Bash Library

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/file.sh
. "$_LIB_DIR/file.sh"
# shellcheck source=lib/logging-api.sh
. "$_LIB_DIR/logging-api.sh"
# shellcheck source=lib/_posix.sh
. "$_LIB_DIR/_posix.sh"
# shellcheck source=lib/git.sh
. "$_LIB_DIR/git.sh"
# shellcheck source=lib/logging.sh
. "$_LIB_DIR/logging.sh"
# shellcheck source=lib/os.sh
. "$_LIB_DIR/os.sh"
# shellcheck source=lib/ver.sh
. "$_LIB_DIR/ver.sh"
# shellcheck source=lib/str.sh
. "$_LIB_DIR/str.sh"
# shellcheck source=lib/ctx.sh
. "$_LIB_DIR/ctx.sh"
# shellcheck source=lib/json.sh
. "$_LIB_DIR/json.sh"
# shellcheck source=lib/net.sh
. "$_LIB_DIR/net.sh"
# shellcheck source=lib/verify.sh
. "$_LIB_DIR/verify.sh"
# shellcheck source=lib/lock.sh
. "$_LIB_DIR/lock.sh"
# shellcheck source=lib/users.sh
. "$_LIB_DIR/users.sh"
# shellcheck source=lib/proc.sh
. "$_LIB_DIR/proc.sh"
# shellcheck source=lib/graph.sh
. "$_LIB_DIR/graph.sh"
# shellcheck source=lib/argparse.sh
. "$_LIB_DIR/argparse.sh"
# shellcheck source=lib/sys_req.sh
. "$_LIB_DIR/sys_req.sh"
# shellcheck source=lib/shell.sh
. "$_LIB_DIR/shell.sh"
# shellcheck source=lib/install.sh
. "$_LIB_DIR/install.sh"
# shellcheck source=lib/bootstrap.sh
. "$_LIB_DIR/bootstrap.sh"
# shellcheck source=lib/ospkg.sh
. "$_LIB_DIR/ospkg.sh"
# shellcheck source=lib/github.sh
. "$_LIB_DIR/github.sh"
# shellcheck source=lib/npm.sh
. "$_LIB_DIR/npm.sh"
# shellcheck source=lib/oci.sh
. "$_LIB_DIR/oci.sh"
# shellcheck source=lib/uri.sh
. "$_LIB_DIR/uri.sh"

unset _LIB_DIR
