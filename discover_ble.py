#!/usr/bin/env python3
"""Scan for Soundcore Wakey BLE services."""

import asyncio
from bleak import BleakScanner, BleakClient

TARGET_NAME = "Soundcore Wakey"
TARGET_ADDR = "AC:B1:EE:25:DA:04"


async def scan():
    print("Scanning for BLE devices (10 seconds)...")
    devices = await BleakScanner.discover(timeout=10.0, return_adv=True)

    wakey = None
    for address, (device, adv_data) in devices.items():
        name = adv_data.local_name or device.name or "(unknown)"
        # Show all devices for debugging
        print(f"  {name:30s}  addr={address}  RSSI={adv_data.rssi}")
        if adv_data.service_uuids:
            print(f"    Services: {adv_data.service_uuids}")

        # Check if this is the Wakey
        if TARGET_NAME.lower() in (name or "").lower():
            wakey = device
            print(f"  *** FOUND WAKEY: {name} @ {address} ***")

    if not wakey:
        # Also try by address (CoreBluetooth may use opaque UUIDs)
        print(f"\nWakey not found by name. Trying by address...")
        wakey = await BleakScanner.find_device_by_name(TARGET_NAME, timeout=5.0)
        if wakey:
            print(f"  Found: {wakey.name} @ {wakey.address}")

    if not wakey:
        print(f"\n{TARGET_NAME} not found in BLE scan.")
        print("The device likely uses classic Bluetooth (RFCOMM) only for control commands.")
        return

    print(f"\nConnecting to {wakey.name} ({wakey.address})...")
    try:
        async with BleakClient(wakey) as client:
            print(f"Connected: {client.is_connected}")
            print("\n=== GATT Services ===")
            for service in client.services:
                print(f"\n[Service] {service.uuid} -- {service.description}")
                for char in service.characteristics:
                    props = ", ".join(char.properties)
                    value_str = ""
                    if "read" in char.properties:
                        try:
                            value = await client.read_gatt_char(char)
                            value_str = f" = {value.hex(' ')}"
                        except Exception as e:
                            value_str = f" (read error: {e})"
                    print(f"  [Char] {char.uuid}  [{props}]{value_str}")
                    for desc in char.descriptors:
                        try:
                            val = await client.read_gatt_descriptor(desc)
                            print(f"    [Desc] {desc.uuid} = {val.hex(' ')}")
                        except Exception:
                            print(f"    [Desc] {desc.uuid}")
    except Exception as e:
        print(f"Connection failed: {e}")


asyncio.run(scan())
