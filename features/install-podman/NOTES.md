## Usage

### Basic

```jsonc
// .devcontainer/devcontainer.json
{
  "features": {
    "ghcr.io/quantized8/devfeats/install-podman:0": {}
  }
}
```

With the defaults above, Podman is configured for both `remoteUser` and
`containerUser` as set by the devcontainer tooling. Run containers as normal:

```sh
podman run --rm hello-world
podman run --rm -v "$(pwd):/work" --userns=keep-id -w /work some-image some-tool
```

### Also configure root

```jsonc
{
  "features": {
    "ghcr.io/quantized8/devfeats/install-podman:0": {
      "add_users": "root"
    }
  }
}
```

### Configure a specific additional user

```jsonc
{
  "features": {
    "ghcr.io/quantized8/devfeats/install-podman:0": {
      "add_users": "myuser"
    }
  }
}
```

---

## How it works

### Packages installed

| Package | Distro(s) | Purpose |
|---|---|---|
| `podman` | all | The container engine |
| `ca-certificates` | all | TLS certificates for pulling images from registries |
| `passt` | all | Default rootless networking backend on Podman 5+ (Fedora, etc.) |
| `slirp4netns` | all | Rootless networking backend; still the default on Debian/Ubuntu |
| `uidmap` | apt | Provides `newuidmap`/`newgidmap` setuid binaries (Debian/Ubuntu) |
| `shadow-utils` | dnf | Provides `newuidmap`/`newgidmap` (Fedora/RHEL) |
| `shadow-uidmap` | apk | Provides `newuidmap`/`newgidmap` (Alpine) |

### `privileged: true`

Rootless Podman requires the devcontainer itself to run with `--privileged`. The feature sets this automatically. It is needed to:

- Create user namespaces (`clone(CLONE_NEWUSER)`) — blocked by default seccomp in unprivileged containers
- Run setuid `newuidmap`/`newgidmap` — blocked by the `nosuid` mount flag on the container root
- Mount `procfs` in child namespaces — blocked by Docker's `/proc` masks
- Access `/dev/net/tun` for rootless networking

This is the same approach used by the official `docker-in-docker` devcontainer feature.

### Named volume for storage

The feature mounts a named volume at `/var/lib/containers/storage`:

```jsonc
{
  "source": "podman-storage-devcontainer-${devcontainerId}",
  "target": "/var/lib/containers/storage",
  "type": "volume"
}
```

The volume is backed by the host's real filesystem (ext4, xfs, btrfs, etc.),
not the container's overlayfs root. This avoids the **overlay-on-overlay**
problem: the Linux kernel rejects `exec` calls from filesystems that are
themselves overlayfs-backed, which is what you would get if Podman stored
images in the container's writable layer.

### subuid / subgid ranges

Each configured user gets a non-overlapping 65,536-entry range registered in
`/etc/subuid` and `/etc/subgid`. These tell the kernel which host UIDs/GIDs
the user is allowed to map inside a user namespace. Without these entries
`podman run` fails immediately with a user namespace error.

### Per-user `storage.conf`

A `~/.config/containers/storage.conf` is written for each configured user,
pointing `graphRoot` at a **per-user subdirectory** of the named volume:
`/var/lib/containers/storage/users/<username>`.  This is necessary because
rootless Podman ignores the system-level storage default and reads only the
per-user config file.  Giving each user their own subdirectory prevents
ownership conflicts: if a shared graphRoot were used, root Podman would create
`libpod/` as `root:root 0700`, blocking non-root users from accessing their
state on the next container start.

### System-level `containers.conf`

A `/etc/containers/containers.conf` is written with:

```toml
[engine]
cgroup_manager = "cgroupfs"
events_logger = "file"
```

These settings are primarily needed when running Podman as **root**. Rootless
Podman already defaults to `cgroupfs` and `file`, but root Podman defaults to
`systemd` and `journald` — neither of which is available inside a Docker
container.

### Entrypoint: `mount --make-rshared /` and cgroup v2 nesting

