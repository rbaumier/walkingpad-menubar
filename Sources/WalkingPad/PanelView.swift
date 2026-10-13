import KeyboardShortcuts
import SwiftUI

// "Galet" theme: a polished pebble set in a groove, warm off-white and sage.
private extension Color {
    static let ink = Color(red: 0.224, green: 0.166, blue: 0.119)
    static let muted = Color(red: 0.457, green: 0.401, blue: 0.339)
    static let searching = Color(red: 0.909, green: 0.632, blue: 0.153)
    static let groove = Color(red: 0.957, green: 0.931, blue: 0.896)
    static let warmShadow = Color(red: 0.405, green: 0.316, blue: 0.212)
    static let goLight = Color(red: 0.424, green: 0.761, blue: 0.604)
    static let goDark = Color(red: 0.227, green: 0.612, blue: 0.455)
    static let stopLight = Color(red: 0.933, green: 0.416, blue: 0.361)
    static let stopDark = Color(red: 0.816, green: 0.278, blue: 0.235)
    static let ringLight = Color(red: 0.533, green: 0.791, blue: 0.586)
    static let ringDark = Color(red: 0.067, green: 0.585, blue: 0.488)
    static let ringDeep = Color(red: 0.02, green: 0.42, blue: 0.36)
}

private let goalStepsRange = 1_000...50_000

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

struct PanelView: View {
    @Environment(Treadmill.self) private var treadmill
    @Environment(History.self) private var history
    @Binding var goal: Int
    @Binding var startSpeedKmh: Double
    @State private var isShowingSettings = false

    var body: some View {
        let today = history.today
        let isRunning = treadmill.status?.isBeltMoving == true
        VStack(spacing: 14) {
            header
            StepRing(steps: today.steps, goal: goal.clamped(to: goalStepsRange), isRunning: isRunning)
            Text(Duration.seconds(today.activeSeconds).formatted(.time(pattern: .hourMinuteSecond)))
                .font(.system(size: 28, weight: .bold).monospacedDigit())
                .accessibilityLabel("Active time today")
                .accessibilityValue(Duration.seconds(today.activeSeconds).formatted(.units(allowed: [.hours, .minutes, .seconds])))
            if let problem = treadmill.connection.problem {
                // Takes the button's place: there is nothing to start until the pad is connected.
                Label {
                    Text(problem)
                } icon: {
                    Circle().fill(Color.searching).frame(width: 8, height: 8)
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.muted)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(Color.groove.shadow(.inner(color: .warmShadow.opacity(0.22), radius: 3, y: 2))))
            } else {
                toggleButton(isRunning: isRunning)
            }
        }
        .padding(18)
        .frame(width: 300)
        .foregroundStyle(Color.ink)
        .fontDesign(.rounded)
        .background(
            RadialGradient(
                colors: [Color(red: 0.997, green: 0.989, blue: 0.975), Color(red: 0.973, green: 0.946, blue: 0.911)],
                center: .top, startRadius: 0, endRadius: 380
            )
        )
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack {
            Spacer()
            Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                // The panel gives this first button keyboard focus on open; focusEffectDisabled alone still drew the ring.
                .focusable(false)
                .font(.system(size: 15))
                .foregroundStyle(Color.muted)
                .popover(isPresented: $isShowingSettings, arrowEdge: .bottom) {
                    SettingsView(goal: $goal, startSpeedKmh: $startSpeedKmh)
                }
        }
        .accessibilityElement(children: .contain)
    }

    /// Raised green pebble while stopped; pressed into the panel, red, while the belt runs.
    private func toggleButton(isRunning: Bool) -> some View {
        Button {
            treadmill.toggle(startSpeedKmh: startSpeedKmh)
        } label: {
            Label(isRunning ? "Stop" : "Start", systemImage: isRunning ? "stop.fill" : "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    if isRunning {
                        Capsule()
                            .fill(
                                LinearGradient(colors: [.stopDark, .stopLight], startPoint: .top, endPoint: .bottom)
                                    .shadow(.inner(color: Color(red: 0.31, green: 0.04, blue: 0).opacity(0.35), radius: 4, x: 3, y: 4))
                                    .shadow(.inner(color: .white.opacity(0.2), radius: 2.5, x: -2, y: -2))
                            )
                            .offset(y: 1)
                            .background(
                                Capsule()
                                    .fill(Color.groove)
                                    .padding(-4)
                                    .overlay(Capsule().stroke(Color.warmShadow.opacity(0.08)).padding(-4.5))
                            )
                    } else {
                        Capsule()
                            .fill(
                                LinearGradient(colors: [.goLight, .goDark], startPoint: .top, endPoint: .bottom)
                                    .shadow(.inner(color: .white.opacity(0.35), radius: 2, x: 1, y: 1.5))
                            )
                            .shadow(color: .white, radius: 6, x: -4, y: -4)
                            .shadow(color: .warmShadow.opacity(0.3), radius: 7, x: 4, y: 5)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: isRunning)
    }
}

struct StepRing: View {
    let steps: Int
    let goal: Int
    let isRunning: Bool

    private let size = 200.0
    private let trackRadius = 82.0
    private let lineWidth = 18.0

