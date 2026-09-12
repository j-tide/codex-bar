import SwiftUI

struct RefreshIconView: View {
    let isRefreshing: Bool
    let size: CGFloat
    let fontSize: CGFloat
    let weight: Font.Weight

    @State private var rotation: Double = 0
    @State private var spinTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: fontSize, weight: weight))
            .symbolRenderingMode(.hierarchical)
            .rotationEffect(.degrees(rotation))
            .frame(width: size, height: size)
            .onAppear { updateSpinTask() }
            .onChange(of: isRefreshing) { _, _ in
                updateSpinTask()
            }
            .onDisappear {
                spinTask?.cancel()
                spinTask = nil
            }
    }

    private func updateSpinTask() {
        if isRefreshing {
            startSpinning()
        } else {
            stopSpinning()
        }
    }

    private func startSpinning() {
        guard spinTask == nil else { return }

        spinTask = Task { @MainActor in
            while !Task.isCancelled {
                withAnimation(.linear(duration: 0.92)) {
                    rotation += 360
                }
                try? await Task.sleep(nanoseconds: 920_000_000)
            }
        }
    }

    private func stopSpinning() {
        spinTask?.cancel()
        spinTask = nil
    }
}

/// The button stays quiet; the panel divider carries the refresh effect.
struct HeaderRefreshGlyph: View {
    let isRefreshing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.popupLiveUpdates) private var liveUpdates

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isRefreshing || reduceMotion || !liveUpdates)) { context in
            let rotating = isRefreshing && !reduceMotion && liveUpdates
            let phase = rotating ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2 : 0
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isRefreshing ? Color.accentColor : .primary)
                .rotationEffect(.degrees(phase * 360))
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// An indeterminate sweep, not a percentage: it tracks the real refresh lifetime.
struct HeaderRefreshSweep: View {
    let isRefreshing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.popupLiveUpdates) private var liveUpdates
    @Environment(\.colorScheme) private var colorScheme
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isRefreshing || reduceMotion || !liveUpdates)) { context in
            GeometryReader { geometry in
                let stationary = reduceMotion || !liveUpdates
                let elapsed = max(0, context.date.timeIntervalSince(startedAt))
                let phase = stationary ? 0.55 : max(0, elapsed - 0.12).truncatingRemainder(dividingBy: 2.6) / 2.6
                let ignition = stationary ? 0 : pow(max(0, 1 - elapsed / 0.45), 2)
                let width = geometry.size.width
                let highlightWidth = width * 0.58
                let shimmer = stationary ? 1 : 0.90 + 0.10 * sin(elapsed * .pi * 2 / 2.2)
                let violet = Color(red: 0.63, green: 0.54, blue: 1)
                let ice = Color(red: 0.42, green: 0.79, blue: 1)
                let blue = Color(red: 0.14, green: 0.57, blue: 0.91)
                let highlight = LinearGradient(stops: [
                    .init(color: ice.opacity(0), location: 0),
                    .init(color: violet.opacity(0.55), location: 0.22),
                    .init(color: ice.opacity(0.85), location: 0.56),
                    .init(color: Color(red: 0.86, green: 0.97, blue: 1), location: 0.77),
                    .init(color: .white, location: 0.85),
                    .init(color: ice.opacity(0), location: 1)
                ], startPoint: .leading, endPoint: .trailing)

                ZStack(alignment: .leading) {
                    // The full divider stays lit. Only its silver reflection moves.
                    Rectangle()
                        .fill(LinearGradient(colors: [blue, ice, blue], startPoint: .leading, endPoint: .trailing))
                        .opacity(colorScheme == .dark ? 0.62 : 0.75)
                        .frame(height: 1.25)
                    Rectangle().fill(ice.opacity(0.16)).frame(height: 3).blur(radius: 1.5)
                    ZStack {
                        Rectangle().fill(highlight).frame(height: 3).blur(radius: 2).opacity(0.85)
                        Rectangle().fill(highlight).frame(height: 1.75)
                    }
                    .frame(width: highlightWidth)
                    .opacity(shimmer)
                    .offset(x: (width + highlightWidth) * phase - highlightWidth)
                    // A brief rise in brightness acknowledges the click without flashing repeatedly.
                    Rectangle().fill(ice.opacity(ignition * 0.9)).frame(height: 2.25)
                }
                .frame(width: width, height: geometry.size.height)
            }
        }
        .frame(height: 11)
        .clipped()
        .opacity(isRefreshing ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: isRefreshing ? 0.12 : 0.45), value: isRefreshing)
        .onChange(of: isRefreshing) { _, refreshing in
            if refreshing { startedAt = Date() }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
