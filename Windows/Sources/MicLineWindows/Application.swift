import Foundation
import WinSDK
import WindowsAudio

private let className = "MicLine.Windows"
private let trayMessage = UINT(WM_APP + 1)

private enum ID: Int32 {
    case input = 101, channel, output, rescan, gain, gainText, lowCut, cutoff
    case cutoffText, bypass, start, quit, inputMeter, outputMeter, inputText
    case outputText, status, cableHelp, privacyHelp
}

private struct Device {
    let id: String, name: String
    let channels: UInt32
    let isInput, isCable: Bool
}

private struct Settings: Codable {
    var inputID: String?
    var outputID: String?
    var channel = 0
    var gainDB = 0.0
    var lowCut = true
    var cutoffHz = 80.0
    var bypass = false

    mutating func validate() {
        if inputID?.isEmpty != false || (inputID?.utf8.count ?? 0) > 2048 { inputID = nil }
        if outputID?.isEmpty != false || (outputID?.utf8.count ?? 0) > 2048 { outputID = nil }
        channel = min(255, max(0, channel))
        gainDB = gainDB.isFinite ? min(12, max(-24, gainDB)) : 0
        cutoffHz = cutoffHz.isFinite ? min(300, max(20, cutoffHz)) : 80
    }
}

private enum LevelMath {
    static func peak(_ value: Float) -> Double {
        guard value.isFinite, value > 0 else { return -90 }
        return max(-90, 20 * log10(Double(value)))
    }
    static func rms(_ value: Float) -> Double {
        guard value.isFinite, value > 0 else { return -90 }
        return max(-90, 20 * log10(Double(value) * sqrt(2)))
    }
}

private struct Ballistics {
    var rms = -90.0, peak = -90.0
    mutating func update(_ r: Float, _ p: Float) {
        func released(_ old: Double, _ new: Double) -> Double { new >= old ? new : max(new, old - 1.176) }
        rms = released(rms, LevelMath.rms(r)); peak = released(peak, LevelMath.peak(p))
    }
    mutating func reset() { self = Ballistics() }
}

private func wide<R>(_ value: String, _ body: (UnsafePointer<WCHAR>) -> R) -> R {
    var units = Array(value.utf16) + [0]
    return units.withUnsafeBufferPointer { body($0.baseAddress!) }
}

private func setText(_ window: HWND?, _ value: String) { wide(value) { _ = SetWindowTextW(window, $0) } }

private final class App {
    var window: HWND?
    var views: [ID: HWND?] = [:]
    var devices: [Device] = []
    var settings = Settings()
    var engine: OpaquePointer?
    var fixture: String?
    var lastState: Int32 = -1
    var inputBallistics = Ballistics(), outputBallistics = Ballistics()
    var tray = NOTIFYICONDATAW(), trayReady = false, quitting = false

    init(fixture: String?) {
        self.fixture = fixture
        if fixture != nil {
            settings.inputID = "fixture-input"; settings.outputID = "fixture-output"
        } else {
            settings = Self.load(); engine = ml_engine_create()
        }
    }

    deinit { if let engine { ml_engine_stop(engine); ml_engine_destroy(engine) } }

    static var settingsURL: URL? {
        ProcessInfo.processInfo.environment["LOCALAPPDATA"].map {
            URL(fileURLWithPath: $0).appendingPathComponent("MicLine/settings.json")
        }
    }

    static func load() -> Settings {
        guard let url = settingsURL, let data = try? Data(contentsOf: url), data.count <= 65_536,
              var result = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        result.validate(); return result
    }

