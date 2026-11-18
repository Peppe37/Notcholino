// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Carbon.HIToolbox
import Combine

final class PluginShortcuts: ObservableObject {
    static let shared = PluginShortcuts()

    struct Key: Codable {
        let code: UInt32
        let modifiers: UInt32
        let label: String

        func matches(_ other: Key) -> Bool { code == other.code && modifiers == other.modifiers }

        init?(event: NSEvent) {
            let flags = event.modifierFlags
            guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
            var mask: UInt32 = 0
            var symbols = ""
            for (flag, bit, symbol): (NSEvent.ModifierFlags, Int, String) in [
                (.control, controlKey, "⌃"), (.option, optionKey, "⌥"), (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")
            ] where flags.contains(flag) {
                mask |= UInt32(bit)
                symbols += symbol
            }
            let names: [UInt16: String] = [36: "Return", 48: "Tab", 49: "Space", 51: "Delete",
                                             123: "←", 124: "→", 125: "↓", 126: "↑"]
            let characters = event.charactersIgnoringModifiers ?? ""
            let key: String
            if let name = names[event.keyCode] {
                key = name
            } else if let scalar = characters.unicodeScalars.first, (0xF704...0xF717).contains(scalar.value) {
                key = "F\(scalar.value - 0xF704 + 1)"
            } else if !characters.isEmpty, characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                key = characters.uppercased()
            } else {
                return nil
            }
            self.code = UInt32(event.keyCode)
            self.modifiers = mask
            self.label = symbols + " " + key
        }
    }

    private struct Binding: Codable {
        var actionID = "open"
        var key: Key?
    }

    private struct Registration {
        let number: UInt32
        let ref: EventHotKeyRef
    }

