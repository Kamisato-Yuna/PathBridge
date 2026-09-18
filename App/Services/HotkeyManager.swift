import AppKit
import Carbon

@MainActor
final class HotkeyManager {
    nonisolated static let keyCodes: [String: UInt32] = [
        "A":0,"S":1,"D":2,"F":3,"H":4,"G":5,"Z":6,"X":7,"C":8,"V":9,"B":11,
        "Q":12,"W":13,"E":14,"R":15,"Y":16,"T":17,"1":18,"2":19,"3":20,"4":21,
        "6":22,"5":23,"9":25,"7":26,"8":28,"0":29,"O":31,"U":32,"I":34,
        "P":35,"L":37,"J":38,"K":40,"N":45,"M":46
    ]
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var current: HotkeyConfiguration?
    var action: (() -> Void)?

    func register(_ configuration: HotkeyConfiguration) throws {
        if current == configuration { return }
        guard let code = Self.keyCodes[configuration.key] else { throw AppError.message("不支持此快捷键。") }
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated {
                    Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue().action?()
                }
                return noErr
            }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { throw AppError.message("无法安装快捷键处理器（\(status)）。") }
        }
        var modifiers: UInt32 = 0
        if configuration.command { modifiers |= UInt32(cmdKey) }
        if configuration.option { modifiers |= UInt32(optionKey) }
        if configuration.control { modifiers |= UInt32(controlKey) }
        if configuration.shift { modifiers |= UInt32(shiftKey) }
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(code, modifiers, EventHotKeyID(signature: 0x50425247, id: 1), GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr else { throw AppError.message("快捷键 \(configuration.label) 注册失败，可能已被其他应用占用（\(status)）。") }
        if let hotkey { UnregisterEventHotKey(hotkey) }
        hotkey = replacement
        current = configuration
    }
}
