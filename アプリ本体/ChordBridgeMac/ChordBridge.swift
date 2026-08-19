import AppKit
import ApplicationServices
import UniformTypeIdentifiers

final class MIDIBridgeView: NSView, NSDraggingSource {
    var onFileReceived: ((URL) -> Void)?
    private(set) var fileURL: URL?
    private var dragStart: NSPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.65).cgColor
        layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.08).cgColor
        registerForDraggedTypes([.fileURL])
        toolTip = "CubaseとLogicの間で渡すMIDIまたはオーディオファイルを置きます"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let title: String
        let subtitle: String
        if let fileURL {
            title = fileURL.lastPathComponent
            subtitle = "このカードをCubaseまたはLogicのトラック領域へドラッグ"
        } else {
            title = "MIDI／オーディオをここへドロップ"
            subtitle = "MIDI、WAV、AIFFなどのファイルを受け取れます"
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]

        let titleRect = NSRect(x: 18, y: bounds.midY + 4, width: bounds.width - 36, height: 26)
        let subtitleRect = NSRect(x: 18, y: bounds.midY - 28, width: bounds.width - 36, height: 22)
        title.draw(in: titleRect, withAttributes: titleAttributes)
        subtitle.draw(in: subtitleRect, withAttributes: subtitleAttributes)
    }

    func setFile(_ url: URL) {
        fileURL = url
        needsDisplay = true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard supportedURL(from: sender.draggingPasteboard) != nil else { return [] }
        layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.18).cgColor
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.08).cgColor
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.08).cgColor
        guard let url = supportedURL(from: sender.draggingPasteboard) else { return false }
        setFile(url)
        onFileReceived?(url)
        return true
    }

    private func supportedURL(from pasteboard: NSPasteboard) -> URL? {
        guard let items = pasteboard.pasteboardItems else { return nil }
        for item in items {
            guard let value = item.string(forType: .fileURL),
                  let url = URL(string: value) else { continue }
            let ext = url.pathExtension.lowercased()
            if ["mid", "midi", "wav", "wave", "aif", "aiff", "caf", "m4a", "mp3"].contains(ext) {
                return url
            }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let fileURL, dragStart != nil else { return }

        let item = NSPasteboardItem()
        item.setString(fileURL.absoluteString, forType: .fileURL)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)

        let image = NSImage(size: NSSize(width: 260, height: 54))
        image.lockFocus()
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 260, height: 54), xRadius: 10, yRadius: 10).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        fileURL.lastPathComponent.draw(in: NSRect(x: 12, y: 18, width: 236, height: 20), withAttributes: attributes)
        image.unlockFocus()

        draggingItem.setDraggingFrame(NSRect(origin: .zero, size: image.size), contents: image)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
        dragStart = nil
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

