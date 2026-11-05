import AppKit
import AVFoundation
import CoreImage
import Observation
import SwiftUI

/// A live camera mirror. The camera only runs while the Mirror tab is open and you pressed Start.
@MainActor @Observable
final class MirrorModel {
    enum Access { case unknown, granted, denied }

    private(set) var running = false
    private(set) var access: Access = .unknown
    private(set) var cameras: [AVCaptureDevice] = []
    var cameraID: String?

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let queue = DispatchQueue(label: "saku.camera")
    @ObservationIgnored private let prefs: Prefs

    init(prefs: Prefs) {
        self.prefs = prefs
        refreshAccess()
    }

    func refreshAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: access = .granted
        case .notDetermined: access = .unknown
        default: access = .denied
        }
    }

    func discover() {
        cameras = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                                   mediaType: .video, position: .unspecified).devices
        if cameraID == nil || !cameras.contains(where: { $0.uniqueID == cameraID }) {
            cameraID = cameras.first { $0.position == .front }?.uniqueID ?? cameras.first?.uniqueID
        }
    }

    /// Asks for camera access the first time (the macOS prompt), then starts.
    func start() {
        Task { @MainActor in
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            refreshAccess()
            guard access == .granted else { return }
            discover()
            configure()
            let s = session
            queue.async { s.startRunning() }
            running = true
        }
    }

    func stop() {
        guard running else { return }
        let s = session
        queue.async { s.stopRunning() }
        running = false
    }

    func select(_ id: String) {
        cameraID = id
        if running { configure() }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        session.inputs.forEach { session.removeInput($0) }
        if let d = cameras.first(where: { $0.uniqueID == cameraID }) ?? AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: d), session.canAddInput(input) {
            session.addInput(input)
        }
        session.commitConfiguration()
    }
}

enum MirrorEffect: String, CaseIterable {
    case natural, warm, cool, mono, soft

    var title: String {
        switch self {
        case .natural: tr("Natural")
        case .warm: tr("Warm")
        case .cool: tr("Cool")
        case .mono: tr("Mono")
        case .soft: tr("Soft")
        }
    }

    var filters: [CIFilter] {
        switch self {
        case .natural: return []
        case .warm:
            let f = CIFilter(name: "CITemperatureAndTint")!
            f.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            f.setValue(CIVector(x: 5200, y: 0), forKey: "inputTargetNeutral")
            return [f]
        case .cool:
            let f = CIFilter(name: "CITemperatureAndTint")!
            f.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            f.setValue(CIVector(x: 8200, y: 0), forKey: "inputTargetNeutral")
            return [f]
        case .mono: return [CIFilter(name: "CIPhotoEffectMono")!]
        case .soft:
            let f = CIFilter(name: "CIBloom")!
            f.setValue(4.0, forKey: kCIInputRadiusKey)
            f.setValue(0.45, forKey: kCIInputIntensityKey)
            return [f]
        }
    }
}

/// Hosts the preview layer; mirrored like a real mirror unless turned off.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    var mirrored: Bool
    var effect: MirrorEffect

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layerUsesCoreImageFilters = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = v.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        v.layer?.addSublayer(layer)
        apply(to: layer)
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        if let layer = v.layer?.sublayers?.first as? AVCaptureVideoPreviewLayer { apply(to: layer) }
    }

    private func apply(to layer: AVCaptureVideoPreviewLayer) {
        if let c = layer.connection, c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = mirrored
        }
        layer.filters = effect.filters
    }
}

struct MirrorView: View {
    let app: AppModel

    var body: some View {
        let m = app.mirror!
        let ring = app.prefs.v.mirrorRingLight
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card)
                if m.running {
                    CameraPreview(session: m.session, mirrored: app.prefs.v.mirrorFlip, effect: MirrorEffect(rawValue: app.prefs.v.mirrorEffect) ?? .natural)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: m.access == .denied ? "video.slash.fill" : "person.crop.square.fill")
                            .font(.system(size: 26)).foregroundStyle(Theme.blossom)
                        Text(m.access == .denied ? tr("Camera access is off") : tr("Check your hair before a call"))
                            .font(Theme.font(12.5, .semibold)).foregroundStyle(Theme.text)
                        if m.access == .denied {
                            PillButton(title: tr("Open Privacy settings"), icon: "lock.fill", primary: true) { Privacy.open("Privacy_Camera") }
                        } else {
                            PillButton(title: tr("Start mirror"), icon: "video.fill", primary: true) { m.start() }
                        }
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(ring ? Color.white : Theme.stroke, lineWidth: ring ? 10 : 1))
            .shadow(color: ring ? Color.white.opacity(0.8) : .clear, radius: ring ? 24 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 7) {
                Caption(text: tr("Mirror"))
                ToggleChip(title: tr("Flip like a mirror"), icon: "arrow.left.and.right", on: app.prefs.v.mirrorFlip) { app.prefs.v.mirrorFlip.toggle() }
                ToggleChip(title: tr("Ring light"), icon: "sun.max.fill", on: ring, tint: Theme.butter) { app.prefs.v.mirrorRingLight.toggle() }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                    ForEach(MirrorEffect.allCases, id: \.self) { e in
                        let on = app.prefs.v.mirrorEffect == e.rawValue
                        Button { app.prefs.v.mirrorEffect = e.rawValue } label: {
                            Text(e.title).font(Theme.font(10.5, .semibold))
                                .foregroundStyle(on ? Color.black.opacity(0.85) : Theme.text2)
                                .frame(maxWidth: .infinity).frame(height: 22)
                                .background(Capsule().fill(on ? Theme.blossom : Color.white.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if m.cameras.count > 1 {
                    Menu {
                        ForEach(m.cameras, id: \.uniqueID) { c in Button(c.localizedName) { m.select(c.uniqueID) } }
                    } label: {
                        Text(m.cameras.first { $0.uniqueID == m.cameraID }?.localizedName ?? tr("Camera")).font(Theme.font(11, .semibold))
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
                Spacer(minLength: 0)
                if m.running {
                    PillButton(title: tr("Stop"), icon: "stop.fill") { m.stop() }
                }
            }
            .frame(width: 210)
        }
        .onAppear {
            m.refreshAccess()
            if m.access == .granted && app.prefs.v.mirrorAutoStart && !Render.active { m.start() }
        }
        .onDisappear { m.stop() }
    }
}

struct MirrorPane: View {
    let app: AppModel
    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section {
                Toggle(tr("Start the camera when the Mirror tab opens"), isOn: $prefs.v.mirrorAutoStart)
                Toggle(tr("Flip like a mirror"), isOn: $prefs.v.mirrorFlip)
                Toggle(tr("Ring light (a bright frame that lights your face)"), isOn: $prefs.v.mirrorRingLight)
                Picker(tr("Look"), selection: $prefs.v.mirrorEffect) {
                    ForEach(MirrorEffect.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
            } footer: {
                Text(tr("The camera turns off as soon as you leave the Mirror tab or close the notch. Nothing is recorded."))
            }
        }
        .formStyle(.grouped)
    }
}