    var body: some View {
        // Past the goal the ring keeps going round, like Apple's activity rings.
        let progress = Double(steps) / Double(goal)
        ZStack {
            Circle()
                .fill(Color.groove.shadow(.inner(color: .warmShadow.opacity(0.22), radius: 4, y: 3)))
                .padding(4)
            arc(to: min(progress, 1), colors: [.ringLight, .ringDark])
            if progress > 1 {
                // Shadow only under the tip, which the arc's round cap then covers: the lap looks laid over the first one.
                Circle()
                    .fill(Color.ringDark)
                    .frame(width: lineWidth, height: lineWidth)
                    .shadow(color: .black.opacity(0.5), radius: 4)
                    .offset(y: -trackRadius)
                    .rotationEffect(.degrees(progress * 360))
                arc(to: progress.truncatingRemainder(dividingBy: 1), colors: [.ringDark, .ringDeep])
            }
            Circle()
                .fill(.white)
                .frame(width: 12, height: 12)
                .shadow(color: .warmShadow.opacity(0.35), radius: 2, y: 1)
                // Scoped to the knob: a repeatForever transaction started in onAppear also animates the panel's layout.
                .phaseAnimator(isRunning ? [1, 1.25] : [1]) { knob, scale in
                    knob.scaleEffect(scale)
                } animation: { _ in
                    .easeInOut(duration: 0.7)
                }
                .offset(y: -trackRadius)
                .rotationEffect(.degrees(progress * 360))
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.999, green: 0.993, blue: 0.982), Color(red: 0.971, green: 0.944, blue: 0.909)],
                        center: UnitPoint(x: 0.35, y: 0.25), startRadius: 0, endRadius: 136
                    )
                )
                .shadow(color: .warmShadow.opacity(0.22), radius: 9, y: 6)
                .padding(32)
            Text(steps.formatted())
                .font(.system(size: 40, weight: .bold).monospacedDigit())
                .tracking(-0.8)
                .contentTransition(.numericText())
                .accessibilityLabel("\(steps.formatted()) of \(goal.formatted()) steps")
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.4), value: steps)
        .accessibilityElement(children: .combine)
    }

    private func arc(to end: Double, colors: [Color]) -> some View {
        Circle()
            .trim(from: 0, to: end)
            .stroke(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: trackRadius * 2, height: trackRadius * 2)
            .rotationEffect(.degrees(-90))
    }
}

struct SettingsView: View {
    @Binding var goal: Int
    @Binding var startSpeedKmh: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.system(size: 15, weight: .bold))
            setting("Daily goal") {
                PebbleStepper(value: "\(goal.clamped(to: goalStepsRange).formatted()) steps") { direction in
                    goal = (goal.clamped(to: goalStepsRange) + direction * 500).clamped(to: goalStepsRange)
                }
            }
            setting("Start speed") {
                PebbleStepper(value: "\(startSpeedKmh.formatted(.number.precision(.fractionLength(1)))) km/h") { direction in
                    startSpeedKmh = (startSpeedKmh + Double(direction) * 0.5).clamped(to: PadCommand.beltSpeedKmh)
                }
            }
            setting("Start / stop shortcut") {
                KeyboardShortcuts.Recorder(for: .toggleBelt)
            }
            Divider()
            Button("Quit WalkingPad", systemImage: "power") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.muted)
        }
        .padding(18)
        .frame(width: 260)
        .foregroundStyle(Color.ink)
        .fontDesign(.rounded)
        .background(Color(red: 0.997, green: 0.989, blue: 0.975))
        .preferredColorScheme(.light)
    }

    private func setting(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.muted)
            content()
        }
    }
}

/// A value set in a groove between two raised pebble buttons; `step` receives -1 or +1.
struct PebbleStepper: View {
    let value: String
    let step: (Int) -> Void

    var body: some View {
        HStack {
            pebble("minus", label: "Decrease") { step(-1) }
            Text(value)
                .font(.system(size: 17, weight: .bold).monospacedDigit())
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)
            pebble("plus", label: "Increase") { step(1) }
        }
        .padding(4)
        .background(Capsule().fill(Color.groove.shadow(.inner(color: .warmShadow.opacity(0.22), radius: 3, y: 2))))
        .animation(.snappy, value: value)
    }

    private func pebble(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color(red: 0.999, green: 0.993, blue: 0.982))
                        .shadow(color: .warmShadow.opacity(0.25), radius: 2, y: 1.5)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .focusEffectDisabled()
        .accessibilityLabel(label)
    }
}

extension Connection {
    /// Being connected is the normal state, so only its absence gets a line.
    var problem: String? {
        switch self {
        case .bluetoothUnavailable: "Bluetooth is off or not allowed"
        case .searching: "Disconnected"
        case .connecting: "Connecting…"
        case .connected: nil
        }
    }
}

#Preview("Ring") {
    StepRing(steps: 6_240, goal: 10_000, isRunning: true).padding()
}

#Preview("Goal exceeded") {
    StepRing(steps: 13_400, goal: 10_000, isRunning: false).padding()
}

#Preview("Settings") {
    SettingsView(goal: .constant(10_000), startSpeedKmh: .constant(5.5))
}
