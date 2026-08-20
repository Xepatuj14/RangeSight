import SwiftUI
import RangeSightCore

struct RootView: View {
    @State private var selectedScreen: AppScreenID = .home

    private var screen: AppScreen {
        AppNavigation.screen(for: selectedScreen)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    statusPanel
                    metricStrip
                    targetPreview
                    actionList
                    screenPicker
                }
                .padding()
            }
            .background(Color(.sRGB, red: 0.06, green: 0.07, blue: 0.08, opacity: 1))
            .foregroundStyle(.white)
            .navigationTitle("RangeSight")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        HStack {
            Text("RangeSight")
                .font(.title.bold())
            Spacer()
            Text("NATIVE FOUNDATION")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(screen.phase.rawValue.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.yellow)
            Text(screen.title)
                .font(.largeTitle.bold())
            Text(screen.description)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var metricStrip: some View {
        HStack {
            metric(value: "0", label: "shots")
            metric(value: "--", label: "group")
            metric(value: "local", label: "privacy")
        }
        .padding()
        .background(Color(.sRGB, red: 0.10, green: 0.12, blue: 0.14, opacity: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.bold())
            Text(label.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var targetPreview: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black)
                .aspectRatio(0.72, contentMode: .fit)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.sRGB, red: 0.91, green: 0.90, blue: 0.86, opacity: 1))
                .overlay {
                    Circle()
                        .stroke(Color.black, lineWidth: 18)
                        .frame(width: 150, height: 150)
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 10, height: 10)
                }
                .frame(maxWidth: 260)
                .aspectRatio(1, contentMode: .fit)
            Text(screen.previewStatus.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.yellow)
                .padding(.bottom, 16)
        }
    }

    private var actionList: some View {
        VStack(spacing: 10) {
            ForEach(screen.actions) { action in
                Button(action.title) {
                    selectedScreen = action.destination
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var screenPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
            ForEach(AppNavigation.screens) { candidate in
                Button(candidate.title) {
                    selectedScreen = candidate.id
                }
                .buttonStyle(.bordered)
                .tint(candidate.id == selectedScreen ? .yellow : .secondary)
            }
        }
    }
}
