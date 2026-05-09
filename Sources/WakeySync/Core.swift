import Foundation
@preconcurrency import CoreBluetooth
import IOBluetooth

let defaultDeviceAddress = "AC:B1:EE:25:DA:04"
let defaultDeviceName = "Soundcore Wakey"
let defaultRFCOMMChannel: UInt8 = 2
let wakeySyncTimeCommand: UInt16 = 0x8101

enum WakeyBLE {
    static let serviceUUIDString = "0109F5DA-0000-1000-8000-00805F9B34FB"
    static let writeCharacteristicUUIDString = "7777"
    static let notifyCharacteristicUUIDString = "8888"

    static var serviceUUID: CBUUID { CBUUID(string: serviceUUIDString) }
    static var writeCharacteristicUUID: CBUUID { CBUUID(string: writeCharacteristicUUIDString) }
    static var notifyCharacteristicUUID: CBUUID { CBUUID(string: notifyCharacteristicUUIDString) }
}

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case invalidArgument(String)
    case bluetooth(String)

    var description: String {
        switch self {
        case .usage(let message), .invalidArgument(let message), .bluetooth(let message):
            return message
        }
    }
}

struct Hex {
    static func parseBytes(_ rawValue: String) throws -> [UInt8] {
        let stripped = rawValue
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        if stripped.isEmpty {
            return []
        }

        if stripped.count == 1 {
            let compact = stripped[0]
                .replacingOccurrences(of: "0x", with: "")
                .replacingOccurrences(of: "0X", with: "")
            guard compact.count.isMultiple(of: 2) else {
                throw CLIError.invalidArgument("Hex string must have an even number of digits: \(rawValue)")
            }

            return try stride(from: 0, to: compact.count, by: 2).map { index in
                let start = compact.index(compact.startIndex, offsetBy: index)
                let end = compact.index(start, offsetBy: 2)
                let token = String(compact[start..<end])
                guard let byte = UInt8(token, radix: 16) else {
                    throw CLIError.invalidArgument("Invalid hex byte: \(token)")
                }
                return byte
            }
        }

        return try stripped.map { token in
            let cleaned = token
                .replacingOccurrences(of: "0x", with: "")
                .replacingOccurrences(of: "0X", with: "")

            guard let byte = UInt8(cleaned, radix: 16) else {
                throw CLIError.invalidArgument("Invalid hex byte: \(token)")
            }
            return byte
        }
    }

    static func parseUInt16(_ rawValue: String) throws -> UInt16 {
        let cleaned = rawValue
            .replacingOccurrences(of: "_", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.lowercased().hasPrefix("0x"), let value = UInt16(cleaned.dropFirst(2), radix: 16) {
            return value
        }

        if let value = UInt16(cleaned) {
            return value
        }

        if let value = UInt16(cleaned, radix: 16) {
            return value
        }

        throw CLIError.invalidArgument("Expected a 16-bit integer, got: \(rawValue)")
    }

    static func string(for bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    static func compactString(for bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

struct SoundcorePacket {
    static let outboundHeader: [UInt8] = [0x08, 0xee, 0x00, 0x00, 0x00]

    static func build(command: UInt16, body: [UInt8]) -> [UInt8] {
        var packet = outboundHeader
        packet.append(UInt8(command & 0xff))
        packet.append(UInt8((command >> 8) & 0xff))

        let length = UInt16(outboundHeader.count + 2 + 2 + body.count)
        packet.append(UInt8(length & 0xff))
        packet.append(UInt8((length >> 8) & 0xff))
        packet.append(contentsOf: body)
        return packet
    }
}

enum TimeBodyFormat: String, CaseIterable {
    case year16
    case year16Weekday = "year16-weekday"
    case year2000
    case unix32

    func encode(date: Date, calendar: Calendar = .current) throws -> [UInt8] {
        switch self {
        case .year16:
            let parts = try dateParts(for: date, calendar: calendar)
            return le16(parts.year) + [parts.month, parts.day, parts.hour, parts.minute, parts.second]
        case .year16Weekday:
            let parts = try dateParts(for: date, calendar: calendar)
            return le16(parts.year) + [parts.month, parts.day, parts.weekday, parts.hour, parts.minute, parts.second]
        case .year2000:
            let parts = try dateParts(for: date, calendar: calendar)
            guard parts.year >= 2000, parts.year <= 2255 else {
                throw CLIError.invalidArgument("year2000 format only supports years 2000...2255")
            }
            return [UInt8(parts.year - 2000), parts.month, parts.day, parts.hour, parts.minute, parts.second]
        case .unix32:
            let timestamp = UInt32(date.timeIntervalSince1970.rounded())
            return [
                UInt8(timestamp & 0xff),
                UInt8((timestamp >> 8) & 0xff),
                UInt8((timestamp >> 16) & 0xff),
                UInt8((timestamp >> 24) & 0xff),
            ]
        }
    }

    private func dateParts(for date: Date, calendar: Calendar) throws -> (year: UInt16, month: UInt8, day: UInt8, weekday: UInt8, hour: UInt8, minute: UInt8, second: UInt8) {
        let components = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute, .second], from: date)

        guard
            let year = components.year,
            let month = components.month,
            let day = components.day,
            let weekday = components.weekday,
            let hour = components.hour,
            let minute = components.minute,
            let second = components.second,
            let year16 = UInt16(exactly: year),
            let month8 = UInt8(exactly: month),
            let day8 = UInt8(exactly: day),
            let weekday8 = UInt8(exactly: weekday),
            let hour8 = UInt8(exactly: hour),
            let minute8 = UInt8(exactly: minute),
            let second8 = UInt8(exactly: second)
        else {
            throw CLIError.invalidArgument("Could not derive time components from \(date)")
        }

        return (year16, month8, day8, weekday8, hour8, minute8, second8)
    }

    private func le16(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xff), UInt8((value >> 8) & 0xff)]
    }
}

func wakeyUTCCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

struct CLIArguments {
    let command: String
    let values: [String: String]
    let flags: Set<String>

    init(argv: [String]) throws {
        guard let command = argv.first else {
            throw CLIError.usage(Self.usage)
        }

        self.command = command

        var values: [String: String] = [:]
        var flags = Set<String>()
        var index = 1

        while index < argv.count {
            let token = argv[index]
            guard token.hasPrefix("--") else {
                throw CLIError.invalidArgument("Unexpected positional argument: \(token)")
            }

            let key = String(token.dropFirst(2))

            if index + 1 < argv.count, !argv[index + 1].hasPrefix("--") {
                values[key] = argv[index + 1]
                index += 2
            } else {
                flags.insert(key)
                index += 1
            }
        }

        self.values = values
        self.flags = flags
    }

    func value(_ key: String, default defaultValue: String? = nil) -> String? {
        values[key] ?? defaultValue
    }

    func double(_ key: String, default defaultValue: Double) throws -> Double {
        guard let raw = values[key] else {
            return defaultValue
        }
        guard let value = Double(raw) else {
            throw CLIError.invalidArgument("Expected a number for --\(key), got: \(raw)")
        }
        return value
    }

    func uint8(_ key: String, default defaultValue: UInt8) throws -> UInt8 {
        guard let raw = values[key] else {
            return defaultValue
        }
        guard let value = UInt8(raw) else {
            throw CLIError.invalidArgument("Expected an 8-bit integer for --\(key), got: \(raw)")
        }
        return value
    }

    func int(_ key: String, default defaultValue: Int) throws -> Int {
        guard let raw = values[key] else {
            return defaultValue
        }
        guard let value = Int(raw) else {
            throw CLIError.invalidArgument("Expected an integer for --\(key), got: \(raw)")
        }
        return value
    }

    static let usage = """
    Usage:
      wakeyctl help
      wakeyctl device-info [--address MAC] [--name NAME]
      wakeyctl services [--address MAC] [--name NAME]
      wakeyctl build-packet --command 0x0101 [--body "aa bb cc"]
      wakeyctl build-time-packet --command 0x0401 [--format year16] [--iso8601 2026-04-07T16:00:00+05:30] [--offset-minutes 60]
      wakeyctl build-sync-time-packet [--iso8601 2026-04-07T16:00:00+05:30] [--offset-minutes 60] [--utc-payload]
      wakeyctl ble-scan [--address MAC] [--name NAME] [--scan-seconds 8]
      wakeyctl sync-time-ble [--address MAC] [--ble-id UUID] [--scan-seconds 8] [--listen-seconds 2] [--pre-send-delay 0.5] [--write-with-response] [--discover-all] [--iso8601 2026-04-07T16:00:00+05:30] [--offset-minutes 60] [--utc-payload]
      wakeyctl ble-send --packet "08 ee ..." [--address MAC] [--ble-id UUID] [--scan-seconds 8] [--listen-seconds 2] [--pre-send-delay 0.5] [--write-with-response] [--discover-all]
      wakeyctl ble-send-sequence --packets "08 ee ...|08 ee ..." [--address MAC] [--ble-id UUID] [--scan-seconds 8] [--listen-seconds 2] [--pre-send-delay 0.5] [--inter-packet-delay 0.15] [--write-with-response] [--discover-all]
      wakeyctl request-state [--address MAC] [--channel 2] [--listen-seconds 2] [--pre-send-delay 0.5]
      wakeyctl sync-time [--address MAC] [--channel 2] [--listen-seconds 2] [--pre-send-delay 0.5] [--iso8601 2026-04-07T16:00:00+05:30] [--offset-minutes 60] [--utc-payload]
      wakeyctl send --packet "08 ee ..." [--address MAC] [--channel 2] [--listen-seconds 2] [--pre-send-delay 0.5]
      wakeyctl send-sequence --packets "08 ee ...|08 ee ..." [--address MAC] [--channel 2] [--listen-seconds 2] [--pre-send-delay 0.5] [--inter-packet-delay 0.15]

    Notes:
      --address accepts either AC:B1:... or AC-B1-...
      BLE discovery matches the Wakey advertisement that embeds the classic address in little-endian form.
      Supported time formats: \(TimeBodyFormat.allCases.map(\.rawValue).joined(separator: ", "))
      sync-time uses the captured Wakey command 0x8101 and local wall-clock body format year2000 + reserved 0x00; --utc-payload is a diagnostic trace-replay mode.
    """
}