final class MainViewController: NSViewController {
    private let statusLabel = NSTextField(labelWithString: "1. Cubaseでコードをまとめる　2. LogicからMIDIまたはオーディオを書き出す")
    private let bridgeView = MIDIBridgeView(frame: .zero)
    private let automationButton = NSButton(title: "① 選んだトラックのコードを一つにまとめる", target: nil, action: nil)
    private let logicMIDIButton = NSButton(title: "MIDIで受け取る", target: nil, action: nil)
    private let logicAudioButton = NSButton(title: "オーディオで受け取る（WAV／AIFF）", target: nil, action: nil)
    private let openLogicButton = NSButton(title: "Logic Proを開く", target: nil, action: nil)
    private let chooseButton = NSButton(title: "ファイルを選ぶ…", target: nil, action: nil)
    private let copyButton = NSButton(title: "ファイルをコピー", target: nil, action: nil)
    private let revealButton = NSButton(title: "Finderに表示", target: nil, action: nil)

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 580, height: 560))
        setupUI()
    }

    private func setupUI() {
        let title = NSTextField(labelWithString: "Cubase ⇄ Logic  Chord Bridge")
        title.font = .systemFont(ofSize: 24, weight: .bold)

        let explanation = NSTextField(wrappingLabelWithString:
            "Cubaseでコードが横に並んでいるトラック名を一回クリックし、①を押します。全コードが順番と長さを保った一つのMIDIパートになります。")
        explanation.textColor = .secondaryLabelColor
        explanation.font = .systemFont(ofSize: 13)

        let cubaseHeading = sectionHeading("Cubase → Logic｜まずコードを一つにまとめる")
        automationButton.bezelStyle = .rounded
        automationButton.controlSize = .large
        automationButton.target = self
        automationButton.action = #selector(glueSelectedCubaseParts)

        let logicHeading = sectionHeading("Logic → Cubase｜自動演奏を受け取る")
        let logicExplanation = NSTextField(wrappingLabelWithString:
            "Logicで渡したいリージョンを選び、下のどちらかを押します。MIDIは必要ならSession Playerを自動変換し、オーディオはLogicの音色とエフェクトを含めて書き出します。")
        logicExplanation.textColor = .secondaryLabelColor
        logicExplanation.font = .systemFont(ofSize: 12)

        logicMIDIButton.bezelStyle = .rounded
        logicMIDIButton.controlSize = .large
        logicMIDIButton.target = self
        logicMIDIButton.action = #selector(exportLogicMIDI)
        logicAudioButton.bezelStyle = .rounded
        logicAudioButton.controlSize = .large
        logicAudioButton.target = self
        logicAudioButton.action = #selector(exportLogicAudio)

        openLogicButton.target = self
        openLogicButton.action = #selector(openLogic)
        chooseButton.target = self
        chooseButton.action = #selector(chooseFile)
        copyButton.target = self
        copyButton.action = #selector(copyFile)
        copyButton.isEnabled = false
        revealButton.target = self
        revealButton.action = #selector(revealMIDI)
        revealButton.isEnabled = false

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2

        bridgeView.translatesAutoresizingMaskIntoConstraints = false
        bridgeView.onFileReceived = { [weak self] url in
            self?.acceptedFile(url)
        }

        let receiveRow = NSStackView(views: [logicMIDIButton, logicAudioButton])
        receiveRow.orientation = .horizontal
        receiveRow.distribution = .fillEqually
        receiveRow.spacing = 10
        let buttonRow = NSStackView(views: [openLogicButton, chooseButton, copyButton, revealButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let stack = NSStackView(views: [
            title,
            explanation,
            cubaseHeading,
            automationButton,
            logicHeading,
            logicExplanation,
            receiveRow,
            bridgeView,
            buttonRow,
            statusLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20),
            title.widthAnchor.constraint(equalTo: stack.widthAnchor),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            cubaseHeading.widthAnchor.constraint(equalTo: stack.widthAnchor),
            automationButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            logicHeading.widthAnchor.constraint(equalTo: stack.widthAnchor),
            logicExplanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            receiveRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bridgeView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bridgeView.heightAnchor.constraint(equalToConstant: 104),
            buttonRow.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func sectionHeading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private func checkAccessibility() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        if !trusted {
            statusLabel.stringValue =
                "アクセシビリティ許可が必要です。システム設定でChord Bridgeを許可してから、もう一度押してください。"
        }
        return trusted
    }

    @objc private func glueSelectedCubaseParts() {
        guard checkAccessibility() else { return }

        automationButton.isEnabled = false
        statusLabel.stringValue = "選んだトラックのコードパートを結合しています…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = CubaseAutomation.glueSelectedParts()
            DispatchQueue.main.async {
                self?.automationButton.isEnabled = true
                switch result {
                case .success:
                    self?.statusLabel.stringValue =
                        "一つのMIDIパートにまとめました。順番と長さは維持されています。できた一つのパートを受渡カードへドラッグしてください。"
                case .failure(let message):
                    self?.statusLabel.stringValue = message
                }
            }
        }
    }

    @objc private func exportLogicMIDI() {
        guard checkAccessibility() else { return }
        logicMIDIButton.isEnabled = false
        statusLabel.stringValue = "LogicのMIDI書き出し画面を開いています…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = LogicAutomation.openMIDIExportDialog()
            DispatchQueue.main.async {
                self?.logicMIDIButton.isEnabled = true
                switch result {
                case .success:
                    self?.statusLabel.stringValue =
                        "MIDIの保存画面を開きました。保存後、ファイルをカードへ入れてCubaseへドラッグしてください。"
                case .failure(let message):
                    self?.statusLabel.stringValue = message
                }
            }
        }
    }

    @objc private func exportLogicAudio() {
        guard checkAccessibility() else { return }
        logicAudioButton.isEnabled = false
        statusLabel.stringValue = "Logicのオーディオ書き出し画面を開いています…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = LogicAutomation.openAudioExportDialog()
            DispatchQueue.main.async {
                self?.logicAudioButton.isEnabled = true
                switch result {
                case .success:
                    self?.statusLabel.stringValue =
                        "オーディオの保存画面を開きました。WAVまたはAIFFで保存し、カードへ入れてCubaseへドラッグしてください。"
                case .failure(let message):
                    self?.statusLabel.stringValue = message
                }
            }
        }
    }

    @objc private func openLogic() {
        let candidates = [
            URL(fileURLWithPath: "/Applications/Logic Pro.app"),
            URL(fileURLWithPath: "/Applications/Logic Pro 12.app")
        ]
        if let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else {
            statusLabel.stringValue = "Logic ProがApplicationsフォルダに見つかりませんでした。"
        }
    }

    @objc private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.midi, .audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            bridgeView.setFile(url)
            acceptedFile(url)
        }
    }

    @objc private func revealMIDI() {
        guard let url = bridgeView.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func copyFile() {
        guard let url = bridgeView.fileURL else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if ["mid", "midi"].contains(url.pathExtension.lowercased()),
           let data = try? Data(contentsOf: url) {
            item.setData(data, forType: NSPasteboard.PasteboardType("public.midi-audio"))
        }
        pasteboard.writeObjects([item])

        statusLabel.stringValue =
            "ファイルをコピーしました。貼り付けできない場合は、カードからCubaseまたはLogicへドラッグしてください。"
    }

    private func acceptedFile(_ url: URL) {
        copyButton.isEnabled = true
        revealButton.isEnabled = true
        statusLabel.stringValue =
            "受け取りました。このカードをCubaseまたはLogicのトラック領域へドラッグしてください。"
    }
}

