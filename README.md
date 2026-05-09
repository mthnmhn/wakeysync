# WakeySync

**Sync your Mac's clock to a Soundcore Wakey alarm clock — the missing macOS companion app.**

The Soundcore Wakey (Anker A3300) auto-syncs its displayed time when you connect it to the iPhone Soundcore app. There is no equivalent on macOS, so the clock drifts and there is no built-in way to set it from a Mac. WakeySync is a small, free, open-source Mac app that does exactly that: one click and your Wakey shows the right time.

> Unofficial. Not affiliated with Anker or Soundcore. See [TRADEMARKS.md](TRADEMARKS.md).

## Features

- One-click "Sync current time" from a tiny native macOS window
- Set a specific time manually (Advanced)
- Works over Bluetooth LE — no pairing required, no extra software
- No account, no cloud, no telemetry by default
- Open source, MIT licensed

## Requirements

- macOS 13 (Ventura) or later
- Bluetooth enabled on your Mac
- A Soundcore Wakey (Anker model A3300) powered on and within Bluetooth range

## Install

### Option A — Download the prebuilt app (easiest)

1. Grab the latest `WakeySync.app.zip` from the [Releases page](https://github.com/mthnmhn/wakeysync/releases).
2. Unzip it and drag `WakeySync.app` into `/Applications`.
3. First launch: right-click the app and choose **Open** to bypass Gatekeeper (the app is not yet notarized).
4. Approve the Bluetooth permission prompt.

### Option B — Build from source

```bash
git clone https://github.com/mthnmhn/wakeysync.git
cd wakeysync
./scripts/run_app.sh
```

This builds the app into `WakeySync.app` and opens it.

## Use

1. Make sure the Wakey is powered on and near the Mac.
2. Open WakeySync and click **Sync current time**.
3. The app scans for the Wakey, sends the time-sync command, and reports success.

If macOS asks for Bluetooth access, click **Allow**. If access was denied earlier, enable it in `System Settings > Privacy & Security > Bluetooth`.

## How it works

The iPhone Soundcore app sends a Bluetooth LE command (`0x8101`) carrying the current local time to a specific GATT characteristic on the Wakey. WakeySync replays that same command from the Mac.

For the full reverse-engineering write-up and protocol details:

- [`docs/FINDINGS.md`](docs/FINDINGS.md) — research log
- [`docs/PROTOCOL.md`](docs/PROTOCOL.md) — packet format and BLE characteristics
- [`docs/PLAN.md`](docs/PLAN.md) — original plan and approach

## CLI (advanced)

The repo also ships a small CLI, `wakeyctl`, used during development for packet building and BLE diagnostics:

```bash
swift build
.build/debug/wakeyctl help
```

See `wakeyctl help` for the full command list.

## Privacy

WakeySync does not collect any data by default. See [PRIVACY.md](PRIVACY.md) for details. If opt-in usage analytics are added in a future release, they will be clearly disclosed and disabled by default until explicitly enabled.

## Contributing

Bug reports and pull requests are welcome — especially reports from different Wakey firmware versions. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
