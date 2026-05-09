# Protocol Notes

Use this file to capture verified Wakey command details as testing progresses.

## Device

- Name: Soundcore Wakey
- Classic Bluetooth address: `AC:B1:EE:25:DA:04`
- BLE advertisement address in the iPhone trace: `D3:B1:EE:25:DA:04`
- CoreBluetooth identifier on this Mac: `A0ABC34C-1C3F-CB56-E3A5-278DC2FE6117`
- BLE advertised service: `0109F5DA-0000-1000-8000-00805F9B34FB`
- BLE manufacturer data for target matching: `04 da 25 ee b1 ac`, which is the classic address in little-endian byte order
- BLE write characteristic: `7777`, value handle `0x000B` in the iPhone trace
- BLE notification characteristic: `8888`, value handle `0x0008` in the iPhone trace, CCCD handle `0x0009`
- RFCOMM channel: `2`

## Known Frame Structure

- Outbound header: `08 ee 00 00 00`
- Inbound header: `09 ff xx xx 01`
- Command: 2 bytes, little-endian
- Length: 2 bytes, little-endian total frame length: header + command + length + body
- Checksum: not present in the iPhone-to-Wakey frames captured in PacketLogger
- Transport: the iPhone app sends these frames over BLE ATT writes to characteristic `7777`, not over classic RFCOMM

## Verified Commands

| Command | Name | Body format | Result |
| --- | --- | --- | --- |
| `0x8101` | Time sync | `year_since_2000 month day hour minute second 00` | Captured from the iPhone Soundcore app over BLE; Mac BLE writes to `7777` now produce the expected app-level notification and the user confirmed the display changes |
| `0x0105` | Unknown | none | Captured outbound from the iPhone Soundcore app with an immediate inbound response |
| `0x0205` | Unknown | none | Captured outbound from the iPhone Soundcore app with an immediate inbound response |
| `0x0101` | Request state | none | Known from OpenSCQ30, not yet re-verified on Wakey from the iPhone trace |

## Candidate Time Formats

| Format | Bytes | Notes |
| --- | --- | --- |
| `year16` | `year_le month day hour minute second` | Most direct guess |
| `year16-weekday` | `year_le month day weekday hour minute second` | Common RTC layout |
| `year2000` | `year_since_2000 month day hour minute second` | Compact variant |
| `year2000 + 00` | `year_since_2000 month day hour minute second 00` | Captured from iPhone PacketLogger traffic; accepted by the Wakey over Mac BLE with a `0x8101` notification |
| `unix32` | `timestamp_le` | Easy probe format |

## Test Log

### 2026-04-07

- Command tried: `services`
- Response: macOS reports 10 SDP services. Service `[2]` is `Serial Port Service - Channel 2`, UUID `0cf12d31-fac3-4553-bd80-d6832e7b3300`, RFCOMM channel `2`. HandsFree uses RFCOMM channel `1`.
- Notes: This confirms our Mac sender is targeting the vendor serial service, not the HandsFree RFCOMM channel.

### 2026-04-07

- Source: iPhone PacketLogger capture [`iphone12.pklg`](captures/iphone12.pklg)
- Timing: the Wakey name first appears around `17:44:54.171`, while the Soundcore BLE ATT command burst starts at `17:45:13.190`
- Notes: this matches the observed UI delay: the app/device spend time connecting before the Soundcore control burst. Once the burst starts, the captured Soundcore frames are only about 0.44 seconds apart.

Captured burst:

| Time | Direction | Packet |
| --- | --- | --- |
| `17:45:13.190` | out | `08 ee 00 00 00 01 81 10 00 1a 04 07 11 2d 0d 00` |
| `17:45:13.268` | in | `09 ff 94 8e 01 01 81 09 00` |
| `17:45:13.403` | out | `08 ee 00 00 00 01 83 1a 00 01 e3 b9 92 66 f5 b9 92 66 9d b9 92 66 d7 06 94 66` |
| `17:45:13.450` | in | `09 ff 02 00 01 01 83 33 00 ...` |
| `17:45:13.508` | in | `09 ff 02 01 01 01 83 16 00 ...` |
| `17:45:13.530` | out | `08 ee 00 00 00 05 01 09 00` |
| `17:45:13.568` | in | `09 ff 00 00 01 05 01 23 00 ...` |
| `17:45:13.583` | out | `08 ee 00 00 00 05 02 09 00` |
| `17:45:13.629` | in | `09 ff 00 00 01 05 02 09 00` |

BLE details from this capture:

