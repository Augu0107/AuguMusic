import SwiftUI

// MARK: - Equalizzatore (stile Musicolet: bande in una scheda, manopole ed effetti nell'altra)

struct EqualizerView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @AppStorage("eqTab") private var tab = 0
    @State private var savingPreset = false
    @State private var presetName = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            deviceBox
                .padding(.horizontal, 16)
                .padding(.top, 8)
            Group {
                if tab == 0 { bandsTab } else { effectsTab }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomTabs
        }
        .background(Color(uiColor: .systemBackground))
        .alert("Salva preset", isPresented: $savingPreset) {
            TextField("Nome", text: $presetName)
            Button("Salva") {
                let name = presetName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                settings.customPresets[name] = settings.eqGains
                settings.eqPresetName = name
            }
            Button("Annulla", role: .cancel) {}
        }
    }

    // MARK: Parti fisse

    private var header: some View {
        HStack(spacing: 18) {
            Button { dismiss() } label: {
                Image(systemName: "arrow.left").font(.title2)
            }
            Text("Equalizzatore").font(.title2.weight(.semibold))
            Spacer()
            Menu {
                Button { settings.resetEQ() } label: { Label("Reimposta tutto", systemImage: "arrow.counterclockwise") }
                Button {
                    presetName = ""
                    savingPreset = true
                } label: { Label("Salva come preset…", systemImage: "plus") }
                if !settings.customPresets.isEmpty {
                    Menu {
                        ForEach(settings.customPresets.keys.sorted(), id: \.self) { name in
                            Button(role: .destructive) { settings.customPresets[name] = nil } label: { Text(name) }
                        }
                    } label: { Label("Elimina un preset", systemImage: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis").rotationEffect(.degrees(90)).font(.title2).frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(Color.primary.opacity(0.8))
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private var deviceBox: some View {
        HStack(spacing: 12) {
            Image(systemName: PlayerController.currentOutputIcon())
                .foregroundStyle(Color.accentColor)
            Menu {
                Section("Impostazioni salvate per ogni dispositivo") {
                    Label(settings.eqDevice.isEmpty ? "Questo dispositivo" : settings.eqDevice, systemImage: "checkmark")
                    ForEach(settings.otherEQDevices, id: \.self) { name in
                        Menu(name) {
                            Button("Dimentica le impostazioni", role: .destructive) { settings.forgetEQDevice(name) }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(settings.eqDevice.isEmpty ? "Altoparlante" : settings.eqDevice)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down").foregroundStyle(.secondary)
                }
            }
            Rectangle().fill(Color(uiColor: .systemGray4)).frame(width: 1, height: 30)
            Toggle("", isOn: $settings.eqEnabled).labelsHidden().tint(Color.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(uiColor: .systemGray4), lineWidth: 1.5))
    }

    private var bottomTabs: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(uiColor: .systemGray4)).frame(height: 1).padding(.horizontal, 60)
            HStack {
                tabButton(0) {
                    Image(systemName: "slider.vertical.3").font(.title)
                }
                tabButton(1) {
                    Circle().frame(width: 34, height: 34)
                        .overlay(Rectangle().fill(Color(uiColor: .systemBackground)).frame(width: 2, height: 8)
                            .offset(y: -9).rotationEffect(.degrees(-40)))
                }
            }
            .padding(.vertical, 10)
        }
    }

    private func tabButton<L: View>(_ i: Int, @ViewBuilder label: () -> L) -> some View {
        Button { tab = i } label: {
            label()
                .foregroundStyle(tab == i ? Color.primary : Color.secondary.opacity(0.6))
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.plain)
    }

    // MARK: Bande

    private var bandIndices: [Int] { settings.eqBands == 5 ? EQPresets.fiveBandIndices : Array(0..<10) }

    private var bandsTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Menu {
                    Button("5 bande") { settings.eqBands = 5 }
                    Button("10 bande") { settings.eqBands = 10 }
                } label: {
                    pill {
                        HStack(spacing: 10) {
                            Image(systemName: "water.waves")
                            Text("\(settings.eqBands)")
                        }
                    }
                }
                Menu {
                    ForEach(EQPresets.builtIn) { preset in
                        Button(preset.name) { settings.applyPreset(name: preset.name, gains: preset.gains) }
                    }
                    if !settings.customPresets.isEmpty {
                        Divider()
                        ForEach(settings.customPresets.keys.sorted(), id: \.self) { name in
                            Button(name) { settings.applyPreset(name: name, gains: settings.customPresets[name] ?? []) }
                        }
                    }
                    Divider()
                    Button {
                        presetName = ""
                        savingPreset = true
                    } label: { Label("Salva come preset…", systemImage: "plus") }
                } label: {
                    pill { Text(settings.eqPresetName).lineLimit(1) }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Spacer(minLength: 20)
            HStack(spacing: 0) {
                ForEach(bandIndices, id: \.self) { i in
                    VStack(spacing: 6) {
                        Text(EQPresets.frequencyLabels[i])
                        Text(String(format: "%.1f", settings.eqGains[safe: i] ?? 0).replacingOccurrences(of: ".", with: ","))
                    }
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            HStack(spacing: 0) {
                ForEach(bandIndices, id: \.self) { i in
                    EQBandSlider(value: Binding(
                        get: { settings.eqGains[safe: i] ?? 0 },
                        set: { v in
                            guard settings.eqGains.indices.contains(i) else { return }
                            settings.eqGains[i] = v
                            settings.eqPresetName = "Personalizzato"
                        }), enabled: settings.eqEnabled)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 30)
            .frame(maxHeight: 520)
            Spacer(minLength: 20)
        }
    }

    private func pill<L: View>(@ViewBuilder _ label: () -> L) -> some View {
        label()
            .font(.title3)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 30)
            .frame(height: 52)
            .overlay(Capsule().stroke(Color(uiColor: .systemGray3), lineWidth: 1.5))
    }

    // MARK: Effetti

    private var effectsTab: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    knobBlock(title: "Bass boost", value: Binding(get: { settings.bassBoost / 12 }, set: { settings.bassBoost = ($0 * 12).rounded(toPlaces: 1) }),
                              text: "\(Int((settings.bassBoost / 12 * 100).rounded()))%")
                    knobBlock(title: "Suono Surround", value: $settings.surround,
                              text: "\(Int((settings.surround * 100).rounded()))%")
                }
                .padding(.top, 30)
                divider

                Text("Preamp").font(.title3).foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    preampButton("Headroom", "-6 dB", -6)
                    preampButton("spento", "0 dB", 0)
                    preampButton("Aumento", "+2 dB", 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(uiColor: .systemGray3), lineWidth: 1.5))
                .padding(.top, 14)
                HStack {
                    Slider(value: $settings.eqPreamp, in: -12...12, step: 0.5).tint(Color(uiColor: .systemGray3))
                    Text(String(format: "%+.1f dB", settings.eqPreamp))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 70)
                }
                .padding(.horizontal, 40)
                .padding(.top, 18)
                divider

                Text("Volume").font(.title3).foregroundStyle(.secondary)
                Slider(value: $settings.eqVolume, in: 0...1)
                    .padding(.horizontal, 40)
                    .padding(.top, 18)
                divider

                HStack(alignment: .center, spacing: 40) {
                    VStack(spacing: 0) {
                        monoButton("Stereo", selected: !settings.mono) { settings.mono = false }
                        Rectangle().fill(settings.mono ? Color(uiColor: .systemGray3) : Color.accentColor).frame(height: 1.5)
                        monoButton("Mono", selected: settings.mono) { settings.mono = true }
                    }
                    .frame(width: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(uiColor: .systemGray3), lineWidth: 1.5))

                    VStack(spacing: 12) {
                        Knob(value: Binding(get: { (settings.balance + 1) / 2 },
                                            set: { settings.balance = (($0 * 2 - 1) * 100).rounded() / 100 }),
                             centered: true)
                            .frame(width: 180, height: 180)
                        Text("Bilanciamento canale audio").font(.headline).foregroundStyle(.secondary)
                        Text("Sinistro:\(Int((min(1, 1 - settings.balance) * 100).rounded())), Destro:\(Int((min(1, 1 + settings.balance) * 100).rounded()))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 20)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    private var divider: some View {
        Rectangle().fill(Color(uiColor: .systemGray4)).frame(height: 1).padding(.horizontal, 60).padding(.vertical, 26)
    }

    private func knobBlock(title: String, value: Binding<Double>, text: String) -> some View {
        VStack(spacing: 14) {
            Knob(value: value).frame(width: 200, height: 200)
            Text(L(title)).font(.title3).foregroundStyle(.secondary)
            Text(L(text)).font(.headline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func preampButton(_ title: String, _ db: String, _ value: Double) -> some View {
        let selected = abs(settings.eqPreamp - value) < 0.01
        return Button { settings.eqPreamp = value } label: {
            VStack(spacing: 2) {
                Text(L(title))
                Text(db)
            }
            .font(.subheadline)
            .foregroundStyle(selected ? Color.primary.opacity(0.7) : Color.secondary)
            .frame(width: 140, height: 62)
            .background(selected ? Color.secondary.opacity(0.08) : Color.clear)
            .overlay(Rectangle().stroke(selected ? Color.secondary : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func monoButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(L(title))
                .font(.title3)
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 70)
                .background(selected ? Color.accentColor.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

/// Cursore verticale di una banda: linea grigia e maniglia arrotondata con un trattino.
struct EQBandSlider: View {
    @Binding var value: Double
    var enabled = true
    var range: ClosedRange<Double> = -12...12

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let thumbH: CGFloat = min(150, h * 0.25)
            let travel = h - thumbH
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let y = travel * (1 - CGFloat(fraction))
            let lineColor = enabled ? Color.accentColor : Color(uiColor: .systemGray3)
            ZStack(alignment: .top) {
                Rectangle().fill(Color(uiColor: .systemGray3)).frame(width: 3, height: h)
                Rectangle().fill(lineColor).frame(width: 3, height: max(0, h - y - thumbH / 2))
                    .offset(y: y + thumbH / 2)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(enabled ? Color.accentColor.opacity(0.8) : Color(uiColor: .systemGray3), lineWidth: 2))
                    .overlay(Rectangle().fill(enabled ? Color.accentColor : Color(uiColor: .systemGray3)).frame(width: 30, height: 3))
                    .frame(width: min(geo.size.width - 6, 46), height: thumbH)
                    .offset(y: y)
            }
            .frame(width: geo.size.width, height: h)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                guard enabled else { return }
                let f = 1 - Double((g.location.y - thumbH / 2) / max(travel, 1))
                let v = range.lowerBound + min(1, max(0, f)) * (range.upperBound - range.lowerBound)
                value = (v * 2).rounded() / 2
            })
        }
    }
}

/// Manopola: si gira trascinando su/giù. `centered`: il valore 0.5 sta in alto (bilanciamento).
struct Knob: View {
    @Binding var value: Double
    var centered = false
    @State private var startValue: Double?

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let angle = -135 + 270 * min(1, max(0, value))
            let active = centered ? abs(value - 0.5) > 0.001 || true : value > 0.001
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(uiColor: .systemGray6), Color(uiColor: .systemBackground)],
                                         startPoint: .top, endPoint: .bottom))
                Circle().stroke(active && centered ? Color(uiColor: .systemGray) : Color(uiColor: .systemGray4), lineWidth: 3)
                Capsule()
                    .fill(active && (centered || value > 0.001) ? Color.accentColor : Color(uiColor: .systemGray3))
                    .frame(width: 3, height: size * 0.12)
                    .offset(y: -size * 0.32)
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if startValue == nil { startValue = value }
                    let delta = (Double(-g.translation.height) + Double(g.translation.width)) / 300
                    value = min(1, max(0, (startValue ?? 0) + delta))
                    if centered, abs(value - 0.5) < 0.02 { value = 0.5 }
                }
                .onEnded { _ in startValue = nil })
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

private extension Double {
    func rounded(toPlaces p: Int) -> Double {
        let m = pow(10, Double(p))
        return (self * m).rounded() / m
    }
}
