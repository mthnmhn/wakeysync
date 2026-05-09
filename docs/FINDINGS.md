# Soundcore Wakey Time Sync — Research Findings

## Goal

Build a proof-of-concept CLI tool on macOS that syncs the Mac's current time to a Soundcore Wakey alarm clock speaker's display. The Soundcore app on iPhone does this automatically, but no such mechanism exists for macOS.

## Device Details

- **Device Name**: Soundcore Wakey (Anker model A3300)
- **Bluetooth MAC Address**: `AC:B1:EE:25:DA:04`
- **Firmware Version**: 1.1.11
- **Connection Type**: Classic Bluetooth (NOT BLE)
- **Connected Profiles**: HFP, AVRCP, A2DP, ACL

## Key Finding #1: No BLE — Classic Bluetooth Only

We ran a full BLE scan using Python `bleak` library. The Soundcore Wakey does **NOT** advertise any BLE (Bluetooth Low Energy) services. It only uses classic Bluetooth. This is consistent with research showing all known Soundcore devices use RFCOMM for command/control.

The BLE scan script is at `discover_ble.py` — it confirmed zero BLE presence for this device.

## Key Finding #2: SDP Service Discovery — RFCOMM Channel 2

We successfully queried the Wakey's SDP (Service Discovery Protocol) records using Python + PyObjC + IOBluetooth framework. The device exposes **10 services**:

| # | Service Name | UUID | Notes |
|---|-------------|------|-------|
| 0 | (unnamed) | `0x1000` | SDP server |
| 1 | (unnamed) | `0x1200` | PnP info |
| **2** | **Serial Port Service - Channel 2** | **`0cf12d31-fac3-4553-bd80-d6832e7b3300`** | **THIS IS THE SOUNDCORE DATA CHANNEL** |
| 3 | HandsFree | `0x1203` | HFP |
| 4 | HandsFree | `0x111e` | HFP |
| 5 | AVRCP TG | `0x110c` | Audio/Video Remote Control Target |
| 6 | AVRCP CT | `0x110f` | Audio/Video Remote Control Controller |
| 7 | AVRCP CT | `0x110e` | Audio/Video Remote Control |
| 8 | A2DP Sink | `0x110b` | Advanced Audio Distribution |
| 9 | (unnamed) | `0x0001` | SDP |

### The Critical Service: Service 2

- **Name**: "Serial Port Service - Channel 2"
- **UUID**: `0cf12d31-fac3-4553-bd80-d6832e7b3300`
  - This matches the OpenSCQ30 vendor UUID pattern: `0cf12d31-fac3-4553-bd80-d6832e7xxxxx`
- **RFCOMM Channel**: **2** (from protocol descriptor: `uuid32(00 00 00 03), uint32(2)`)
- **Protocol Stack**: L2CAP → RFCOMM (channel 2)

This is the channel the Soundcore app uses to send commands (EQ, time sync, alarms, etc.).

### Full SDP attributes for Service 2:
```
Attr 0x0000: uint32(65541)                    # Service record handle
Attr 0x0009: uuid32(00 00 11 01), uint32(258) # Profile descriptor (Serial Port, v1.2)
Attr 0x0005: { uuid32(00 00 10 02) }          # Browse group
Attr 0x0001: uuid128(0c f1 2d 31 fa c3 45 53 bd 80 d6 83 2e 7b 33 00)  # Service class UUID
Attr 0x0100: string(Serial Port Service - Channel 2)  # Service name
Attr 0x0006: { uint32(25966), uint32(106), uint32(256) }  # Language base
Attr 0x0008: uint32(255)                      # Service availability
Attr 0x0004: { { uuid32(00 00 01 00) }, { uuid32(00 00 00 03), uint32(2) } }  # Protocol: L2CAP + RFCOMM ch2
```

## Key Finding #3: Wakey RFCOMM Packet Format

The initial implementation used the OpenSCQ30 headphone framing as a starting point. PacketLogger captures from the iPhone Soundcore app show that the Wakey uses the same header and little-endian command/length fields, but the captured Wakey frames do not include a trailing checksum byte.

### Packet Structure

```
+--------+--------+--------+---------+
| Header | Command| Length | Body    |
| 5 bytes| 2 bytes| 2 bytes| N bytes |
+--------+--------+--------+---------+
```

- **Header (5 bytes)**: `08 ee 00 00 00` for outbound (Mac → speaker)
  - Response header is `09 ff 00 00 01` (speaker → Mac)
- **Command (2 bytes)**: Little-endian command code (e.g., `01 01` = request state)
- **Length (2 bytes)**: Little-endian total frame length (header + command + length + body)
- **Body (N bytes)**: Command-specific payload

### Example: Captured Time Sync Packet
```
08 ee 00 00 00  # header (outbound)
01 81           # command: sync time
10 00           # length: 16 bytes total
1a 04 07        # 2026-04-07
11 2d 0d        # 17:45:13
00              # reserved byte observed in the iPhone capture
```

