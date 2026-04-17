import Foundation
import AppKit
import Carbon.HIToolbox

/// Global hotkey registration using Carbon's Hot Key API (no external deps).
///
/// Defaults:
///   - ⌃⌥⌘ T → toggle (start/stop) main timer
///   - ⌃⌥⌘ P → pause/resume main timer
///
/// The manager resolves the current running timer via APIClient and dispatches
/// the appropriate action on its MainActor-bound handler.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var refs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    private var onToggle: (() -> Void)?
    private var onPause:  (() -> Void)?

    // Signatures must fit in a 4-char code (OSType).
    private let toggleId: UInt32 = UInt32(bitPattern: Int32(bitPattern: "TLtg".fourCharCode))
    private let pauseId:  UInt32 = UInt32(bitPattern: Int32(bitPattern: "TLps".fourCharCode))

    private init() {}

    func install(toggle: @escaping () -> Void, pause: @escaping () -> Void) {
        self.onToggle = toggle
        self.onPause  = pause

        installHandlerIfNeeded()

        // ⌃⌥⌘ T
        registerHotKey(signature: "TLtg".fourCharCode, id: toggleId,
                       keyCode: UInt32(kVK_ANSI_T),
                       modifiers: UInt32(controlKey | optionKey | cmdKey))
        // ⌃⌥⌘ P
        registerHotKey(signature: "TLps".fourCharCode, id: pauseId,
                       keyCode: UInt32(kVK_ANSI_P),
                       modifiers: UInt32(controlKey | optionKey | cmdKey))
    }

    func uninstall() {
        for ref in refs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        refs.removeAll()
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
        onToggle = nil
        onPause = nil
    }

    // MARK: - Private

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let eventRef, let userData else { return noErr }
                var hkID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard status == noErr else { return status }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in mgr.dispatch(id: hkID.id) }
                return noErr
            },
            1,
            &spec,
            selfPtr,
            &handler
        )
    }

    private func registerHotKey(signature: FourCharCode, id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }

    private func dispatch(id: UInt32) {
        if id == toggleId { onToggle?() }
        if id == pauseId  { onPause?() }
    }
}

private extension String {
    var fourCharCode: FourCharCode {
        var r: FourCharCode = 0
        for ch in utf8.prefix(4) {
            r = (r << 8) | FourCharCode(ch)
        }
        return r
    }
}