The feature installs an entrypoint script at
`/usr/local/share/devfeats/install-podman/entrypoint.sh` that runs two operations at
container startup.

**`mount --make-rshared /`**: Docker sets the container root mount to `private`
propagation by default, which blocks bind-mount propagation into rootless
Podman's user namespace and produces the warning `"\"/ \" is not a shared mount"`.
On Linux Docker hosts this fix works correctly.  On **macOS Docker Desktop**,
the call fails with `Unknown error 5005` — a VM-level restriction that cannot
be worked around from inside the container.  Podman's `"\"/ \" is not a shared
mount"` warning will therefore persist on macOS; basic container usage is
unaffected.

**cgroup v2 nesting setup**: On cgroup v2, the kernel's "no internal process"
rule prevents a cgroup that contains processes from enabling controllers for
its children. Docker places container processes directly in the root cgroup
(`/sys/fs/cgroup/`), so root Podman's attempt to write to
`cgroup.subtree_control` in order to enable the `pids`, `memory`, and other
controllers fails with EBUSY. The fix (mirroring the official Moby
[docker-in-docker entrypoint](https://github.com/moby/moby/blob/master/hack/dind))
is to move all processes into `/sys/fs/cgroup/init/`, making the root cgroup
process-free, and then enable all available controllers via
`cgroup.subtree_control`. Root Podman can then create and fully manage its
`/sys/fs/cgroup/libpod_parent/` hierarchy. The guard
`[ -f /sys/fs/cgroup/cgroup.controllers ]` makes this a no-op on cgroup v1.

**macOS Docker Desktop note**: On macOS, `mkdir /sys/fs/cgroup/init` is also
denied (even with `privileged: true`) because Docker Desktop's VM does not
allow cgroupfs writes from inside containers.  Both operations are therefore
best-effort and emit a `WARN` when they fail, without preventing startup.

### `containerUser` must be root

The feature entrypoint performs privileged operations (`mount --make-rshared`,
cgroup namespace setup) that require `CAP_SYS_ADMIN`.  The devcontainer CLI
runs feature entrypoints as `containerUser` — the user that the container
process runs as.  If `containerUser` is set to a non-root user, both operations
will fail with permission denied.

**Recommendation**: do not set `containerUser` to a non-root user for this
feature.  Use `remoteUser` instead — it controls only what user the VS Code
server and lifecycle commands (`postCreateCommand`, etc.) run as, without
changing the container's OS user.  Root is the default and works correctly.

---

## Troubleshooting

### `cannot clone: Invalid argument` or `operation not permitted`

User namespaces are being blocked. Ensure `"privileged": true` is set in your
`devcontainer.json` (this feature sets it automatically). On hardened
Debian/Ubuntu hosts the host sysctl
`kernel.unprivileged_userns_clone` may also need to be `1`.

### `WARN: failed to set '/' mount propagation to rshared` (macOS only)

This is expected on macOS Docker Desktop. The Docker Desktop VM does not allow
`mount --make-rshared /` from inside containers even with `privileged: true`.
Podman's `"\"/ \" is not a shared mount"` warning will also persist.
Basic container usage (`podman run`, `podman pull`) is unaffected.

### `WARN: could not create /sys/fs/cgroup/init` (macOS or non-root)

On macOS Docker Desktop, cgroupfs writes are blocked at the VM level even for
root containers.  When `containerUser` is non-root, `CAP_SYS_ADMIN` is absent.
In both cases Podman falls back to cgroupfs management without full controller
delegation; `podman run` still works for typical usage.

### `OCI runtime error: the requested cgroup controller 'pids' is not available`

Occurs when running Podman as **root** on a cgroup v2 host. Root Podman
attempts to enable the `pids` controller in its cgroup hierarchy, but the
root cgroup (where Docker places container processes) blocks `subtree_control`
writes while it contains processes. The feature's entrypoint performs cgroup
nesting setup at container start to resolve this: it moves all processes to
`/sys/fs/cgroup/init/` and enables all available controllers. If the entrypoint
has not run yet (e.g., the container was started outside a devcontainer
lifecycle), run it manually: `/usr/local/share/devfeats/install-podman/entrypoint.sh`.

### `newuidmap: write to uid_map failed: Operation not permitted`

Either `newuidmap` lacks the setuid bit, or the user has no `/etc/subuid`
entry. The feature sets both at install time. To inspect:

```sh
grep "$USER" /etc/subuid /etc/subgid
ls -la $(which newuidmap)   # should show -rwsr-xr-x
```

### `slirp4netns: failed to execute` / no network inside containers

Both `slirp4netns` and `passt` are installed. If Podman cannot find whichever
it expects, the active default can be overridden in
`~/.config/containers/containers.conf`:

```toml
[network]
default_rootless_network_cmd = "slirp4netns"
```

### `short-name "..." did not resolve to an alias`

Podman does not allow pulling by short name without a configured search registry.
Use fully-qualified image names:

```sh
podman run --rm docker.io/library/hello-world
```

Or add `docker.io` to `/etc/containers/registries.conf`:

```toml
unqualified-search-registries = ["docker.io"]
```




## Design decisions

### `privileged: true` over targeted capabilities

The first question was whether to use `privileged: true` or a chosen set of
`capAdd` / `securityOpt` overrides (e.g. `CAP_SYS_ADMIN`,
`seccomp=unconfined`, `apparmor=unconfined`).

Rootless Podman inside a container needs to:

- Create user namespaces (`clone(CLONE_NEWUSER)`) — blocked by the default
  seccomp profile
- Run setuid `newuidmap`/`newgidmap` — blocked by `nosuid` on the container
  root mount
- Mount `procfs` in child namespaces — blocked by Docker's `/proc` masks
- Access `/dev/net/tun` for networking

The combination of requirements adds up to near-privileged access anyway.
Using targeted overrides offers no meaningful security improvement in practice
(since anyone running rootless Podman inside a devcontainer already trusts that
container), while adding maintenance surface and fragility across container runtimes.
The official [`docker-in-docker`](https://github.com/devcontainers/features/blob/3df3aed1e7bfcdd91e97fa2d5d7cbefff1dde4cf/src/docker-in-docker/devcontainer-feature.json#L66)
feature uses the same `privileged: true` approach for the same reasons.

### Named volume for storage

The first working approach used the container's writable layer
for Podman's image store.
This hit the **overlay-on-overlay** problem:
the Linux kernel rejects `exec` calls on filesystems
that are themselves overlayfs-backed,
which is exactly what the container's writable layer is.
The exec failure produces an opaque `Invalid argument` error
with no indication of the root cause.

The solution is to give Podman a named Docker volume mounted at a fixed path.
A named volume is backed by the host's actual filesystem (ext4, xfs, btrfs, etc.),
not overlayfs, so the native kernel overlay driver works correctly on top of it.
`fuse-overlayfs` was also considered as an alternative
but does not work in this environment (see [below](#fuse-overlayfs-does-not-work-in-this-environment)).

The volume name includes `${devcontainerId}`
so each devcontainer gets its own isolated image store.

### `graphRoot` in per-user `storage.conf`, not system config

Rootless Podman ignores the system-level `/etc/containers/storage.conf`
for `graphRoot` — it only reads the per-user `~/.config/containers/storage.conf`.
Only the per-user file is therefore written, inside the loop over resolved users.
Each user's `graphRoot` points to their own subdirectory on the named volume
(`/var/lib/containers/storage/users/<username>`) so their Podman state is
fully isolated from other users.  Root is treated identically: if configured,
root gets `/root/.config/containers/storage.conf` pointing at
`/var/lib/containers/storage/users/root`.

### The entrypoint: `mount --make-rshared /` and cgroup v2 nesting

After the named volume fix, bind mounts like `-v $(pwd):/data` started
producing a warning: `"\"/ \" is not a shared mount"`.
This is because Docker sets the container's root mount point to `private` propagation.
Rootless Podman creates a user namespace and tries to bind-mount host paths into it,
which requires the root mount to have `shared` (or `rshared`) propagation
so kernel mount events propagate across the namespace boundary.

Root Podman also failed with:

```
Error: OCI runtime error: crun: the requested cgroup controller `pids` is not available
```

On cgroup v2, the kernel's "no internal process" rule blocks writing to
`cgroup.subtree_control` in any cgroup that currently contains processes.
Docker places container processes directly in the root cgroup
(`/sys/fs/cgroup/`), so root Podman cannot enable the `pids` controller
(or any other) in its `libpod_parent/` hierarchy — the write fails with EBUSY.

The established fix for both issues is the entrypoint pattern from the Moby
[docker-in-docker script](https://github.com/moby/moby/blob/master/hack/dind),
which the `devcontainers/features` `docker-in-docker` feature also uses:

```sh
# cgroup v2: enable controller delegation
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
    mkdir -p /sys/fs/cgroup/init
    xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs || true
    sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers \
        > /sys/fs/cgroup/cgroup.subtree_control || true
fi
```

This moves all processes out of the root cgroup into `/sys/fs/cgroup/init/`,
making the root cgroup process-free. All available controllers can then be
enabled. Root Podman can create and fully manage its `libpod_parent/`
hierarchy including pids, memory, and cpu controllers.

Both operations (`mount --make-rshared /` and cgroup nesting) are runtime
operations that cannot be done at image build time — they require a running,
privileged container. The entrypoint is generated during `install.sh` and
installed at `/usr/local/share/devfeats/install-podman/entrypoint.sh` (not in `$PATH`,
since it is not a user-facing tool).
The `devcontainer-feature.json`'s `entrypoint` field points to it.

### `containers.conf`: cgroupfs and file event logger

When testing with root Podman, it failed immediately:

```
WARN[0000] Failed to add conmon to cgroupfs sandbox cgroup: creating cgroup path
/libpod_parent/conmon: write /sys/fs/cgroup/cgroup.subtree_control: device or resource busy
```

Root Podman defaults to the `systemd` cgroup manager and `journald` event logger.
Neither is available inside a Docker container (no systemd daemon is running).
Rootless Podman already defaults to `cgroupfs` and `file`, so only root was affected.

The fix is a system-level `/etc/containers/containers.conf` with:

```toml
[engine]
cgroup_manager = "cgroupfs"
events_logger = "file"
```

This is written unconditionally (not only when root config is requested),
since it is harmless for rootless users and ensures correct behaviour whenever
root runs Podman in this container. The cgroup v2 controller delegation
problem (pids, memory, cpu controllers not being available) is addressed
by the entrypoint — see above.

### Removing `userns = "keep-id"`

An early version of the feature set `userns = "keep-id"` in `containers.conf`.
This maps the host user's UID to the same UID inside every container, which
is useful for bind-mount permission consistency when the host user is
non-root.

It was removed because:

1. It is too opinionated as a global default. Most container images expect to
   run as root inside the container (i.e. UID 0). With `keep-id`, those images
   run as the host UID instead, which can break image-internal file permissions
   and package managers.
2. It is trivially opt-in per invocation: `podman run --userns=keep-id ...`.
3. The standard rootless Podman behaviour (host UID maps to container root) is
   what users familiar with Docker or Podman will expect.

### Networking: both `passt` and `slirp4netns`

The Podman 5.x release notes and Fedora packaging mark `slirp4netns` as
deprecated in favour of `passt`. The `passt` package was added to
`base.yaml` accordingly. However, the Debian/Ubuntu `podman` package still
configures `slirp4netns` as the default rootless network backend — removing
it caused a runtime error:

```
Error: could not find slirp4netns, the network namespace can't be configured:
exec: "slirp4netns": executable file not found in $PATH
```

Both packages are now installed. The active backend is whatever the distro's
`containers.conf` default selects.

### Package names for UID mapping tools

The package providing `newuidmap` and `newgidmap` has different names across
distributions:

| Distro family | Package name |
|---|---|
| Debian/Ubuntu (apt) | `uidmap` |
| Fedora/RHEL (dnf) | `shadow-utils` |
| Alpine (apk) | `shadow-uidmap` |

The `install-os-pkg` manifest uses PM-specific blocks (`apt:`, `dnf:`,
`apk:`) to handle this without shell conditionals in `install.sh`.

### Multi-user configuration model

The feature can configure Podman for multiple users (subuid/subgid + per-user
`storage.conf`). User sources:

| Option | Resolved to |
|---|---|
| `add_root_user_config` | literal `root` |
| `add_current_user` | `$SUDO_USER` if set and non-root, else `$(whoami)`, skipped if root |
| `add_remote_user` | `$_REMOTE_USER` if set (devcontainer tooling) |
| `add_container_user` | `$_CONTAINER_USER` if set (devcontainer tooling) |
| `add_users` | comma-separated explicit list |

Deduplication uses POSIX sh's `case` pattern matching against a
space-separated accumulator string — no `sort`, `uniq`, or arrays required.

`add_current_user` deliberately does not fall back to `_REMOTE_USER`.
Its purpose is standalone `sudo ./install.sh` invocations where `SUDO_USER`
identifies the invoking non-root user. In a devcontainer context (where the
script runs as root with no `SUDO_USER`), it is a no-op — `_REMOTE_USER` is
handled separately by `add_remote_user`.

### Subuid/subgid range allocation

Each user gets 65,536 UIDs/GIDs starting at an incrementing offset
(`SUBUID_OFFSET=100000`, `+65536` per user). The feature checks for an
existing entry before writing, so rebuilds are idempotent. Each user's
`graphRoot` is an isolated subdirectory (`/var/lib/containers/storage/users/<username>`)
owned by that user; their `libpod/` state and image layers are private.
The parent `users/` directory is `chmod 1777` (sticky + world-writable)
so each user can create their own subdirectory; Podman initialises it with
mode 0700 on first run.

---

## Problems that no longer apply

### `fuse-overlayfs` does not work in this environment

Early iterations attempted to use `fuse-overlayfs` as the storage driver to
avoid the overlay-on-overlay problem. It failed: `fuse-overlayfs` requires
`/dev/fuse` and exhibits `noexec` behaviour in deeply nested user namespaces,
causing container exec calls to fail. It is **not installed** and **not used**.

The correct solution is the named volume: by mounting a Docker volume at
`/var/lib/containers/storage`, the storage path is backed by the host's real
filesystem, not overlayfs, so the native kernel overlay driver works without
any FUSE involvement.

### `configure-storage.sh` / `postStartCommand`

An early design used a `postStartCommand` script (`configure-storage.sh`)
that ran at container startup, detected whether `/dev/fuse` was accessible,
and wrote the appropriate `~/.config/containers/storage.conf`:

- If `/dev/fuse` was available: `driver = "overlay"` with `fuse-overlayfs` as the `mount_program`
- If not: `driver = "vfs"` — always works, but copies full layer contents for every container (slow, high disk usage)

This was the only host-agnostic way to handle storage at the time, since a
feature cannot request `--device=/dev/fuse` and `/dev/fuse` availability varies
by host. Once the named volume design was adopted — giving Podman storage backed
by the host's real filesystem rather than overlayfs — neither fuse-overlayfs nor
vfs was needed anymore. The native kernel overlay driver works on the named
volume unconditionally. All configuration is now done at image build time in
`install.sh`, and the runtime detection script is gone.

---

## References

- [Podman rootless tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)
- [Podman shortcomings of rootless](https://github.com/containers/podman/blob/main/rootless.md)
- [Podman troubleshooting guide](https://github.com/containers/podman/blob/main/troubleshooting.md)
- [fuse-overlayfs](https://github.com/containers/fuse-overlayfs)
- [containers/storage.conf docs](https://github.com/containers/storage/blob/main/docs/containers-storage.conf.5.md)
- [devcontainers feature spec](https://containers.dev/implementors/features/)
