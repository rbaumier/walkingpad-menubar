import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let toggleBelt = Self("toggleBelt")
}

@main
struct WalkingPadApp: App {
    @State private var history: History
    @State private var treadmill: Treadmill
    @AppStorage("dailyStepGoal") private var goal = 10_000
    @AppStorage("startSpeedKmh") private var startSpeedKmh = 5.5

    init() {
        let history = History()
        let treadmill = Treadmill(history: history)
        _history = State(initialValue: history)
        _treadmill = State(initialValue: treadmill)
        let startSpeed = _startSpeedKmh
        KeyboardShortcuts.onKeyUp(for: .toggleBelt) {
            MainActor.assumeIsolated { treadmill.toggle(startSpeedKmh: startSpeed.wrappedValue) }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(goal: $goal, startSpeedKmh: $startSpeedKmh)
                .environment(history)
                .environment(treadmill)
        } label: {
            let steps = history.today.steps.formatted()
            Image(nsImage: menuBarImage(steps: steps))
                .accessibilityLabel("\(steps) steps")
        }
        .menuBarExtraStyle(.window)
    }
}

/// MenuBarExtra ignores font weight on Text, so the icon and the bold count are drawn into one template image.
private func menuBarImage(steps: String) -> NSImage {
    let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .bold)
    let symbol = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: nil)!
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular))!
    let text = NSAttributedString(string: steps, attributes: [.font: font])
    let gap: CGFloat = 4
    let textSize = text.size()
    let size = NSSize(width: symbol.size.width + gap + textSize.width, height: max(symbol.size.height, textSize.height))
    let image = NSImage(size: size, flipped: false) { _ in
        symbol.draw(in: NSRect(origin: NSPoint(x: 0, y: (size.height - symbol.size.height) / 2), size: symbol.size))
        text.draw(at: NSPoint(x: symbol.size.width + gap, y: (size.height - textSize.height) / 2))
        return true
    }
    image.isTemplate = true
    return image
}