    private static let defaultsKey = "pluginShortcuts"
    private static let signature: OSType = 0x4E50_4C47 // NPLG
    private let defaults: UserDefaults
    @Published private var bindings: [String: Binding]
    @Published private(set) var recordingID: String?
    @Published private(set) var errors: [String: String] = [:]
    private var registrations: [String: Registration] = [:]
    private var held: Set<UInt32> = []
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?
    private var localMonitor: Any?
    private var blurObserver: NSObjectProtocol?
    private var appObserver: NSObjectProtocol?
    private var plugins: [NotcholinoPlugin] = []
    private var pluginObserver: AnyCancellable?
    private var open: ((String) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bindings = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([String: Binding].self, from: $0) } ?? [:]
    }

    func start(manager: PluginManager, open: @escaping (String) -> Void) {
        self.open = open
        pluginObserver = manager.$loadedPlugins.sink { [weak self] plugins in self?.sync(plugins) }
        appObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                              object: NSApp, queue: .main) { [weak self] _ in
            self?.restoreHandlerPriority()
        }
    }

    func openPlugin(_ id: String) { open?(id) }

    func key(for id: String) -> Key? { bindings[id]?.key }
    func action(for id: String) -> String { bindings[id]?.actionID ?? "open" }

    func setAction(_ actionID: String, for id: String) {
        let existing = bindings[id] ?? Binding()
        bindings[id] = Binding(actionID: actionID, key: existing.key)
        save()
    }

    func clear(_ id: String) {
        unregister(id)
        bindings[id]?.key = nil
        errors[id] = nil
        save()
        if recordingID == id { stopRecording() }
    }

    func remove(_ id: String) {
        clear(id)
        bindings[id] = nil
        save()
    }

    func record(_ id: String) {
        guard let window = NSApp.keyWindow else { return }
        stopRecording()
        errors[id] = nil
        recordingID = id
        for id in Array(registrations.keys) { unregister(id) }
        blurObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                               object: window, queue: .main) { [weak self] _ in self?.stopRecording() }
        var candidate: Key?
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, event.window === window else { return event }
            if event.type == .keyUp {
                if let key = candidate, key.code == UInt32(event.keyCode) {
                    candidate = nil
                    self.capture(key, for: id)
                }
                return nil
            }
            if event.keyCode == UInt16(kVK_Escape) { self.stopRecording(); return nil }
            guard !event.isARepeat else { return nil }
            candidate = Key(event: event)
            if candidate == nil {
                self.errors[id] = "Press Control, Option or Command with another key. Esc cancels."
            }
            return nil
        }
    }

    func stopRecording() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let blurObserver { NotificationCenter.default.removeObserver(blurObserver); self.blurObserver = nil }
        guard recordingID != nil else { return }
        recordingID = nil
        sync(plugins)
    }

    private func capture(_ key: Key, for id: String) {
        if let conflict = plugins.first(where: { $0.pluginIdentifier != id && bindings[$0.pluginIdentifier]?.key?.matches(key) == true }) {
            errors[id] = "Already assigned to \(conflict.pluginName). Choose another shortcut."
            return
        }
        guard register(key, for: id) else {
            errors[id] = "macOS could not register this combination. Choose another shortcut."
            return
        }
        let existing = bindings[id] ?? Binding()
        bindings[id] = Binding(actionID: existing.actionID, key: key)
        errors[id] = nil
        save()
        stopRecording()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(bindings) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    private func sync(_ plugins: [NotcholinoPlugin]) {
        self.plugins = plugins
        let ids = Set(plugins.map(\.pluginIdentifier))
        for id in Array(registrations.keys) where !ids.contains(id) { unregister(id) }
        guard recordingID == nil else { return }
        for id in ids.sorted() where registrations[id] == nil {
            guard let key = bindings[id]?.key else { continue }
            if register(key, for: id) { errors[id] = nil }
            else { errors[id] = "This shortcut is unavailable. Record another combination." }
        }
    }

    private func installHandler() -> Bool {
        if handler != nil { return true }
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyReleased))
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == PluginShortcuts.signature else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<PluginShortcuts>.fromOpaque(context).takeUnretainedValue()
            let number = id.id
            let pressed = GetEventKind(event) == kEventHotKeyPressed
            DispatchQueue.main.async { manager.handle(number, pressed: pressed) }
            return noErr
        }, events.count, &events, context, &handler)
        return status == noErr
    }

    /// Older Notchy bundles installed their application handler without checking the event signature.
    /// Keep this handler first after leaving Settings, where those bundles can register for the first time.
    private func restoreHandlerPriority() {
        guard !registrations.isEmpty, let handler else { return }
        RemoveEventHandler(handler)
        self.handler = nil
        _ = installHandler()
    }

    private func register(_ key: Key, for plugin: String) -> Bool {
        guard installHandler() else { return false }
        let number = nextID
        nextID &+= 1
        var ref: EventHotKeyRef?
        let result = RegisterEventHotKey(key.code, key.modifiers, EventHotKeyID(signature: Self.signature, id: number),
                                         GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &ref)
        guard result == noErr, let ref else { return false }
        registrations[plugin] = Registration(number: number, ref: ref)
        return true
    }

    private func handle(_ number: UInt32, pressed: Bool) {
        guard pressed else { held.remove(number); return }
        guard recordingID == nil, let id = registrations.first(where: { $0.value.number == number })?.key,
              held.insert(number).inserted, let plugin = plugins.first(where: { $0.pluginIdentifier == id }), let open else { return }
        let actions = PluginShortcutAction.actions(for: plugin)
        (actions.first(where: { $0.id == action(for: id) }) ?? actions[0]).perform(on: plugin, open: open)
    }

    private func unregister(_ plugin: String) {
        guard let registration = registrations.removeValue(forKey: plugin) else { return }
        held.remove(registration.number)
        UnregisterEventHotKey(registration.ref)
    }

    func stop() {
        pluginObserver = nil
        if let appObserver { NotificationCenter.default.removeObserver(appObserver); self.appObserver = nil }
        plugins = []
        stopRecording()
        for id in Array(registrations.keys) { unregister(id) }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
        open = nil
    }
}
