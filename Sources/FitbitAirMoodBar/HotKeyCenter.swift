import Carbon
import Foundation
import os.log

final class HotKeyCenter: @unchecked Sendable {
    struct Registration {
        let keyCode: UInt32
        let modifiers: UInt32
        let action: @MainActor () -> Void
    }

    static let controlOption = UInt32(controlKey | optionKey)

    private static let signature: OSType = 0x4641_4D42

    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?

    init(registrations: [Registration]) {
        register(registrations)
    }

    deinit {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    private func register(_ registrations: [Registration]) {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleHotKey,
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )
        guard installStatus == noErr else { return }

        for (index, registration) in registrations.enumerated() {
            let id = UInt32(index + 1)
            actions[id] = registration.action

            let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                registration.keyCode,
                registration.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr, let hotKeyRef {
                hotKeyRefs.append(hotKeyRef)
            } else {
                // Usually means another app owns the combination.
                os_log(
                    .error,
                    "HotKeyCenter: registering hotkey %d (keyCode %d) failed with status %d",
                    id,
                    registration.keyCode,
                    status
                )
            }
        }
    }

    private func invoke(id: UInt32) {
        guard let action = actions[id] else { return }
        Task { @MainActor in
            action()
        }
    }

    private static let handleHotKey: EventHandlerUPP = { _, event, userData in
        guard
            let event,
            let userData,
            GetEventKind(event) == UInt32(kEventHotKeyPressed)
        else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else {
            return OSStatus(eventNotHandledErr)
        }

        let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
        center.invoke(id: hotKeyID.id)
        return noErr
    }
}
