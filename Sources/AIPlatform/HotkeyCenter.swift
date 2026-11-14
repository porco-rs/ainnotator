import AppKit
import Carbon.HIToolbox

/// Global hotkeys through Carbon: no permission needed.
@MainActor public final class HotkeyCenter {
    private static var handler: EventHandlerRef?
    private static var actions: [UInt32: () -> Void] = [:]
    private static let signature = OSType(0x4149_4E4E)  // "AINN"

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1

    public init() {
        guard Self.handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            guard status == noErr, id.signature == HotkeyCenter.signature else { return OSStatus(eventNotHandledErr) }
            let value = id.id
            // Carbon delivers on the main thread. Calling directly keeps a runloop hop out of the hot path.
            MainActor.assumeIsolated { HotkeyCenter.actions[value]?() }
            return noErr
        }, 1, &spec, nil, &Self.handler)
    }

    /// Returns nil if the system refuses the combination; the caller reports the collision. The id releases the key.
    @discardableResult
    public func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) -> UInt32? {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return nil }
        refs[id] = ref
        Self.actions[id] = action
        return id
    }

    public func unregister(_ id: UInt32) {
        guard let ref = refs.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(ref)
        Self.actions[id] = nil
    }

    public static let optionShift = optionKey | shiftKey
    public static let keyA = kVK_ANSI_A
    public static let keyR = kVK_ANSI_R
}