    func save() {
        guard fixture == nil, let url = Self.settingsURL else { return }
        settings.validate()
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(settings)
            if data.count <= 65_536 { try data.write(to: url, options: .atomic) }
        } catch { status("Could not save settings.") }
    }

    func create(title: String) -> Bool {
        var wc = WNDCLASSW()
        wc.style = UINT(CS_HREDRAW | CS_VREDRAW); wc.lpfnWndProc = windowProc
        wc.hInstance = GetModuleHandleW(nil); wc.hCursor = LoadCursorW(nil, IDC_ARROW)
        wc.hbrBackground = HBRUSH(bitPattern: UInt(COLOR_WINDOW + 1))
        let atom = wide(className) { wc.lpszClassName = $0; return RegisterClassW(&wc) }
        guard atom != 0 || GetLastError() == DWORD(ERROR_CLASS_ALREADY_EXISTS) else { return false }
        window = wide(className) { klass in wide(title) { name in
            CreateWindowExW(0, klass, name, DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX),
                Int32(CW_USEDEFAULT), Int32(CW_USEDEFAULT), 620, 560, nil, nil, GetModuleHandleW(nil), nil)
        }}
        guard let window else { return false }
        controls(); _ = SetTimer(window, 1, 100, nil); trayReady = addTray()
        fixture == nil ? scan() : loadFixture()
        ShowWindow(window, SW_SHOW); _ = UpdateWindow(window); return true
    }

    private func add(_ id: ID, _ kind: String, _ title: String, _ style: DWORD,
                     _ x: Int32, _ y: Int32, _ w: Int32, _ h: Int32) {
        views[id] = wide(kind) { klass in wide(title) { text in
            CreateWindowExW(0, klass, text, DWORD(WS_CHILD | WS_VISIBLE) | style, x, y, w, h,
                window, HMENU(bitPattern: UInt(Int(id.rawValue))), GetModuleHandleW(nil), nil)
        }}
    }

    private func label(_ text: String, _ y: Int32, _ width: Int32 = 120) {
        _ = wide("STATIC") { kind in wide(text) { value in
            CreateWindowExW(0, kind, value, DWORD(WS_CHILD | WS_VISIBLE), 24, y, width, 22,
                window, nil, GetModuleHandleW(nil), nil)
        }}
    }

    private func controls() {
        label("Microphone", 22); add(.input, "COMBOBOX", "", DWORD(CBS_DROPDOWNLIST | WS_TABSTOP), 150, 18, 425, 180)
        label("Input channel", 62); add(.channel, "COMBOBOX", "", DWORD(CBS_DROPDOWNLIST | WS_TABSTOP), 150, 58, 160, 160)
        label("Virtual output", 102); add(.output, "COMBOBOX", "", DWORD(CBS_DROPDOWNLIST | WS_TABSTOP), 150, 98, 425, 180)
        add(.cableHelp, "BUTTON", "Get VB-CABLE", DWORD(BS_PUSHBUTTON | WS_TABSTOP), 330, 137, 130, 28)
        add(.rescan, "BUTTON", "Rescan", DWORD(BS_PUSHBUTTON | WS_TABSTOP), 470, 137, 105, 28)
        label("Input level (RMS / sample peak)", 183, 250)
        add(.inputMeter, "msctls_progress32", "", 0, 24, 208, 430, 18)
        add(.inputText, "STATIC", "-90 / -90 dBFS", DWORD(SS_RIGHT), 460, 204, 115, 22)
        label("Output level (RMS / sample peak)", 237, 250)
        add(.outputMeter, "msctls_progress32", "", 0, 24, 262, 430, 18)
        add(.outputText, "STATIC", "-90 / -90 dBFS", DWORD(SS_RIGHT), 460, 258, 115, 22)
        label("Input gain", 306); add(.gain, "msctls_trackbar32", "", DWORD(TBS_AUTOTICKS | WS_TABSTOP), 150, 296, 330, 35)
        add(.gainText, "STATIC", "0 dB", DWORD(SS_RIGHT), 490, 305, 85, 22)
        add(.lowCut, "BUTTON", "Low cut", DWORD(BS_AUTOCHECKBOX | WS_TABSTOP), 24, 350, 110, 25)
        add(.cutoff, "msctls_trackbar32", "", DWORD(TBS_AUTOTICKS | WS_TABSTOP), 150, 342, 330, 35)
        add(.cutoffText, "STATIC", "80 Hz", DWORD(SS_RIGHT), 490, 350, 85, 22)
        add(.bypass, "BUTTON", "Bypass low cut", DWORD(BS_AUTOCHECKBOX | WS_TABSTOP), 24, 390, 170, 25)
        add(.privacyHelp, "BUTTON", "Microphone privacy settings", DWORD(BS_PUSHBUTTON | WS_TABSTOP), 330, 387, 245, 28)
        add(.status, "STATIC", "Stopped", 0, 24, 435, 551, 36)
        add(.start, "BUTTON", "Start", DWORD(BS_DEFPUSHBUTTON | WS_TABSTOP), 335, 485, 110, 32)
        add(.quit, "BUTTON", "Quit", DWORD(BS_PUSHBUTTON | WS_TABSTOP), 465, 485, 110, 32)
        _ = SendMessageW(views[.gain]!, UINT(TBM_SETRANGE), 1, LPARAM(36 << 16))
        _ = SendMessageW(views[.cutoff]!, UINT(TBM_SETRANGE), 1, LPARAM(280 << 16))
        _ = SendMessageW(views[.gain]!, UINT(TBM_SETPOS), 1, LPARAM(Int(settings.gainDB + 24)))
        _ = SendMessageW(views[.cutoff]!, UINT(TBM_SETPOS), 1, LPARAM(Int(settings.cutoffHz - 20)))
        _ = SendMessageW(views[.lowCut]!, UINT(BM_SETCHECK), WPARAM(settings.lowCut ? BST_CHECKED : BST_UNCHECKED), 0)
        _ = SendMessageW(views[.bypass]!, UINT(BM_SETCHECK), WPARAM(settings.bypass ? BST_CHECKED : BST_UNCHECKED), 0)
    }

    func scan() {
        stop(nil); devices.removeAll()
        var error = [CChar](repeating: 0, count: 512)
        guard let list = error.withUnsafeMutableBufferPointer({ ml_devices_create($0.baseAddress, UInt32($0.count)) }) else {
            status(error[0] == 0 ? "Could not enumerate audio endpoints." : String(cString: error)); populate(); return
        }
        defer { ml_devices_destroy(list) }
        for i in 0..<ml_devices_count(list) {
            guard let id = ml_device_id(list, i), let name = ml_device_name(list, i) else { continue }
            devices.append(Device(id: String(cString: id), name: String(cString: name), channels: ml_device_channels(list, i),
                isInput: ml_device_is_input(list, i) != 0, isCable: ml_device_is_cable(list, i) != 0))
        }
        populate(); status(ready ? "Ready — press Start to begin processing." : missingMessage)
    }

    func rescan() { fixture == nil ? scan() : loadFixture() }

    private func loadFixture() {
        devices = [Device(id: "fixture-input", name: "Studio Microphone", channels: 2, isInput: true, isCable: false),
                   Device(id: "fixture-output", name: "CABLE Input (VB-Audio Virtual Cable)", channels: 2, isInput: false, isCable: true)]
        populate()
        switch fixture {
        case "empty": devices = []; populate(); status("No input endpoints found. Connect a microphone and Rescan.")
        case "active": status("Processing — synthetic fixture; no microphone is open."); running(true); meters(-18.4, -10.2, -20.1, -12)
        case "recovery": settings.inputID = "missing"; populate(); status("Stopped — saved microphone is unavailable.")
        default: status("Ready — press Start to begin processing.")
        }
    }

    private func populate() {
        _ = SendMessageW(views[.input]!, UINT(CB_RESETCONTENT), 0, 0); _ = SendMessageW(views[.output]!, UINT(CB_RESETCONTENT), 0, 0)
        for d in inputs { wide(d.name) { _ = SendMessageW(views[.input]!, UINT(CB_ADDSTRING), 0, LPARAM(Int(bitPattern: $0))) } }
        for d in outputs { wide(d.name) { _ = SendMessageW(views[.output]!, UINT(CB_ADDSTRING), 0, LPARAM(Int(bitPattern: $0))) } }
        if let i = inputs.firstIndex(where: { $0.id == settings.inputID }) { _ = SendMessageW(views[.input]!, UINT(CB_SETCURSEL), WPARAM(i), 0) }
        if let i = outputs.firstIndex(where: { $0.id == settings.outputID }) { _ = SendMessageW(views[.output]!, UINT(CB_SETCURSEL), WPARAM(i), 0) }
        populateChannels()
    }

    func populateChannels() {
        _ = SendMessageW(views[.channel]!, UINT(CB_RESETCONTENT), 0, 0)
        guard let input = selectedInput else { return }
        for i in 0..<input.channels { wide("Channel \(i + 1)") { _ = SendMessageW(views[.channel]!, UINT(CB_ADDSTRING), 0, LPARAM(Int(bitPattern: $0))) } }
        settings.channel = min(settings.channel, max(0, Int(input.channels) - 1))
        _ = SendMessageW(views[.channel]!, UINT(CB_SETCURSEL), WPARAM(settings.channel), 0)
    }

    var inputs: [Device] { devices.filter(\.isInput) }
    var outputs: [Device] { devices.filter { !$0.isInput && $0.isCable } }
    var selectedInput: Device? { selection(.input, inputs) }
    var selectedOutput: Device? { selection(.output, outputs) }
    private func selection(_ id: ID, _ list: [Device]) -> Device? {
        let i = Int(SendMessageW(views[id]!, UINT(CB_GETCURSEL), 0, 0)); return list.indices.contains(i) ? list[i] : nil
    }
    var ready: Bool { selectedInput != nil && selectedOutput != nil }
    var missingMessage: String {
        if settings.inputID != nil && selectedInput == nil { return "Stopped — saved microphone is unavailable." }
        if settings.outputID != nil && selectedOutput == nil { return "Stopped — saved VB-CABLE output is unavailable." }
        return "Stopped — choose a microphone and VB-CABLE output."
    }

    func start() {
        guard fixture == nil, let engine, let input = selectedInput, let output = selectedOutput else { return }
        settings.inputID = input.id; settings.outputID = output.id
        settings.channel = max(0, Int(SendMessageW(views[.channel]!, UINT(CB_GETCURSEL), 0, 0))); applyControls()
        let accepted = input.id.utf8CString.withUnsafeBufferPointer { a in
            output.id.utf8CString.withUnsafeBufferPointer { b in ml_engine_start(engine, a.baseAddress, b.baseAddress, UInt32(settings.channel)) }
        }
        if accepted == 0 { status("Could not start the selected route."); return }
        lastState = 1; status("Opening microphone… Press Pause to cancel."); running(true)
    }

    func stop(_ message: String? = "Paused — microphone capture is stopped.") {
        if let engine { ml_engine_stop(engine) }
        lastState = 0; inputBallistics.reset(); outputBallistics.reset(); meters(-90, -90, -90, -90); running(false)
        if let message { status(message) }
    }

    func applyControls() {
        settings.gainDB = Double(SendMessageW(views[.gain]!, UINT(TBM_GETPOS), 0, 0)) - 24
        settings.cutoffHz = Double(SendMessageW(views[.cutoff]!, UINT(TBM_GETPOS), 0, 0)) + 20
        settings.lowCut = SendMessageW(views[.lowCut]!, UINT(BM_GETCHECK), 0, 0) == LRESULT(BST_CHECKED)
        settings.bypass = SendMessageW(views[.bypass]!, UINT(BM_GETCHECK), 0, 0) == LRESULT(BST_CHECKED)
        setText(views[.gainText]!, String(format: "%+.0f dB", settings.gainDB)); setText(views[.cutoffText]!, String(format: "%.0f Hz", settings.cutoffHz))
        if let engine { ml_engine_controls(engine, Float(settings.gainDB), Float(settings.cutoffHz), settings.lowCut ? 1 : 0, settings.bypass ? 1 : 0) }
    }

    func poll() {
        applyControls(); guard fixture == nil, let engine else { return }
        let state = ml_engine_state(engine)
        if state != lastState {
            lastState = state
            if state == 2 { status("Processing — input is routed to VB-CABLE."); running(true) }
            if state == 3 {
                var error = [CChar](repeating: 0, count: 512)
                error.withUnsafeMutableBufferPointer { ml_engine_error(engine, $0.baseAddress, UInt32($0.count)) }
                status(error[0] == 0 ? "Audio stopped with an error. Check microphone privacy settings." : "Stopped — \(String(cString: error))")
                running(false)
            }
        }
        if state == 2 {
            let m = ml_engine_meters(engine); inputBallistics.update(m.input_rms, m.input_peak); outputBallistics.update(m.output_rms, m.output_peak)
            meters(inputBallistics.rms, inputBallistics.peak, outputBallistics.rms, outputBallistics.peak)
        }
    }

    private func meters(_ a: Double, _ ap: Double, _ b: Double, _ bp: Double) {
        func pos(_ dB: Double) -> WPARAM { WPARAM(Int(min(100, max(0, (dB + 60) * 100 / 60)))) }
        _ = SendMessageW(views[.inputMeter]!, UINT(PBM_SETPOS), pos(a), 0); _ = SendMessageW(views[.outputMeter]!, UINT(PBM_SETPOS), pos(b), 0)
        setText(views[.inputText]!, String(format: "%.1f / %.1f dBFS", a, ap)); setText(views[.outputText]!, String(format: "%.1f / %.1f dBFS", b, bp))
    }

    private func running(_ value: Bool) {
        setText(views[.start]!, value ? "Pause" : "Start")
        for id in [ID.input, .channel, .output] { _ = EnableWindow(views[id]!, value ? false : true) }
    }
    private func status(_ value: String) { setText(views[.status]!, value) }

    private func addTray() -> Bool {
        tray.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size); tray.hWnd = window; tray.uID = 1
        tray.uFlags = UINT(NIF_MESSAGE | NIF_ICON | NIF_TIP); tray.uCallbackMessage = trayMessage
        tray.hIcon = LoadIconW(nil, IDI_APPLICATION)
        let value = Array("MicLine".utf16) + [0]
        withUnsafeMutableBytes(of: &tray.szTip) { destination in value.withUnsafeBytes { destination.copyBytes(from: $0.prefix(destination.count)) } }
        return Shell_NotifyIconW(DWORD(NIM_ADD), &tray)
    }

    func trayMenu() {
        let menu = CreatePopupMenu()
        wide("Show") { _ = AppendMenuW(menu, UINT(MF_STRING), 1, $0) }; wide("Pause") { _ = AppendMenuW(menu, UINT(MF_STRING), 2, $0) }
        _ = AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil); wide("Quit") { _ = AppendMenuW(menu, UINT(MF_STRING), 3, $0) }
        var p = POINT(); _ = GetCursorPos(&p); _ = SetForegroundWindow(window)
        let choice = TrackPopupMenu(menu, UINT(TPM_RETURNCMD | TPM_RIGHTBUTTON), p.x, p.y, 0, window, nil); _ = DestroyMenu(menu)
        if choice == 1 { ShowWindow(window, SW_SHOW); _ = SetForegroundWindow(window) }; if choice == 2 { stop() }; if choice == 3 { quit() }
    }

    func open(_ link: String) { wide(link) { _ = ShellExecuteW(window, nil, $0, nil, nil, SW_SHOWNORMAL) } }
    func close() { if trayReady { ShowWindow(window, SW_HIDE) } else { stop("Tray unavailable. Processing paused; use Quit to exit.") } }
    func quit() {
        guard !quitting else { return }; quitting = true; stop(nil); save()
        if trayReady { _ = Shell_NotifyIconW(DWORD(NIM_DELETE), &tray) }; DestroyWindow(window)
    }
}

