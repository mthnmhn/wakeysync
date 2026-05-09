# Privacy Policy

Last updated: 2026-05-09

## TL;DR

WakeySync ships with anonymous, opt-in usage analytics powered by [Umami](https://umami.is/). On first launch the app asks once whether you want to enable it. The default if you dismiss the dialog is **off**. You can change the choice any time from the WakeySync menu.

If analytics are off, the app makes no network requests at all. WakeySync does not have an account system, never reaches out to any server for sync functionality itself, and stores all logs locally.

## What is sent when analytics are enabled

Each event POSTs a small JSON payload to a self-hosted Umami instance:

| Field | Example | Notes |
|---|---|---|
| `name` | `sync_succeeded` | Event name from a fixed allowlist (see below) |
| `app_version` | `0.2.0` | WakeySync version |
| `macos` | `14.4` | macOS major.minor only |
| `mac_model` | `MacBookPro18,3` | The model identifier from `sysctl hw.model` |
| `language` | `en_US` | OS locale |
| `hostname` | `wakeysync.app` | Static; lets Umami group events |

Umami additionally derives a daily-rotating anonymous visitor hash from the request IP and User-Agent. The raw IP is **not** stored. The hash cannot be reversed and rotates daily, so it cannot be used to track an individual across days.

### Event allowlist

Only these event names are ever sent. The full list lives in `App/Telemetry.swift` so you can audit it:

- `app_launched` — fired once per app launch
- `sync_succeeded` — Wakey acknowledged the time-sync packet
- `sync_failed_no_ack` — packet sent but no acknowledgement
- `sync_failed_timeout` — Wakey not found during scan
- `sync_failed_bt_off` — Bluetooth is off
- `sync_failed_unauthorized` — Bluetooth permission denied
- `sync_failed_other` — uncategorized error

## What is never sent

- Personal information of any kind
- Bluetooth MAC addresses
- The contents of any field you typed (e.g. a manually selected time)
- Raw IP addresses (Umami strips these at ingest)
- Apple ID, device serial number, or hardware UUID
- File paths or contents of `~/Library/Logs/WakeySync.log`

## Where the data lives

Events are sent to a self-hosted Umami instance. The server stores them in a Postgres database under the maintainer's control. There is no third-party analytics vendor involved.

A public read-only dashboard share link will be added here once the server is live:

> `https://analytics.wakeysync.dev/share/<id>/wakeysync` *(pending)*

## Local logs

WakeySync writes diagnostic logs to `~/Library/Logs/WakeySync.log`. These stay on your Mac. They are never read or transmitted by the app.

## How to opt out

- **At first launch:** click "No thanks" on the consent dialog.
- **Any time after:** open the **WakeySync** menu and click **Disable Anonymous Analytics**.

The choice is stored locally in `UserDefaults` under the key `WSAnalyticsEnabled`.

## How to audit

The entire telemetry implementation is in a single file: [`App/Telemetry.swift`](App/Telemetry.swift). It is roughly 150 lines and uses only Foundation + `URLSession`. No third-party dependencies. The event-firing call sites are all visible by grepping `Telemetry.track` in the codebase.

## Questions / data deletion requests

Please open an issue on the [GitHub repository](https://github.com/mthnmhn/wakeysync/issues). Because no personally identifying data is collected, we cannot identify or delete events tied to a specific user — but we can answer questions about the system and adjust collection.