### Known Command Codes
- `01 81` — Sync time on the Wakey, captured from the iPhone app
- `05 01` — Unknown outbound command captured from the iPhone app
- `05 02` — Unknown outbound command captured from the iPhone app
- `01 01` — Request device state in OpenSCQ30/headphone research, not re-confirmed from the iPhone Wakey trace

## Key Finding #4: macOS RFCOMM Access

### What DOESN'T work:
- **Python `socket.AF_BLUETOOTH`**: Does NOT exist on macOS. Python's socket module has no Bluetooth support on Darwin.
- **PyBluez**: Not compatible with macOS (or extremely outdated).
- **bleak**: Only supports BLE, not classic Bluetooth RFCOMM.

### What DOES work:
- **PyObjC + IOBluetooth**: Successfully tested. Can load `IOBluetooth.framework`, find paired devices, query SDP services. Available classes include `IOBluetoothDevice`, `IOBluetoothRFCOMMChannel`, etc.
  - Installed: `pip3 install pyobjc-framework-IOBluetooth` (v12.0)
  - Caveat: RFCOMM requires delegate-based async patterns which are complex in Python
- **Swift + IOBluetooth**: `swiftc` is available (Swift 6.2.4). Native access to `IOBluetoothDevice`, `IOBluetoothRFCOMMChannel`. This is the more straightforward path for RFCOMM.
  - Compile: `swiftc tool.swift -framework IOBluetooth`

## Environment

- **macOS**: Darwin 25.2.0 (arm64)
- **Python**: 3.9.6 (system)
- **Swift**: 6.2.4 (Apple, from Command Line Tools)
- **Xcode**: Command Line Tools only (no full Xcode — `blew` CLI couldn't be installed because of this)
- **Installed Python packages**: `bleak` 1.1.1, `pyobjc-core` 12.0, `pyobjc-framework-IOBluetooth` 12.0, `pyobjc-framework-CoreBluetooth` 12.0, `pyobjc-framework-Cocoa` 12.0

## Current Implementation

The iPhone PacketLogger capture recovered the time sync command and the Swift tool now has a dedicated `sync-time` command.

### Captured Time Sync Command

- Command: `0x8101` (`01 81` on the wire)
- Body: `year_since_2000 month day hour minute second 00`
- Example: `08 ee 00 00 00 01 81 10 00 1a 04 07 11 2d 0d 00`

### Swift RFCOMM Tool

The Swift tool:

1. Finds the Wakey by MAC address `AC:B1:EE:25:DA:04`
2. Opens RFCOMM channel 2
3. Sends the time sync packet
4. Reads any immediate response
5. Closes the connection

#### Swift approach (recommended):
```swift
import IOBluetooth
import Foundation

// Key APIs:
// IOBluetoothDevice(addressString: "AC-B1-EE-25-DA-04")
// device.openRFCOMMChannelSync(&channel, withChannelID: 2, delegate: delegate)
// channel.writeSync(dataPtr, length: UInt16(data.count))
// channel.closeChannel()
```

#### Python+PyObjC approach (fallback):
```python
import objc
IOBluetooth = objc.loadBundle('IOBluetooth', ...)
device = IOBluetoothDevice.deviceWithAddressString_("AC-B1-EE-25-DA-04")
# Open RFCOMM channel 2, set up delegate for data reception
# Requires NSRunLoop for async delegate callbacks
```

### Packet Builder

```python
import struct
from datetime import datetime

def build_time_packet(dt: datetime) -> bytes:
    header = bytes([0x08, 0xee, 0x00, 0x00, 0x00])
    command = bytes([0x01, 0x81])
    body = bytes([
        dt.year - 2000,
        dt.month, dt.day, dt.hour, dt.minute, dt.second
    ]) + bytes([0x00])
    length = struct.pack('<H', 5 + 2 + 2 + len(body))
    return header + command + length + body
```

### Verification

1. Run the sync tool
2. Check if the Wakey display updates
3. Try syncing a deliberately wrong time (e.g., 1 hour offset) to confirm the tool is actually setting the time

## File Structure

```

├── PLAN.md              # Original implementation plan
├── FINDINGS.md          # This file — research findings
├── discover_ble.py      # BLE scan script (confirmed no BLE)
├── Sources/WakeySync/   # Swift CLI and shared Bluetooth/RFCOMM logic
├── App/                 # AppKit launcher for macOS Bluetooth privacy access
└── scripts/             # Build/run/probing helpers
```

## References

- **OpenSCQ30**: https://github.com/Oppzippy/OpenSCQ30 — Rust project for Soundcore headphones, has packet format details
- **SoundcoreDesktop**: Python project using RFCOMM for Soundcore devices
- **Gadgetbridge**: Android app supporting various BT devices including some Soundcore
- **bleak**: https://bleak.readthedocs.io/ — Python BLE library (used for BLE scan, not for RFCOMM)
- **IOBluetooth Framework**: Apple's native Bluetooth framework for classic BT on macOS
- **PacketLogger**: Apple's BT traffic capture tool (in "Additional Tools for Xcode")
