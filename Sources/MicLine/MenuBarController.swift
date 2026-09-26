import AppKit
import Combine
import SwiftUI
import MicLineCore

/// Keep meter ticks out of SwiftUI's menu-bar layout. The popover still uses
/// the production SwiftUI controls and the main scene's window actions.
@MainActor
final class MenuBarController: NSObject, ObservableObject {
    private let graph: AudioGraph
    private let fixture: PresentationFixture?
    private let defaults: UserDefaults
    private let images = MenuBarMeterImages()
    private let popover = NSPopover()
    private var item: NSStatusItem?
    private var subscriptions = Set<AnyCancellable>()
    private var appearanceObservation: NSKeyValueObservation?
    private var reading = MenuBarMeterReading(-90)
    private var running = false
    private var openMain: (() -> Void)?
    private var openSettings: (() -> Void)?
    private weak var settingsWindow: NSWindow?
    private var settingsRequested = false

    init(graph: AudioGraph, fixture: PresentationFixture?, defaults: UserDefaults) {
        self.graph = graph
        self.fixture = fixture
        self.defaults = defaults
        super.init()
    }

    func install(openMain: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.openMain = openMain
        self.openSettings = openSettings
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.item = item
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.setAccessibilityLabel("MicLine")
        popover.behavior = .transient
        let content = NSHostingController(rootView: menuContent)
        content.sizingOptions = [.preferredContentSize]
        popover.contentViewController = content

        graph.$running.sink { [weak self] running in
            guard let self else { return }
            self.running = self.fixture == nil && running
            self.refreshImage()
        }.store(in: &subscriptions)
        graph.meterDisplay.$readings.map { MenuBarMeterReading($0.output.rmsDBFS) }
            .removeDuplicates().sink { [weak self] reading in
                self?.reading = reading
                self?.refreshImage()
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshImage() }.store(in: &subscriptions)
        appearanceObservation = item.button?.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshImage() }
        }
    }

    @ViewBuilder private var menuContent: some View {
        if fixture == nil {
            MenuView(graph: graph, openMain: { [weak self] in self?.showMain() },
                openSettings: { [weak self] in self?.showSettings() })
        } else {
            FixtureMenuView(openSettings: { [weak self] in self?.showSettings() })
                .padding(16)
        }
    }

    func showSettings() {
        settingsRequested = true
        popover.performClose(nil)
        // Finish dismissing the transient panel before activating its destination.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.openSettings?()
            self.presentSettingsIfRequested()
        }
    }

    func registerSettingsWindow(_ window: NSWindow) {
        settingsWindow = window
        presentSettingsIfRequested()
    }

    private func presentSettingsIfRequested() {
        guard settingsRequested, let settingsWindow else { return }
        settingsRequested = false
        // SwiftUI may create the Settings window after openSettings returns.
        // Activate once its actual window exists, including when reopening it.
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindow.isMiniaturized { settingsWindow.deminiaturize(nil) }
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    private func showMain() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        openMain?()
    }

    @objc private func togglePopover() {
        guard let button = item?.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }

    private func refreshImage() {
        guard let button = item?.button else { return }
        let colour = defaults.object(forKey: "colourMenuMeter") as? Bool ?? true
        let dark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let image = images.image(segments: running ? reading.segments : 0,
            running: running, colour: colour, dark: dark)
        if button.image !== image { button.image = image }
        button.toolTip = running ? "MicLine · Processing · Output level" : "MicLine · Stopped"
        button.setAccessibilityValue(running
            ? "Processing, output RMS \(reading.rmsDBFS) decibels full scale" : "Stopped")
    }
}

struct MenuBarActions: NSViewRepresentable {
    let controller: MenuBarController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let openWindow = openWindow
        let openSettings = openSettings
        controller.install(openMain: { openWindow(id: "main") }, openSettings: { openSettings() })
    }
}

struct SettingsWindowRegistration: NSViewRepresentable {
    let controller: MenuBarController

    func makeNSView(context: Context) -> SettingsWindowView {
        let view = SettingsWindowView()
        view.register = { [weak controller] in controller?.registerSettingsWindow($0) }
        return view
    }

    func updateNSView(_ view: SettingsWindowView, context: Context) {}
}

final class SettingsWindowView: NSView {
    var register: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            self.register?(window)
        }
    }
}