- The iPhone connects to `D3:B1:EE:25:DA:04`, not the classic `AC:B1:EE:25:DA:04` address.
- Primary service `0109F5DA-0000-1000-8000-00805F9B34FB` spans handles `0x0006...0x000B`.
- Characteristic `8888` has value handle `0x0008`; iPhone enables notifications by writing `01 00` to CCCD handle `0x0009`.
- Characteristic `7777` has value handle `0x000B`; iPhone sends the Soundcore packets as ATT Write Commands to this handle.

### 2026-04-07

- Source: Mac PacketLogger capture [`macos.pklg`](captures/macos.pklg)
- Result: capture worked and shows our earlier Mac replay on classic RFCOMM channel `2`.
- Key finding: the Mac sent the same `08 ee ...` app frames over RFCOMM to `AC:B1:EE:25:DA:04`, while the iPhone sent them over BLE ATT to `D3:B1:EE:25:DA:04`.
- Response: no app-level Wakey replies to the Mac RFCOMM writes; only RFCOMM control frames and HCI completed-packet events were observed.

Captured Mac RFCOMM replay:

| Time | Direction | Transport | Packet |
| --- | --- | --- | --- |
| `00:30:16.296` | out | RFCOMM ch2 | `08 ee 00 00 00 01 81 10 00 1a 04 07 0a 00 00 00` |
| `00:30:17.098` | out | RFCOMM ch2 | `08 ee 00 00 00 01 83 1a 00 01 e3 b9 92 66 f5 b9 92 66 9d b9 92 66 d7 06 94 66` |
| `00:30:17.899` | out | RFCOMM ch2 | `08 ee 00 00 00 05 01 09 00` |
| `00:30:18.700` | out | RFCOMM ch2 | `08 ee 00 00 00 05 02 09 00` |

### 2026-04-07

- Command tried: `sync-time-ble`
- Packet: `08 ee 00 00 00 01 81 10 00 1a 04 07 0a 00 00 00`
- Transport: BLE write to characteristic `7777` on service `0109F5DA-0000-1000-8000-00805F9B34FB`
- Response: no app-level `09 ff ...` notification observed from characteristic `8888`
- Notes: `--write-with-response` produces an ATT write response from characteristic `7777`, confirming the BLE write reaches the device at the ATT layer.

### 2026-04-07

- Command tried: `sync-time`
- Packet: `08 ee 00 00 00 01 81 10 00 1a 04 07 12 04 1a 00`
- Response: no inbound bytes observed within 4 seconds
- Display change: not visually confirmed from the terminal session
- Notes: RFCOMM channel opened successfully and `writeSync` returned success through the `WakeySync.app` launcher path. Body decodes to local time `2026-04-07 18:04:26`.

### 2026-04-07

- Command tried: `sync-time` to force `10:00:00`
- Packet: `08 ee 00 00 00 01 81 10 00 1a 04 07 0a 00 00 00`
- Response: no inbound bytes observed within 4 seconds
- Display change: user reported no change
- Notes: RFCOMM channel opened successfully and `writeSync` returned success. Added a `--pre-send-delay` option and retried captured `0x0105`; that also wrote successfully but produced no inbound bytes from this Mac session.

### 2026-04-07

- Command tried: framing variants for `10:00:00`
- Packets: `08 ee 00 00 00 01 81 10 00 1a 04 07 0a 00 00 b7` and `08 ee 00 00 00 01 81 0f 00 1a 04 07 0a 00 00`
- Response: no inbound bytes observed
- Display change: pending user confirmation
- Notes: These were diagnostic variants to test whether the trailing zero from the iPhone capture was checksum-like or body-like.

### 2026-04-07

- Command tried: one-channel replay of the captured iPhone burst, with the first packet changed to `10:00:00`
- Packet sequence: `0x8101`, `0x8301`, `0x0105`, `0x0205`
- Response: no inbound bytes observed
- Display change: user reported no change after earlier attempts; this replay still did not produce inbound bytes
- Notes: Retried with a 20-second post-open delay to mimic the observed app connection delay. RFCOMM opened and all writes returned success, but the Wakey still did not respond to the Mac session.

### 2026-04-07

- Source: iPhone PacketLogger capture [`iphone12.pklg`](captures/iphone12.pklg)
- Command captured: `0x8101` (`01 81` on the wire)
- Packet: `08 ee 00 00 00 01 81 10 00 1a 04 07 11 2d 0d 00`
- Body meaning: `2026-04-07 17:45:13 UTC`, encoded as `year_since_2000 month day hour minute second 00`
- Timezone note: PacketLogger displayed this event at `2026-04-07 23:15:13 +05:30`; the payload used the same instant in UTC fields.
- Response: immediate inbound frame with command bytes `01 81`
- Display change: likely yes, captured during the phone app sync window
- Notes: The following byte after the packet in the `.pklg` file is PacketLogger record data, not part of the Soundcore frame. The captured frame length is `0x0010`, so the Soundcore frame ends at the trailing `00`.

