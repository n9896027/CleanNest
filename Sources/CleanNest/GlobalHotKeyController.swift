import Carbon.HIToolbox
import Foundation

@MainActor
final class GlobalHotKeyController {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: () -> Void
    private var requestedEnabled = false
    private var lastRegistrationStatus: OSStatus = noErr

    init(action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let controller = Unmanaged<GlobalHotKeyController>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                Task { @MainActor in controller.action() }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandler
        )
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> OSStatus {
        guard enabled != requestedEnabled else { return lastRegistrationStatus }
        requestedEnabled = enabled
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        guard enabled else {
            lastRegistrationStatus = noErr
            return noErr
        }

        let identifier = EventHotKeyID(signature: OSType(0x434E5354), id: 1) // CNST
        lastRegistrationStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_M),
            UInt32(cmdKey | optionKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        return lastRegistrationStatus
    }
}
