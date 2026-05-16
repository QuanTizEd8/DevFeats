- `remoteUser` is available in `install.sh` as `_REMOTE_USER`, but not available for substitution in `devcontainer-feature.json`, whereas `containerWorkspaceFolder` is not available in `install.sh`, but is available for substitution in `devcontainer-feature.json`.

- VS Code extension ignores `CLAUDE_CONFIG_DIR` environment variable: https://github.com/anthropics/claude-code/issues/30538


## References

- [Claude Code Docs – Advanced Setup](https://code.claude.com/docs/en/setup)
- [Cluade Code Docs – Claude Directory](https://code.claude.com/docs/en/claude-directory)
- [Cluade Code Docs – VS Code](https://code.claude.com/docs/en/vs-code)
- [Claude Code Docs – Dev Containers](https://code.claude.com/docs/en/devcontainer)
- [Official Claude Code Devcontainer Feature](https://github.com/anthropics/devcontainer-features/tree/main/src/claude-code)
- [Claude Dev Container Features](https://containers.dev/features?search=claude)

- [Claude-mem: Persistent Context Across Sessions for Every Agent](https://github.com/thedotmack/claude-mem)