struct BLETarget {
    let classicAddress: String?
    let classicAddressBytesLE: [UInt8]?
    let peripheralIdentifier: UUID?
    let name: String?

    var isUntargeted: Bool {
        classicAddressBytesLE == nil && peripheralIdentifier == nil && name == nil
    }

    init(address: String?, peripheralID: String?, name: String?) throws {
        self.classicAddress = address.map(Self.normalize(address:))
        self.classicAddressBytesLE = try address.map(Self.littleEndianAddressBytes(address:))

        if let peripheralID {
            guard let uuid = UUID(uuidString: peripheralID) else {
                throw CLIError.invalidArgument("Expected a UUID for --ble-id, got: \(peripheralID)")
            }
            self.peripheralIdentifier = uuid
        } else {
            self.peripheralIdentifier = nil
        }

        self.name = name
    }

    func matches(peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        if let peripheralIdentifier, peripheral.identifier == peripheralIdentifier {
            return true
        }

        if let classicAddressBytesLE,
           let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           Array(manufacturerData).windows(ofCount: classicAddressBytesLE.count).contains(classicAddressBytesLE) {
            return true
        }

        let candidateName = (
            advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? peripheral.name
            ?? ""
        ).lowercased()
        if let name, !name.isEmpty, candidateName.contains(name.lowercased()) {
            return true
        }

        return peripheralIdentifier == nil && classicAddressBytesLE == nil && name == nil
    }

    static func normalize(address: String) -> String {
        address.uppercased().replacingOccurrences(of: ":", with: "-")
    }

    static func littleEndianAddressBytes(address: String) throws -> [UInt8] {
        let normalized = normalize(address: address)
        let parts = normalized.split(separator: "-").map(String.init)
        guard parts.count == 6 else {
            throw CLIError.invalidArgument("Expected a Bluetooth MAC address, got: \(address)")
        }

        return try parts.reversed().map { part in
            guard let byte = UInt8(part, radix: 16) else {
                throw CLIError.invalidArgument("Invalid Bluetooth address byte: \(part)")
            }
            return byte
        }
    }
}

extension Array where Element: Equatable {
    func windows(ofCount count: Int) -> [[Element]] {
        guard count > 0, count <= self.count else {
            return []
        }

        return (0...(self.count - count)).map { index in
            Array(self[index..<(index + count)])
        }
    }
}

