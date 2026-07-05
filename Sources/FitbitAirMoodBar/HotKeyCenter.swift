import Carbon
import Foundation

final class HotKeyCenter: @unchecked Sendable {
    private static let signature: OSType = 0x4641_4D42
    private static let toggleQuickCheckInID: UInt32 = 1

    private let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        register()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    private func register() {
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

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.toggleQuickCheckInID)
        let keyCodeM: UInt32 = 46
        RegisterEventHotKey(
            keyCodeM,
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func invoke() {
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

        let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
        center.invoke()
        return noErr
    }
}
