# Features


## Sync

After creating or editing `install.bash`, run:

```bash
python3 scripts/sync-src.py
```

This assembles `src/<feature-id>/install.bash` (header + body), generates
`install.sh` (bootstrap) and `_lib/` for your new feature.
The entire `src/` directory is git-ignored — never commit anything there.

[Lefthook](https://github.com/evilmartians/lefthook) can run sync on commit if you enable the corresponding commands in `lefthook.yml` (they are **commented out** in the repo default).

Verify the sync is up to date before pushing:

```bash
python3 scripts/sync-src.py --check
```