final class BLESession: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private enum Phase {
        case waitingForBluetooth
        case scanning
        case connecting
        case discovering
        case subscribing
        case readyToWrite
        case writing
        case listening
        case finished
    }

    private let target: BLETarget
    private let packets: [[UInt8]]
    private let scanSeconds: Double
    private let listenSeconds: Double
    private let preSendDelay: Double
    private let interPacketDelay: Double
    private let writeWithResponse: Bool
    private let discoverAll: Bool
    private let printDiscoveredOnly: Bool
    private let log: (String) -> Void

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var notifyCharacteristic: CBCharacteristic?
    private var writeCharacteristic: CBCharacteristic?
    private var phase = Phase.waitingForBluetooth
    private var scanDeadline = Date.distantFuture
    private var hardDeadline = Date.distantFuture
    private var isFinished = false
    private var finishError: Error?
    private var nextPacketIndex = 0
    private var nextWriteAt: Date?
    private var finishAt: Date?
    private var waitingForWriteWithoutResponseReady = false
    private var printedPeripheralIDs = Set<UUID>()
    private(set) var receivedNotifications: [[UInt8]] = []

    init(target: BLETarget, packets: [[UInt8]], scanSeconds: Double, listenSeconds: Double, preSendDelay: Double, interPacketDelay: Double, writeWithResponse: Bool = false, discoverAll: Bool = false, printDiscoveredOnly: Bool = false, log: @escaping (String) -> Void = { print($0) }) {
        self.target = target
        self.packets = packets
        self.scanSeconds = scanSeconds
        self.listenSeconds = listenSeconds
        self.preSendDelay = preSendDelay
        self.interPacketDelay = interPacketDelay
        self.writeWithResponse = writeWithResponse
        self.discoverAll = discoverAll
        self.printDiscoveredOnly = printDiscoveredOnly
        self.log = log
    }

    func run() throws {
        guard printDiscoveredOnly || !packets.isEmpty else {
            throw CLIError.invalidArgument("At least one BLE packet is required")
        }

        scanDeadline = Date().addingTimeInterval(scanSeconds)
        hardDeadline = Date().addingTimeInterval(scanSeconds + preSendDelay + listenSeconds + Double(packets.count) * max(interPacketDelay, 0.2) + 12)
        central = CBCentralManager(delegate: self, queue: .main)

        while !isFinished {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))

            if phase == .scanning, Date() > scanDeadline {
                complete(error: printDiscoveredOnly ? nil : CLIError.bluetooth("BLE scan timed out after \(scanSeconds)s"))
            }

            if let nextWriteAt, Date() >= nextWriteAt {
                self.nextWriteAt = nil
                writeNextPacket()
            }

            if let finishAt, Date() >= finishAt {
                self.finishAt = nil
                complete(error: nil)
            }

            if Date() > hardDeadline {
                complete(error: CLIError.bluetooth("BLE operation timed out"))
            }
        }

        if let finishError {
            throw finishError
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            startScan(central: central)
        case .poweredOff:
            complete(error: CLIError.bluetooth("Bluetooth is powered off"))
        case .unauthorized:
            complete(error: CLIError.bluetooth("Bluetooth is not authorized for this app. Launch through ./scripts/run_app.sh and allow Bluetooth access."))
        case .unsupported:
            complete(error: CLIError.bluetooth("Bluetooth LE is unsupported on this Mac"))
        case .resetting, .unknown:
            break
        @unknown default:
            complete(error: CLIError.bluetooth("Unhandled Bluetooth state: \(central.state.rawValue)"))
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "(unnamed)"
        let manufacturerText = manufacturerData.map { Hex.string(for: Array($0)) } ?? "(none)"
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []

        let isMatch = target.matches(peripheral: peripheral, advertisementData: advertisementData)

        let shouldPrint = (printDiscoveredOnly && (target.isUntargeted || isMatch)) || (!printDiscoveredOnly && isMatch)
        if shouldPrint, !printedPeripheralIDs.contains(peripheral.identifier) {
            printedPeripheralIDs.insert(peripheral.identifier)
            log("[ble] found name=\"\(localName)\" id=\(peripheral.identifier.uuidString) rssi=\(RSSI) services=\(serviceUUIDs.map(\.uuidString).joined(separator: ",")) mfr=\(manufacturerText)")
        }

        guard !printDiscoveredOnly, isMatch else {
            return
        }

        phase = .connecting
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        log("[ble] connecting to \(localName) id=\(peripheral.identifier.uuidString)")
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        phase = .discovering
        log("[ble] connected")
        peripheral.discoverServices(discoverAll ? nil : [WakeyBLE.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        complete(error: error ?? CLIError.bluetooth("BLE connect failed"))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error, !isFinished {
            complete(error: error)
        } else if !isFinished {
            complete(error: CLIError.bluetooth("BLE peripheral disconnected before operation completed"))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            complete(error: error)
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == WakeyBLE.serviceUUID }) else {
            complete(error: CLIError.bluetooth("Could not find Wakey BLE service \(WakeyBLE.serviceUUIDString)"))
            return
        }

        log("[ble] discovered service \(service.uuid.uuidString)")
        peripheral.discoverCharacteristics(discoverAll ? nil : [WakeyBLE.notifyCharacteristicUUID, WakeyBLE.writeCharacteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            complete(error: error)
            return
        }

        for characteristic in service.characteristics ?? [] {
            log("[ble] characteristic \(characteristic.uuid.uuidString) properties=0x\(String(characteristic.properties.rawValue, radix: 16))")
            if characteristic.uuid == WakeyBLE.notifyCharacteristicUUID {
                notifyCharacteristic = characteristic
            } else if characteristic.uuid == WakeyBLE.writeCharacteristicUUID {
                writeCharacteristic = characteristic
            }
        }

        guard let notifyCharacteristic else {
            complete(error: CLIError.bluetooth("Could not find notify characteristic \(WakeyBLE.notifyCharacteristicUUIDString)"))
            return
        }

        guard writeCharacteristic != nil else {
            complete(error: CLIError.bluetooth("Could not find write characteristic \(WakeyBLE.writeCharacteristicUUIDString)"))
            return
        }

        phase = .subscribing
        log("[ble] enabling notifications on \(notifyCharacteristic.uuid.uuidString)")
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            complete(error: error)
            return
        }

        guard characteristic.uuid == WakeyBLE.notifyCharacteristicUUID else {
            return
        }

        log("[ble] notifications enabled=\(characteristic.isNotifying)")
        phase = .readyToWrite

        if preSendDelay > 0 {
            log("[ble] waiting \(preSendDelay)s before write")
        }

        nextWriteAt = Date().addingTimeInterval(preSendDelay)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            log("[ble] notify error: \(error)")
            return
        }

        guard let value = characteristic.value else {
            log("[ble] notify \(characteristic.uuid.uuidString): (empty)")
            return
        }

        let bytes = Array(value)
        receivedNotifications.append(bytes)
        log("[ble] notify \(characteristic.uuid.uuidString) \(value.count) bytes: \(Hex.string(for: bytes))")
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            complete(error: error)
            return
        }

        guard writeWithResponse, characteristic.uuid == WakeyBLE.writeCharacteristicUUID else {
            return
        }

        log("[ble] write response from \(characteristic.uuid.uuidString)")
        scheduleNextPacket()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard waitingForWriteWithoutResponseReady else {
            return
        }

        waitingForWriteWithoutResponseReady = false
        log("[ble] writeWithoutResponse ready")
        writeNextPacket()
    }

    private func startScan(central: CBCentralManager) {
        phase = .scanning
        log("[ble] scanning for Wakey BLE advertisements for \(scanSeconds)s")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

    }

    private func writeNextPacket() {
        guard !isFinished else {
            return
        }

        guard let peripheral, let writeCharacteristic else {
            complete(error: CLIError.bluetooth("BLE write attempted before peripheral/characteristic was ready"))
            return
        }

        guard nextPacketIndex < packets.count else {
            phase = .listening
            if listenSeconds > 0 {
                finishAt = Date().addingTimeInterval(listenSeconds)
            } else {
                complete(error: nil)
            }
            return
        }

        phase = .writing
        let packet = packets[nextPacketIndex]
        let index = nextPacketIndex + 1

        if !writeWithResponse, !peripheral.canSendWriteWithoutResponse {
            waitingForWriteWithoutResponseReady = true
            log("[ble] waiting for writeWithoutResponse readiness before packet \(index)")
            return
        }

        nextPacketIndex += 1
        let writeType: CBCharacteristicWriteType = writeWithResponse ? .withResponse : .withoutResponse
        log("[ble] send \(index)/\(packets.count) \(packet.count) bytes to \(writeCharacteristic.uuid.uuidString) type=\(writeWithResponse ? "withResponse" : "withoutResponse"): \(Hex.string(for: packet))")
        peripheral.writeValue(Data(packet), for: writeCharacteristic, type: writeType)

        if !writeWithResponse {
            scheduleNextPacket()
        }
    }

    private func scheduleNextPacket() {
        let delay = nextPacketIndex < packets.count ? interPacketDelay : 0
        nextWriteAt = Date().addingTimeInterval(delay)
    }

    private func complete(error: Error?) {
        guard !isFinished else {
            return
        }

        finishError = error
        isFinished = true
        phase = .finished

        if let peripheral, peripheral.state == .connected {
            central?.cancelPeripheralConnection(peripheral)
        }
        central?.stopScan()
    }
}

