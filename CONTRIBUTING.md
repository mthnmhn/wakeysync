# Contributing to WakeySync

Thanks for considering a contribution! This is a small project, so the bar for contributions is friendly.

## Reporting bugs

The most useful bug reports include:

- Your Mac model and macOS version
- Your Wakey firmware version (visible in the Soundcore iPhone app under device settings)
- What you clicked / ran
- What happened, and what you expected
- Relevant lines from `~/Library/Logs/WakeySync.log`

Please use the bug report issue template — it asks for these fields.

## Reporting it works on a new firmware

If you got WakeySync working on a Wakey firmware version not yet listed in the README compatibility table, please open an issue or PR adding it.

## Pull requests

1. Fork the repo and create a branch.
2. Run `swift build` and confirm it compiles.
3. If you're touching the BLE protocol, exercise the change against a real Wakey before submitting.
4. Keep the diff focused — small PRs land faster.
5. By submitting a PR you agree your contribution is licensed under the project's MIT license.

## Code style

Match what's already there. No formal linter; just keep things readable and consistent.

## Reverse-engineering contributions

The Wakey protocol is partially documented in [`docs/PROTOCOL.md`](docs/PROTOCOL.md). Captures, additional command IDs, and notes on other Soundcore devices that share the protocol are all welcome. Do not include copyrighted firmware, app binaries, or proprietary assets in PRs.
