@preconcurrency import CoreBluetooth
import Observation

enum Connection {
    case bluetoothUnavailable
    case searching
    case connecting
    case connected
}

/// Finds the WalkingPad, keeps the link up, polls its status and sends the user's commands.
@Observable @MainActor final class Treadmill: NSObject {
    private(set) var connection = Connection.searching
    private(set) var status: PadStatus?

    @ObservationIgnored private let history: History
    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    // Latest user intent wins: a new tap replaces commands not sent yet.
    @ObservationIgnored private var pending: [PadCommand] = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var speedOnStartKmh: Double?

    private static let service = CBUUID(string: "FE00")
    private static let notifyCharacteristic = CBUUID(string: "FE01")
    private static let writeCharacteristic = CBUUID(string: "FE02")

    init(history: History) {
        self.history = history
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func toggle(startSpeedKmh: Double) {
        guard connection == .connected, let status else { return }
        if status.isBeltMoving { stop() } else { start(atKmh: startSpeedKmh) }
    }

    private func start(atKmh speed: Double) {
        pending = [.setMode(.manual), .startBelt]
        speedOnStartKmh = speed
    }

    private func stop() {
        pending = [.setMode(.standby)]
        speedOnStartKmh = nil
    }

    private func scan() {
        dropLink()
        connection = .searching
        central.scanForPeripherals(withServices: [Self.service])
    }

    /// Bluetooth turning off doesn't call `didDisconnectPeripheral`, so both paths clear the link here.
    private func dropLink() {
        pollTask?.cancel()
        pollTask = nil
        pending = []
        speedOnStartKmh = nil
        status = nil
    }

    private func startPolling(_ peripheral: CBPeripheral, through characteristic: CBCharacteristic) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled, let self {
                let command = pending.isEmpty ? PadCommand.askStatus : pending.removeFirst()
                peripheral.writeValue(command.frame, for: characteristic, type: .withoutResponse)
                // The pad drops commands sent less than ~0.7 s apart (ph4-walkingpad).
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }
}

// The central runs on the main queue, so every delegate callback is already on the main actor.
extension Treadmill: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            guard central.state == .poweredOn else {
                dropLink()
                connection = .bluetoothUnavailable
                return
            }
            scan()
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) {
        // FE00 is a shared member UUID, so also check the KingSmith name (KS-ST-A1P, WalkingPad…).
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        guard name.hasPrefix("KS-") || name.hasPrefix("WalkingPad") else { return }
        MainActor.assumeIsolated {
            central.stopScan()
            self.peripheral = peripheral
            connection = .connecting
            central.connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            peripheral.delegate = self
            peripheral.discoverServices([Self.service])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { scan() }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { scan() }
    }
}

extension Treadmill: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else {
                central.cancelPeripheralConnection(peripheral)
                return
            }
            peripheral.discoverCharacteristics([Self.notifyCharacteristic, Self.writeCharacteristic], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            let characteristics = service.characteristics ?? []
            guard error == nil,
                  let notify = characteristics.first(where: { $0.uuid == Self.notifyCharacteristic }),
                  let write = characteristics.first(where: { $0.uuid == Self.writeCharacteristic })
            else {
                central.cancelPeripheralConnection(peripheral)
                return
            }
            peripheral.setNotifyValue(true, for: notify)
            startPolling(peripheral, through: write)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard error == nil, characteristic.isNotifying else {
                central.cancelPeripheralConnection(peripheral)
                return
            }
            connection = .connected
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            // Other replies (history, preferences) are not used yet.
            guard let frame = characteristic.value, let status = PadStatus(frame: frame) else { return }
            self.status = status
            history.record(status)
            // Sent once the belt runs: a speed sent during the start countdown may be dropped.
            if status.belt == .running, let speed = speedOnStartKmh {
                pending.append(.setSpeed(kmh: speed))
                speedOnStartKmh = nil
            }
        }
    }
}
