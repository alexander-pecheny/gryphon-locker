import AppKit
import CoreAudio
import IOBluetooth
import ServiceManagement

let deviceName = "iFi Hi-Res Audio"
let heartbeat: TimeInterval = 2
let audioGracePeriod: TimeInterval = 8
let connectTimeout: TimeInterval = 20
let firstRetryDelay: TimeInterval = 1
let maxRetryDelay: TimeInterval = 30

/// The Gryphon links to several sources but streams to one, so only an audio device proves we own it.
func hasAudioOutput(_ device: IOBluetoothDevice) -> Bool {
    guard let address = device.addressString?.lowercased() else { return false }
    let system = AudioObjectID(kAudioObjectSystemObject)
    var property = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size) == noErr else { return false }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(system, &property, 0, nil, &size, &ids) == noErr else { return false }
    property.mSelector = kAudioDevicePropertyDeviceUID
    return ids.contains { id in
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &uidSize, &uid) == noErr, let uid else { return false }
        return (uid.takeRetainedValue() as String).lowercased().hasPrefix(address)
    }
}

final class Locker: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var locked = UserDefaults.standard.bool(forKey: "locked") {
        didSet { UserDefaults.standard.set(locked, forKey: "locked") }
    }
    private var connectingSince: Date?
    private var linkedSince: Date?
    private var nextAttempt = Date.distantPast
    private var retryDelay = firstRetryDelay

    private var device: IOBluetoothDevice? {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?.first { $0.name == deviceName }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        statusItem.menu = menu
        IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(retryNow), name: NSWorkspace.didWakeNotification, object: nil)
        Timer.scheduledTimer(withTimeInterval: heartbeat, repeats: true) { [weak self] _ in self?.enforce() }
        enforce()
    }

    func menuNeedsUpdate(_ menu: NSMenu) { refresh() }

    private func enforce() {
        defer { refresh() }
        guard let device else { return }
        if let since = connectingSince, Date().timeIntervalSince(since) > connectTimeout {
            connectingSince = nil
        }
        guard locked else {
            if device.isConnected() { device.closeConnection() }
            return
        }
        if device.isConnected() {
            let linked = linkedSince ?? Date()
            linkedSince = linked
            if hasAudioOutput(device) {
                retryDelay = firstRetryDelay
            } else if Date().timeIntervalSince(linked) > audioGracePeriod {
                device.closeConnection()
                linkedSince = nil
            }
        } else if connectingSince == nil && Date() >= nextAttempt {
            linkedSince = nil
            connectingSince = Date()
            nextAttempt = Date().addingTimeInterval(retryDelay)
            retryDelay = min(retryDelay * 2, maxRetryDelay)
            let status = device.openConnection(self)
            if status != kIOReturnSuccess { connectingSince = nil }
        }
    }

    @objc(connectionComplete:status:)
    func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        connectingSince = nil
        enforce()
    }

    @objc func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard device.addressString == self.device?.addressString else { return }
        device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
        enforce()
    }

    @objc func disconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        retryNow()
    }

    @objc func retryNow() {
        retryDelay = firstRetryDelay
        nextAttempt = .distantPast
        enforce()
    }

    @objc func toggleLock() {
        locked.toggle()
        retryNow()
    }

    @objc func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func refresh() {
        let device = device
        let linked = device?.isConnected() ?? false
        let audio = device.map(hasAudioOutput) ?? false
        let button = statusItem.button
        button?.image = NSImage(
            systemSymbolName: locked ? "lock.fill" : "lock.open",
            accessibilityDescription: locked ? "Gryphon locked" : "Gryphon unlocked")
        button?.appearsDisabled = !audio

        let status: String
        if device == nil {
            status = "\(deviceName) is not paired"
        } else if audio {
            status = "Gryphon is playing from this Mac"
        } else if locked {
            status = linked ? "Gryphon is busy with another device…" : "Gryphon: connecting…"
        } else {
            status = "Gryphon is not connected"
        }
        menu.removeAllItems()
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        let lock = menu.addItem(withTitle: "Lock to this Mac", action: #selector(toggleLock), keyEquivalent: "")
        lock.target = self
        lock.state = locked ? .on : .off
        let login = menu.addItem(withTitle: "Open at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }
}

let app = NSApplication.shared
let locker = Locker()
app.delegate = locker
app.setActivationPolicy(.accessory)
app.run()