private var app: App?
private func low(_ value: WPARAM) -> Int32 { Int32(value & 0xffff) }
private func high(_ value: WPARAM) -> Int32 { Int32((value >> 16) & 0xffff) }

private let windowProc: WNDPROC = { hwnd, message, wParam, lParam in
    guard let app else { return DefWindowProcW(hwnd, message, wParam, lParam) }
    switch message {
    case UINT(WM_COMMAND):
        guard let id = ID(rawValue: low(wParam)) else { break }
        if id == .start { app.lastState == 1 || app.lastState == 2 ? app.stop() : app.start() }
        if id == .rescan { app.rescan() }; if id == .quit { app.quit() }
        if id == .cableHelp { app.open("https://vb-audio.com/Cable/") }; if id == .privacyHelp { app.open("ms-settings:privacy-microphone") }
        if id == .input && high(wParam) == CBN_SELCHANGE { app.settings.inputID = app.selectedInput?.id; app.settings.channel = 0; app.populateChannels() }
        if id == .output && high(wParam) == CBN_SELCHANGE { app.settings.outputID = app.selectedOutput?.id }
        return 0
    case UINT(WM_HSCROLL): app.applyControls(); return 0
    case UINT(WM_TIMER): app.poll(); return 0
    case UINT(WM_POWERBROADCAST): if wParam == WPARAM(PBT_APMSUSPEND) { app.stop("Paused after sleep. Press Start when ready.") }; return LRESULT(TRUE)
    case trayMessage:
        if UINT(lParam) == UINT(WM_RBUTTONUP) || UINT(lParam) == UINT(WM_CONTEXTMENU) { app.trayMenu() }
        if UINT(lParam) == UINT(WM_LBUTTONDBLCLK) { ShowWindow(hwnd, SW_SHOW); _ = SetForegroundWindow(hwnd) }; return 0
    case UINT(WM_CLOSE): app.close(); return 0
    case UINT(WM_DESTROY): PostQuitMessage(0); return 0
    default: break
    }
    return DefWindowProcW(hwnd, message, wParam, lParam)
}

