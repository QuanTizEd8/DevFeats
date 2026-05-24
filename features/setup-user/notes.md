## Usage



### Conflict resolution

Before creating the user or group, the script compares the requested
UID/GID against existing accounts:

| Situation | `replace_existing=true` | `replace_existing=false` |
|---|---|---|
| UID/GID already correct | No-op — account reused as-is | Same |
| Username exists with wrong UID | Removes old account first | Error |
| UID in use by a different user | Removes that user first | Error |
| Group name exists with wrong GID | Removes old group first | Error |
| GID in use by a different group | Removes that group + its members | Error |

Home directories are **never** removed, regardless of `replace_existing`.

### Home directory

Created with `mkdir -p` and seeded from `/etc/skel`. If the directory
already exists, only ownership is corrected; existing contents are untouched.

### Sudo drop-in

A file is written to `<sudoers_dir>/<username>` with the content:

```
<username> ALL=(ALL) NOPASSWD:ALL
```

The file is created with mode `0440`. If `visudo` is available it is used to
validate the file before finalising; a validation failure removes the file
and aborts.