enum CubaseAutomation {
    enum Result {
        case success
        case failure(String)
    }

    static func glueSelectedParts() -> Result {
        let source = """
        tell application "System Events"
            set cubaseProcesses to every application process whose name contains "Cubase"
            if (count of cubaseProcesses) is 0 then error "Cubase 15を起動してください。"
            set cubaseProcess to item 1 of cubaseProcesses
            set frontmost of cubaseProcess to true
            delay 0.4

            tell cubaseProcess
                try
                    click menu bar item "編集" of menu bar 1
                    delay 0.2
                    click menu item "選択トラック上の全イベントを選択" of menu 1 of menu item "選択" of menu 1 of menu bar item "編集" of menu bar 1
                on error
                    error "Cubaseで、コードが並んでいるトラック名を一回クリックしてから、もう一度押してください。"
                end try

                delay 0.3
                try
                    click menu bar item "編集" of menu bar 1
                    delay 0.2
                    click menu item "のり" of menu 1 of menu bar item "編集" of menu bar 1
                on error
                    error "選んだトラックに、結合できるコードパートが2つ以上ありません。コードが横に並ぶトラックを選んでください。"
                end try
            end tell
        end tell
        """

        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return .failure("Cubase操作スクリプトを作成できませんでした。")
        }
        script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? "Cubaseの自動操作に失敗しました。"
            return .failure(message)
        }
        return .success
    }
}

enum LogicAutomation {
    enum Result {
        case success
        case failure(String)
    }

    static func openMIDIExportDialog() -> Result {
        guard let logic = logicApplication() else {
            return .failure("Logic Proが開いていません。")
        }
        guard let region = selectedRegion(pid: logic.processIdentifier),
              let regionPoint = elementCenter(region),
              openContextMenu(at: regionPoint, preferredElement: region) else {
            return .failure("Logicで渡したいリージョンの中央を一度クリックしてから、もう一度押してください。")
        }
        if !pressMenuItem(pid: logic.processIdentifier,
                          containing: ["MIDIリージョンに変換"]) {
            dismissMenu()
        }
        Thread.sleep(forTimeInterval: 0.6)

        click(at: regionPoint, button: .left)
        Thread.sleep(forTimeInterval: 0.25)
        guard openContextMenu(at: regionPoint) else {
            return .failure("MIDI化後の演奏リージョンを選択できませんでした。もう一度、元のSession Playerリージョンを選んでください。")
        }
        if pressMenuItem(pid: logic.processIdentifier,
                         containing: ["MIDIファイルとして"]) {
            return .success
        }
        dismissMenu()
        return .failure("選択したリージョンをMIDIで書き出せません。Logicのリージョン中央を一度クリックしてください。")
    }

    static func openAudioExportDialog() -> Result {
        guard let logic = logicApplication() else {
            return .failure("Logic Proが開いていません。")
        }
        guard let region = selectedRegion(pid: logic.processIdentifier),
              let regionPoint = elementCenter(region),
              openContextMenu(at: regionPoint, preferredElement: region) else {
            return .failure("Logicでオーディオ化したいリージョンの中央を一度クリックしてから、もう一度押してください。")
        }
        if pressMenuItem(pid: logic.processIdentifier,
                         containing: ["リージョン", "オーディオファイルとして"]) {
            return .success
        }
        if pressMenuItem(pid: logic.processIdentifier, containing: ["書き出す"]) {
            Thread.sleep(forTimeInterval: 0.35)
            if pressMenuItem(pid: logic.processIdentifier,
                             containing: ["リージョン", "オーディオファイルとして"]) {
                return .success
            }
        }
        dismissMenu()
        return .failure("選択したリージョンをオーディオで書き出せません。Logicのリージョン中央を一度クリックしてください。")
    }