@main
enum Application {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--self-test") { exit(selfTest()) }
        let fixture = args.firstIndex(of: "--fixture").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        if let fixture, !["empty", "configured", "active", "recovery"].contains(fixture) { print("Unknown fixture: \(fixture)"); exit(2) }
        let mutex = wide("Local\\MicLine.Windows.Singleton") { CreateMutexW(nil, false, $0) }
        if GetLastError() == DWORD(ERROR_ALREADY_EXISTS) {
            wide(className) { if let old = FindWindowW($0, nil) { ShowWindow(old, SW_SHOW); _ = SetForegroundWindow(old) } }
            if let mutex { _ = CloseHandle(mutex) }; return
        }
        defer { if let mutex { _ = CloseHandle(mutex) } }
        var common = INITCOMMONCONTROLSEX(dwSize: DWORD(MemoryLayout<INITCOMMONCONTROLSEX>.size), dwICC: DWORD(ICC_BAR_CLASSES | ICC_PROGRESS_CLASS)); _ = InitCommonControlsEx(&common)
        app = App(fixture: fixture)
        guard app!.create(title: fixture.map { "MicLine Fixture \($0)" } ?? "MicLine — Windows test build") else { print("Could not create MicLine window"); exit(1) }
        if args.contains("--smoke"), let window = app?.window { _ = SetTimer(window, 99, 2_000, { _, _, _, _ in app?.quit() }) }
        var message = MSG()
        while GetMessageW(&message, nil, 0, 0) > 0 {
            if app?.window == nil || !IsDialogMessageW(app!.window, &message) { _ = TranslateMessage(&message); _ = DispatchMessageW(&message) }
        }
        app = nil
    }

    private static func selfTest() -> Int32 {
        var error = [CChar](repeating: 0, count: 512)
        let audio = error.withUnsafeMutableBufferPointer { ml_audio_self_test($0.baseAddress, UInt32($0.count)) }
        var s = Settings(inputID: String(repeating: "x", count: 3000), outputID: "", channel: -1, gainDB: .infinity, lowCut: true, cutoffHz: 999, bypass: false); s.validate()
        let swift = s.inputID == nil && s.outputID == nil && s.channel == 0 && s.gainDB == 0 && s.cutoffHz == 300 && LevelMath.peak(0) == -90 && abs(LevelMath.rms(1) - 3.0103) < 0.001
        if audio != 0 || !swift { print("MicLine self-test failed: \(audio != 0 && error[0] != 0 ? String(cString: error) : "Swift boundary checks")"); return 1 }
        print("MicLine self-test passed: audio DSP; settings bounds; level math"); return 0
    }
}
