# Contributing

## Docs

`README.ko.md` is a Korean translation of `README.md`. When you change one, update the other.

## Release

Bump `version` in `.claude-plugin/plugin.json` whenever a change reaches `main`. Installed copies are cached by version, so without a bump existing users don't get the change. Use semver: patch for fixes, minor for new features or settings.

## Tests

Run `bash tests/run.sh` before a change reaches `main`.