final class RFCOMMDelegate: NSObject, IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel?, status error: IOReturn) {
        let message = error == kIOReturnSuccess ? "opened" : "open failed"
        print("[rfcomm] \(message) status=\(BluetoothSession.describe(status: error))")
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel) {
        print("[rfcomm] channel closed")
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel, data dataPointer: UnsafeMutableRawPointer, length dataLength: Int) {
        let buffer = dataPointer.bindMemory(to: UInt8.self, capacity: dataLength)
        let bytes = Array(UnsafeBufferPointer(start: buffer, count: dataLength))
        print("[rfcomm] recv \(dataLength) bytes: \(Hex.string(for: bytes))")
    }
}

enum BluetoothSession {
    static func lookupDevice(address: String?, name: String?) throws -> IOBluetoothDevice {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        guard !paired.isEmpty else {
            throw CLIError.bluetooth("No paired Bluetooth devices were returned by macOS. Confirm Bluetooth access is allowed for the terminal and the Wakey is paired.")
        }

        if let address {
            let normalized = normalize(address: address)
            if let device = paired.first(where: { ($0.addressString ?? "").uppercased() == normalized }) {
                return device
            }
            throw CLIError.bluetooth("Could not find a paired device with address \(address)")
        }

        let targetName = (name ?? defaultDeviceName).lowercased()
        if let device = paired.first(where: { ($0.nameOrAddress ?? "").lowercased().contains(targetName) }) {
            return device
        }

        throw CLIError.bluetooth("Could not find a paired device matching name \(name ?? defaultDeviceName)")
    }

    static func printDeviceInfo(device: IOBluetoothDevice) {
        print("name: \(device.nameOrAddress ?? "(unknown)")")
        print("address: \(device.addressString ?? "(unknown)")")
        print("paired: \(device.isPaired())")
        print("connected: \(device.isConnected())")
    }

    static func printServices(device: IOBluetoothDevice) {
        let services = (device.value(forKey: "services") as? [IOBluetoothSDPServiceRecord]) ?? []
        print("services: \(services.count)")

        for (index, service) in services.enumerated() {
            var channelID = BluetoothRFCOMMChannelID(0)
            let channelStatus = service.getRFCOMMChannelID(&channelID)

            var handle = BluetoothSDPServiceRecordHandle(0)
            let handleStatus = service.getHandle(&handle)

            let channelText = channelStatus == kIOReturnSuccess ? "\(channelID)" : "none (\(describe(status: channelStatus)))"
            let handleText = handleStatus == kIOReturnSuccess ? String(format: "0x%08x", handle) : "unknown"
            let name = service.getServiceName() ?? "(unnamed)"
            let serviceClassList = service.getAttributeDataElement(0x0001)?.description ?? "(no service class list)"

            print("[\(index)] \(name)")
            print("  service class list: \(serviceClassList)")
            print("  handle: \(handleText)")
            print("  rfcomm channel: \(channelText)")
        }
    }

