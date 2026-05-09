# Soundcore Wakey Time Sync from macOS

## Context

The Soundcore Wakey alarm clock speaker auto-syncs its display time when connected to a phone via the Soundcore app, but not when connected to a Mac. The goal is a proof-of-concept CLI command that syncs the Mac's current time to the Wakey's display.

**Speaker**: Soundcore Wakey @ `AC:B1:EE:25:DA:04`, firmware 1.1.11, connected via classic BT (HFP/AVRCP/A2DP).

**Key insight from research**: All known Soundcore devices (headphones, speakers) communicate commands over **RFCOMM (classic Bluetooth serial)**, not BLE. The open-source project [OpenSCQ30](https://github.com/Oppzippy/OpenSCQ30) has reverse-engineered the Soundcore RFCOMM packet format:
- Header: `08 ee 00 00 00` (outbound)
- Command: 2 bytes, little-endian
- Length: 2 bytes, little-endian (total packet size)
- Body: variable
- Checksum: 1 byte (sum of all preceding bytes % 256)

**Problem**: macOS Python lacks `socket.AF_BLUETOOTH` — we can't use raw BT sockets. We need either Swift/IOBluetooth or PyObjC for RFCOMM.

---

## Plan

### Step 1: BLE Discovery (quick check, ~5 min)

Before going down the RFCOMM path, quickly check if the Wakey also advertises BLE services — this would be the simpler path.

1. Install `blew` CLI: `brew install stass/tap/blew`
2. Run `blew scan` and look for "Soundcore Wakey" in BLE results
3. If found, run `blew gatt tree -n "Soundcore Wakey" -dr` to dump all GATT services/characteristics
4. Look for standard Current Time Service (UUID `0x1805`) or writable custom characteristics

**If BLE services with writable time characteristics are found** → skip to Step 4 (BLE variant).
**If no BLE** → continue to Step 2 (expected outcome based on research).

### Step 2: Capture Time Sync Traffic from iPhone (~20 min)

Use Apple PacketLogger to capture what the Soundcore app sends when it syncs time.

1. Download "Additional Tools for Xcode" from https://developer.apple.com/download/all/ (if not already installed)
2. Install the **Bluetooth Logging Profile** on the iPhone:
   - Go to https://developer.apple.com/bug-reporting/profiles-and-logs/?name=bluetooth on the iPhone
   - Install the logging profile and restart the iPhone
3. Connect iPhone to Mac via USB
4. Open PacketLogger on Mac → File → New iOS Trace
5. On the iPhone: open Soundcore app, connect to the Wakey, let it sync time
6. In PacketLogger: filter for RFCOMM or look for packets to/from `AC:B1:EE:25:DA:04`
7. Identify the time sync packet — look for:
   - Outbound RFCOMM data containing `08 ee 00 00 00` header
   - Payload bytes that correspond to the current time (year, month, day, hour, minute, second)
8. Document: the command code (2 bytes after header), the time payload format, and the RFCOMM channel/UUID

**Deliverable**: The exact packet format for the time sync command, saved to `protocol_notes.md`.

### Step 3: Build the RFCOMM Time Sync Tool

Two options depending on what works best:

#### Option A: Python + PyObjC (preferred — keeps everything in Python)

1. `pip3 install pyobjc-framework-IOBluetooth`
2. Create `sync_time.py` that:
   - Uses `IOBluetooth` framework via PyObjC to find the paired Wakey device by MAC address
   - Opens an RFCOMM channel (using the UUID or channel discovered in Step 2)
   - Constructs the time sync packet using the format from Step 2
   - Sends the packet
   - Closes the connection

#### Option B: Swift CLI tool (fallback if PyObjC is problematic)

1. Create `wakey_rfcomm.swift` that:
   - Uses `IOBluetoothDevice(addressString:)` to get the device
   - Opens RFCOMM channel
   - Sends the time sync packet
   - Compiles with `swiftc wakey_rfcomm.swift -framework IOBluetooth`

#### Packet construction (shared logic):

```
header  = bytes([0x08, 0xee, 0x00, 0x00, 0x00])
command = bytes([CMD_LO, CMD_HI])          # from Step 2
body    = encode_time(datetime.now())       # format from Step 2
length  = struct.pack('<H', 5 + 2 + 2 + len(body) + 1)
packet  = header + command + length + body
checksum = sum(packet) % 256
packet  += bytes([checksum])
```

### Step 4: BLE Variant (only if Step 1 finds BLE services)

1. `pip3 install bleak`
2. Create `sync_time.py` using `bleak`:
   - Scan for device by name
   - Connect and write current time to the discovered characteristic
   - Use standard CTS format (10 bytes) or the format discovered via traffic capture

### Step 5: Verification

1. Note the current time on the Wakey display
2. Run the sync script: `python3 sync_time.py`
3. Observe whether the Wakey display updates to the Mac's current time
4. Test with a deliberate offset to confirm it's actually writing (e.g., sync a time 1 hour ahead, then sync correct time)

---

## File Structure

```

├── sync_time.py            # Main script — the CLI command to sync time
├── protocol_notes.md       # Captured protocol details from Step 2
├── discover_ble.py         # Step 1: BLE discovery script (if needed)
└── requirements.txt        # Python dependencies
```

## Execution Order

1. **Step 1** — Quick BLE check (determines which path to take)
2. **Step 2** — Capture traffic from iPhone (if RFCOMM path)
3. **Step 3** — Build the tool
4. **Step 5** — Verify it works

Step 2 requires **user participation** — install the Bluetooth logging profile on iPhone, connect to Mac, and trigger a time sync from the Soundcore app while PacketLogger is recording.