    private static func openContextMenu(at point: CGPoint,
                                        preferredElement: AXUIElement? = nil) -> Bool {
        guard let logic = logicApplication() else { return false }
        logic.activate(options: [.activateIgnoringOtherApps])
        Thread.sleep(forTimeInterval: 0.35)
        if let preferredElement,
           AXUIElementPerformAction(preferredElement, kAXShowMenuAction as CFString) == .success {
            Thread.sleep(forTimeInterval: 0.45)
            return true
        }
        click(at: point, button: .right)
        Thread.sleep(forTimeInterval: 0.45)
        return true
    }

    private static func click(at point: CGPoint, button: CGMouseButton) {
        let downType: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: button)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: downType,
                mouseCursorPosition: point, mouseButton: button)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: upType,
                mouseCursorPosition: point, mouseButton: button)?.post(tap: .cghidEventTap)
    }

    private static func logicApplication() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.logic10").first
    }

    private static func focusedElement(pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef else { return nil }
        return unsafeBitCast(focusedRef, to: AXUIElement.self)
    }

    private static func selectedRegion(pid: pid_t) -> AXUIElement? {
        let root = AXUIElementCreateApplication(pid)
        var visited = 0
        return findSelectedRegion(in: root, depth: 0, visited: &visited)
    }

    private static func findSelectedRegion(in element: AXUIElement,
                                           depth: Int,
                                           visited: inout Int) -> AXUIElement? {
        guard depth < 18, visited < 8000 else { return nil }
        visited += 1

        var selectedRef: CFTypeRef?
        var helpRef: CFTypeRef?
        var descriptionRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSelectedAttribute as CFString, &selectedRef)
        AXUIElementCopyAttributeValue(element, kAXHelpAttribute as CFString, &helpRef)
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descriptionRef)
        let selected = selectedRef as? Bool ?? false
        let searchableText = [
            helpRef as? String ?? "",
            descriptionRef as? String ?? ""
        ].joined(separator: " ")
        if selected,
           searchableText.localizedStandardContains("リージョン"),
           elementCenter(element) != nil {
            return element
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }
        for child in children {
            if let found = findSelectedRegion(in: child, depth: depth + 1,
                                              visited: &visited) {
                return found
            }
        }
        return nil
    }

    private static func elementCenter(_ focused: AXUIElement) -> CGPoint? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(
                focused, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(positionRef, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeBitCast(sizeRef, to: AXValue.self), .cgSize, &size),
              size.width > 20, size.height > 10 else { return nil }
        return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
    }

    private static func pressMenuItem(pid: pid_t, containing fragments: [String]) -> Bool {
        let root = AXUIElementCreateApplication(pid)
        var visited = 0
        var searchRoots: [AXUIElement] = []
        if var current = focusedElement(pid: pid) {
            for _ in 0..<10 {
                searchRoots.append(current)
                var parentRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    current, kAXParentAttribute as CFString, &parentRef) == .success,
                      let parentRef else { break }
                current = unsafeBitCast(parentRef, to: AXUIElement.self)
            }
        }
        searchRoots.append(root)

        var item: AXUIElement?
        for searchRoot in searchRoots {
            item = findMenuItem(in: searchRoot, containing: fragments,
                                depth: 0, visited: &visited)
            if item != nil { break }
        }
        guard let item else {
            return false
        }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    private static func findMenuItem(in element: AXUIElement,
                                     containing fragments: [String],
                                     depth: Int,
                                     visited: inout Int) -> AXUIElement? {
        guard depth < 14, visited < 6000 else { return nil }
        visited += 1

        var roleRef: CFTypeRef?
        var titleRef: CFTypeRef?
        var enabledRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledRef)
        let role = roleRef as? String
        let title = titleRef as? String ?? ""
        let enabled = enabledRef as? Bool ?? true
        if role == kAXMenuItemRole,
           enabled,
           fragments.allSatisfy({ title.localizedStandardContains($0) }) {
            return element
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }
        for child in children {
            if let found = findMenuItem(in: child, containing: fragments,
                                        depth: depth + 1, visited: &visited) {
                return found
            }
        }
        return nil
    }

    private static func dismissMenu() {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)?
            .post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)?
            .post(tap: .cghidEventTap)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = MainViewController()
        let window = NSWindow(contentViewController: controller)
        window.title = "Chord Bridge"
        window.setContentSize(NSSize(width: 580, height: 560))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