    static func send(packet: [UInt8], to device: IOBluetoothDevice, channelID: UInt8, listenSeconds: Double, preSendDelay: Double) throws {
        try send(packets: [packet], to: device, channelID: channelID, listenSeconds: listenSeconds, preSendDelay: preSendDelay, interPacketDelay: 0)
    }

    static func send(packets: [[UInt8]], to device: IOBluetoothDevice, channelID: UInt8, listenSeconds: Double, preSendDelay: Double, interPacketDelay: Double) throws {
        guard !packets.isEmpty else {
            throw CLIError.invalidArgument("At least one packet is required")
        }

        if !device.isConnected() {
            let connectionStatus = device.openConnection()
            guard connectionStatus == kIOReturnSuccess else {
                throw CLIError.bluetooth("openConnection failed with \(describe(status: connectionStatus))")
            }
        }

        let delegate = RFCOMMDelegate()
        var channel: IOBluetoothRFCOMMChannel?
        let openStatus = device.openRFCOMMChannelSync(&channel, withChannelID: BluetoothRFCOMMChannelID(channelID), delegate: delegate)
        guard openStatus == kIOReturnSuccess, let channel else {
            throw CLIError.bluetooth("openRFCOMMChannelSync failed with \(describe(status: openStatus))")
        }

        if preSendDelay > 0 {
            print("[rfcomm] waiting \(preSendDelay)s before write")
            RunLoop.current.run(until: Date().addingTimeInterval(preSendDelay))
        }

        for (index, packet) in packets.enumerated() {
            if index > 0, interPacketDelay > 0 {
                print("[rfcomm] waiting \(interPacketDelay)s before next write")
                RunLoop.current.run(until: Date().addingTimeInterval(interPacketDelay))
            }

            print("[rfcomm] send \(index + 1)/\(packets.count) \(packet.count) bytes: \(Hex.string(for: packet))")

            let writeStatus: IOReturn = packet.withUnsafeBytes { rawBuffer in
                channel.writeSync(
                    UnsafeMutableRawPointer(mutating: rawBuffer.baseAddress!),
                    length: UInt16(rawBuffer.count)
                )
            }

            guard writeStatus == kIOReturnSuccess else {
                channel.close()
                throw CLIError.bluetooth("writeSync failed with \(describe(status: writeStatus))")
            }
        }

        if listenSeconds > 0 {
            RunLoop.current.run(until: Date().addingTimeInterval(listenSeconds))
        }

        channel.close()
    }

    static func describe(status: IOReturn) -> String {
        let rawBits = UInt32(bitPattern: status)
        return "\(status) (0x" + String(rawBits, radix: 16) + ", signed \(status))"
    }

    private static func normalize(address: String) -> String {
        address.uppercased().replacingOccurrences(of: ":", with: "-")
    }
}

func parseDate(arguments: CLIArguments) throws -> Date {
    let offsetMinutes = try arguments.int("offset-minutes", default: 0)
    if let raw = arguments.value("iso8601") {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) {
            return date.addingTimeInterval(TimeInterval(offsetMinutes * 60))
        }
        throw CLIError.invalidArgument("Could not parse --iso8601 value: \(raw)")
    }

    return Date().addingTimeInterval(TimeInterval(offsetMinutes * 60))
}

func buildPacket(arguments: CLIArguments) throws -> [UInt8] {
    guard let commandRaw = arguments.value("command") else {
        throw CLIError.usage("build-packet requires --command\n\n\(CLIArguments.usage)")
    }

    let command = try Hex.parseUInt16(commandRaw)
    let body = try Hex.parseBytes(arguments.value("body", default: "") ?? "")
    return SoundcorePacket.build(command: command, body: body)
}

func buildTimePacket(arguments: CLIArguments) throws -> [UInt8] {
    guard let commandRaw = arguments.value("command") else {
        throw CLIError.usage("build-time-packet requires --command\n\n\(CLIArguments.usage)")
    }

    let command = try Hex.parseUInt16(commandRaw)
    let formatRaw = arguments.value("format", default: TimeBodyFormat.year16.rawValue) ?? TimeBodyFormat.year16.rawValue
    guard let format = TimeBodyFormat(rawValue: formatRaw) else {
        throw CLIError.invalidArgument("Unsupported time format: \(formatRaw)")
    }

    let body = try format.encode(date: parseDate(arguments: arguments))
    return SoundcorePacket.build(command: command, body: body)
}