### 2026-04-07

- Source: Mac PacketLogger capture [`macos1.pklg`](captures/macos1.pklg)
- Result: Mac BLE now matches the iPhone ATT path: it connects to `D3:B1:EE:25:DA:04`, exchanges MTU `185/200`, enables notifications with a write request to CCCD handle `0x0009`, and writes to characteristic `7777` value handle `0x000B`.
- Captured Mac packet before the fix: `08 ee 00 00 00 01 81 10 00 1a 04 07 0a 00 00 00`
- Difference from iPhone: the Mac packet used literal `10:00:00` local wall-clock fields during the visible test; the iPhone's captured time packet used UTC fields. `sync-time-ble` now encodes `0x8101` using UTC.

### 2026-04-07

- Command tried: `sync-time-ble` after UTC encoder fix
- Current-time packet sent: `08 ee 00 00 00 01 81 10 00 1a 04 07 0d 3a 17 00`
- Response: `09 ff 00 00 01 01 81 09 00`
- Visible test packet for `2026-04-07T10:00:00+05:30`: `08 ee 00 00 00 01 81 10 00 1a 04 07 04 1e 00 00`
- Response: `09 ff 00 00 01 01 81 09 00`
- Display change: user confirmed the display changed, but it showed `04:30`, meaning the Wakey applies payload fields literally rather than converting from UTC.
- Notes: This confirmed the Mac BLE command reaches and is accepted by the Wakey app protocol, but `sync-time-ble` should default to local wall-clock payload fields.

### 2026-04-07

- Command tried: raw local-wall-clock BLE packet for `10:00:00`
- Packet: `08 ee 00 00 00 01 81 10 00 1a 04 07 0a 00 00 00`
- Response: `09 ff 00 00 01 01 81 09 00`
- Display change: expected to show `10:00`; earlier UTC-payload run changed the display and showed that payload fields are applied literally
- Notes: `sync-time-ble` now defaults to local wall-clock payload fields. `--utc-payload` remains available only as a diagnostic mode to reproduce captured PacketLogger bytes.

### 2026-04-07

- Command tried: `sync-time-ble` with no explicit timestamp after reverting default payloads to local wall-clock fields
- Packet: `08 ee 00 00 00 01 81 10 00 1a 04 07 13 20 25 00`
- Response: `09 ff 00 00 01 01 81 09 00`
- Body meaning: `2026-04-07 19:32:37` local time
- Notes: This is the desired final behavior for syncing the Wakey display from the Mac.

### 2026-04-07

- Command tried: `device-info`
- Packet: none
- Response: device found as `Soundcore Wakey`, address `ac-b1-ee-25-da-04`, paired `true`, connected `true`
- Display change: none
- Notes: Live Bluetooth access works when launched via `WakeySync.app` using [`run_app.sh`](scripts/run_app.sh).

### 2026-04-07

- Command tried: `request-state`
- Packet: `08 ee 00 00 00 01 01 0a 00 02`
- Response: no inbound bytes observed within 4 seconds
- Display change: unknown
- Notes: RFCOMM channel opened successfully and write returned success. This was sent before the iPhone trace showed that captured Wakey frames omit the OpenSCQ30-style checksum byte.

### 2026-04-07

- Command tried: `0x0581`..`0x0584` with `year16` body and `+120 min` offset
- Packet: generated by [`probe_time_candidates.sh`](scripts/probe_time_candidates.sh)
- Response: no inbound bytes observed for any candidate
- Display change: unknown
- Notes: All four packets opened RFCOMM successfully and wrote successfully.

### 2026-04-07

- Command tried: `0x0501`..`0x0504` with `year16` body and `+120 min` offset
- Packet: generated by [`probe_time_candidates.sh`](scripts/probe_time_candidates.sh)
- Response: no inbound bytes observed for any candidate
- Display change: unknown
- Notes: All four packets opened RFCOMM successfully and wrote successfully.

## Android App Findings

- The Soundcore Android app contains Wakey model-specific strings:
  - `get:a3300_alarm_monday` through `get:a3300_alarm_sunday`
  - `get:a3300_sleep_reset`
- The Flutter AOT payload in `libapp.so` also contains:
  - `syncTime`
  - `bluetoothConnect`
  - `bluetoothScan`
  - `initNativeChannel`
  - `SCFlutterEventChannelHandler.sendDataToNative`
- We have not yet recovered the exact Wakey time-sync opcode or payload bytes from the APK.
- Reason: the app is Flutter AOT compiled, so the relevant logic appears to live in `libapp.so` rather than easy-to-search Java/Kotlin dex classes, and the strings are not exported as normal symbols.