func buildWakeySyncTimePacket(arguments: CLIArguments) throws -> [UInt8] {
    let calendar = arguments.flags.contains("utc-payload") ? wakeyUTCCalendar() : Calendar.current
    var body = try TimeBodyFormat.year2000.encode(date: parseDate(arguments: arguments), calendar: calendar)
    body.append(0x00)
    return SoundcorePacket.build(command: wakeySyncTimeCommand, body: body)
}

func buildWakeySyncTimePacket(date: Date, utcPayload: Bool = false) throws -> [UInt8] {
    let calendar = utcPayload ? wakeyUTCCalendar() : Calendar.current
    var body = try TimeBodyFormat.year2000.encode(date: date, calendar: calendar)
    body.append(0x00)
    return SoundcorePacket.build(command: wakeySyncTimeCommand, body: body)
}

struct WakeySyncResult {
    let packet: [UInt8]
    let notifications: [[UInt8]]

    var acknowledged: Bool {
        notifications.contains { bytes in
            bytes.count >= 9 &&
                bytes[0] == 0x09 &&
                bytes[1] == 0xff &&
                bytes[4] == 0x01 &&
                bytes[5] == 0x01 &&
                bytes[6] == 0x81
        }
    }
}

func syncWakeyTimeOverBLE(
    date: Date,
    address: String = defaultDeviceAddress,
    utcPayload: Bool = false,
    scanSeconds: Double = 12.0,
    listenSeconds: Double = 3.0,
    preSendDelay: Double = 0.55,
    log: @escaping (String) -> Void = { print($0) }
) throws -> WakeySyncResult {
    let packet = try buildWakeySyncTimePacket(date: date, utcPayload: utcPayload)
    let target = try BLETarget(address: address, peripheralID: nil, name: nil)
    let session = BLESession(
        target: target,
        packets: [packet],
        scanSeconds: scanSeconds,
        listenSeconds: listenSeconds,
        preSendDelay: preSendDelay,
        interPacketDelay: 0,
        log: log
    )
    try session.run()
    return WakeySyncResult(packet: packet, notifications: session.receivedNotifications)
}

func parsePacketSequence(arguments: CLIArguments) throws -> [[UInt8]] {
    guard let raw = arguments.value("packets") else {
        throw CLIError.usage("send-sequence requires --packets\n\n\(CLIArguments.usage)")
    }

    let packets = try raw
        .split(separator: "|", omittingEmptySubsequences: true)
        .map { try Hex.parseBytes(String($0)) }

    guard !packets.isEmpty else {
        throw CLIError.invalidArgument("--packets did not contain any packets")
    }

    return packets
}

@discardableResult
func runCLI(argv: [String]) throws -> Int32 {
    let arguments = try CLIArguments(argv: argv)

    switch arguments.command {
    case "help", "--help", "-h":
        print(CLIArguments.usage)

    case "device-info":
        let device = try BluetoothSession.lookupDevice(
            address: arguments.value("address", default: defaultDeviceAddress),
            name: arguments.value("name")
        )
        BluetoothSession.printDeviceInfo(device: device)

    case "services":
        let device = try BluetoothSession.lookupDevice(
            address: arguments.value("address", default: defaultDeviceAddress),
            name: arguments.value("name")
        )
        BluetoothSession.printServices(device: device)

    case "build-packet":
        let packet = try buildPacket(arguments: arguments)
        print(Hex.string(for: packet))

    case "build-time-packet":
        let packet = try buildTimePacket(arguments: arguments)
        print(Hex.string(for: packet))

    case "build-sync-time-packet":
        let packet = try buildWakeySyncTimePacket(arguments: arguments)
        print(Hex.string(for: packet))

    case "ble-scan":
        let target = try BLETarget(
            address: arguments.value("address"),
            peripheralID: arguments.value("ble-id"),
            name: arguments.value("name")
        )
        let scanSeconds = try arguments.double("scan-seconds", default: 8.0)
        try BLESession(
            target: target,
            packets: [],
            scanSeconds: scanSeconds,
            listenSeconds: 0,
            preSendDelay: 0,
            interPacketDelay: 0,
            printDiscoveredOnly: true
        ).run()

    case "sync-time-ble":
        let target = try BLETarget(
            address: arguments.value("address", default: defaultDeviceAddress),
            peripheralID: arguments.value("ble-id"),
            name: arguments.value("name")
        )
        let scanSeconds = try arguments.double("scan-seconds", default: 8.0)
        let listenSeconds = try arguments.double("listen-seconds", default: 2.0)
        let preSendDelay = try arguments.double("pre-send-delay", default: 0.5)
        let packet = try buildWakeySyncTimePacket(arguments: arguments)
        try BLESession(
            target: target,
            packets: [packet],
            scanSeconds: scanSeconds,
            listenSeconds: listenSeconds,
            preSendDelay: preSendDelay,
            interPacketDelay: 0,
            writeWithResponse: arguments.flags.contains("write-with-response"),
            discoverAll: arguments.flags.contains("discover-all")
        ).run()

    case "ble-send":
        guard let packetRaw = arguments.value("packet") else {
            throw CLIError.usage("ble-send requires --packet\n\n\(CLIArguments.usage)")
        }

        let target = try BLETarget(
            address: arguments.value("address", default: defaultDeviceAddress),
            peripheralID: arguments.value("ble-id"),
            name: arguments.value("name")
        )
        let scanSeconds = try arguments.double("scan-seconds", default: 8.0)
        let listenSeconds = try arguments.double("listen-seconds", default: 2.0)
        let preSendDelay = try arguments.double("pre-send-delay", default: 0.5)
        let packet = try Hex.parseBytes(packetRaw)
        try BLESession(
            target: target,
            packets: [packet],
            scanSeconds: scanSeconds,
            listenSeconds: listenSeconds,
            preSendDelay: preSendDelay,
            interPacketDelay: 0,
            writeWithResponse: arguments.flags.contains("write-with-response"),
            discoverAll: arguments.flags.contains("discover-all")
        ).run()

    case "ble-send-sequence":
        let target = try BLETarget(
            address: arguments.value("address", default: defaultDeviceAddress),
            peripheralID: arguments.value("ble-id"),
            name: arguments.value("name")
        )
        let scanSeconds = try arguments.double("scan-seconds", default: 8.0)
        let listenSeconds = try arguments.double("listen-seconds", default: 2.0)
        let preSendDelay = try arguments.double("pre-send-delay", default: 0.5)
        let interPacketDelay = try arguments.double("inter-packet-delay", default: 0.15)
        let packets = try parsePacketSequence(arguments: arguments)
        try BLESession(
            target: target,
            packets: packets,
            scanSeconds: scanSeconds,
            listenSeconds: listenSeconds,
            preSendDelay: preSendDelay,
            interPacketDelay: interPacketDelay,
            writeWithResponse: arguments.flags.contains("write-with-response"),
            discoverAll: arguments.flags.contains("discover-all")
        ).run()

    case "request-state":
        let device = try BluetoothSession.lookupDevice(
            address: arguments.value("address", default: defaultDeviceAddress),
            name: arguments.value("name")
        )
        let channel = try arguments.uint8("channel", default: defaultRFCOMMChannel)
        let listenSeconds = try arguments.double("listen-seconds", default: 2.0)
        let preSendDelay = try arguments.double("pre-send-delay", default: 0.5)
        let packet = SoundcorePacket.build(command: 0x0101, body: [])
        try BluetoothSession.send(packet: packet, to: device, channelID: channel, listenSeconds: listenSeconds, preSendDelay: preSendDelay)

    case "sync-time":
        let device = try BluetoothSession.lookupDevice(
            address: arguments.value("address", default: defaultDeviceAddress),
            name: arguments.value("name")
        )
        let channel = try arguments.uint8("channel", default: defaultRFCOMMChannel)
        let listenSeconds = try arguments.double("listen-seconds", default: 2.0)
        let preSendDelay = try arguments.double("pre-send-delay", default: 0.5)
        let packet = try buildWakeySyncTimePacket(arguments: arguments)
        try BluetoothSession.send(packet: packet, to: device, channelID: channel, listenSeconds: listenSeconds, preSendDelay: preSendDelay)

    case "send":
        guard let packetRaw = arguments.value("packet") else {
            throw CLIError.usage("send requires --packet\n\n\(CLIArguments.usage)")
        }

        let device = try BluetoothSession.lookupDevice(
            address: arguments.value("address", default: defaultDeviceAddress),
            name: arguments.value("name")
        )
        let channel = try arguments.uint8("channel", default: defaultRFCOMMChannel)
        let listenSeconds = try arguments.double("listen-seconds", default: 2.0)
        let preSendDelay = try arguments.double("pre-send-delay", default: 0.5)
        let packet = try Hex.parseBytes(packetRaw)
        try BluetoothSession.send(packet: packet, to: device, channelID: channel, listenSeconds: listenSeconds, preSendDelay: preSendDelay)

    case "send-sequence":
        let device = try BluetoothSession.lookupDevice(
            address: arguments.value("address", default: defaultDeviceAddress),
            name: arguments.value("name")
        )
        let channel = try arguments.uint8("channel", default: defaultRFCOMMChannel)
        let listenSeconds = try arguments.double("listen-seconds", default: 2.0)
        let preSendDelay = try arguments.double("pre-send-delay", default: 0.5)
        let interPacketDelay = try arguments.double("inter-packet-delay", default: 0.15)
        let packets = try parsePacketSequence(arguments: arguments)
        try BluetoothSession.send(packets: packets, to: device, channelID: channel, listenSeconds: listenSeconds, preSendDelay: preSendDelay, interPacketDelay: interPacketDelay)

    default:
        throw CLIError.usage("Unknown command: \(arguments.command)\n\n\(CLIArguments.usage)")
    }

    return 0
}
