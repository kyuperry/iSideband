import SwiftUI
import MapKit

enum MeshMapMode: String, CaseIterable, Identifiable {
    case geographic
    case topology

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .geographic:
            return "Geographic"

        case .topology:
            return "Topology"
        }
    }

    var icon: String {
        switch self {
        case .geographic:
            return "map.fill"

        case .topology:
            return "point.3.connected.trianglepath.dotted"
        }
    }
}

enum GeographicMapStyle: String, CaseIterable, Identifiable {
    case standard
    case satellite
    case hybrid

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .standard:
            return "Standard"

        case .satellite:
            return "Satellite"

        case .hybrid:
            return "Hybrid"
        }
    }

    var icon: String {
        switch self {
        case .standard:
            return "map"

        case .satellite:
            return "globe.americas.fill"

        case .hybrid:
            return "square.2.layers.3d"
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .standard:
            return .standard

        case .satellite:
            return .imagery

        case .hybrid:
            return .hybrid
        }
    }
}

struct MeshMapView: View {
    @ObservedObject var bluetooth: BluetoothManager

    @AppStorage("selectedMeshMapMode")
    private var selectedMode: MeshMapMode = .geographic

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedMode {
                case .geographic:
                    GeographicMeshMapView(
                        startsInHawaii:
                            bluetooth.connectedDeviceID != nil
                    )

                case .topology:
                    TopologyMeshMapView()
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )

            modeSelector
                .padding(.horizontal)
                .padding(.bottom, 18)
        }
        .navigationTitle("Mesh Map")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var modeSelector: some View {
        HStack(spacing: 6) {
            ForEach(MeshMapMode.allCases) { mode in
                Button {
                    withAnimation(
                        .easeInOut(duration: 0.2)
                    ) {
                        selectedMode = mode
                    }
                } label: {
                    Label(
                        mode.title,
                        systemImage: mode.icon
                    )
                    .font(
                        .subheadline.weight(.semibold)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(
                        selectedMode == mode
                            ? Color.white
                            : Color.primary
                    )
                    .background {
                        if selectedMode == mode {
                            Capsule()
                                .fill(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(
                    Color.secondary.opacity(0.2),
                    lineWidth: 1
                )
        }
        .frame(maxWidth: .infinity)
    }
}

struct GeographicMeshMapView: View {
    private static let hawaiiRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(
            latitude: 20.8,
            longitude: -156.3
        ),
        span: MKCoordinateSpan(
            latitudeDelta: 5.2,
            longitudeDelta: 8.0
        )
    )

    @AppStorage("selectedGeographicMapStyle")
    private var selectedMapStyle:
        GeographicMapStyle = .standard

    @State private var cameraPosition: MapCameraPosition

    @State private var showInformationBanner = true

    init(startsInHawaii: Bool) {
        _cameraPosition = State(
            initialValue: startsInHawaii
                ? .region(Self.hawaiiRegion)
                : .automatic
        )
    }

    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                UserAnnotation()
            }
            .mapStyle(selectedMapStyle.mapStyle)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea(edges: .bottom)

            currentLocationButton

            if showInformationBanner {
                VStack {
                    Spacer()

                    dismissibleStatusBanner(
                        title: "Geographic Mesh Map",
                        message:
                            "Nodes that opt in to location sharing will appear here.",
                        isPresented:
                            $showInformationBanner
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 90)
                    .transition(
                        .move(edge: .bottom)
                            .combined(with: .opacity)
                    )
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                mapStyleMenu
            }
        }
        .animation(
            .easeInOut(duration: 0.2),
            value: showInformationBanner
        )
    }

    private var currentLocationButton: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                Button {
                    withAnimation {
                        cameraPosition = .userLocation(
                            followsHeading: false,
                            fallback: .automatic
                        )
                    }
                } label: {
                    Image(systemName: "location.fill")
                        .font(
                            .body.weight(.semibold)
                        )
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.secondary
                                        .opacity(0.2),
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Go to current location"
                )
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 92)
    }

    private var mapStyleMenu: some View {
        Menu {
            ForEach(
                GeographicMapStyle.allCases
            ) { style in
                Button {
                    selectedMapStyle = style
                } label: {
                    Label(
                        style.title,
                        systemImage: style.icon
                    )
                }
            }
        } label: {
            Image(systemName: selectedMapStyle.icon)
        }
        .accessibilityLabel("Choose map style")
    }
}

import SwiftUI

struct TopologyMeshMapView: View {
    @ObservedObject private var discoveredStore =
        ReticulumDiscoveredPeerStore.shared

    @State private var showInformationBanner = true

    private struct DisplayNode: Identifiable {
        let id: String
        let name: String
        let detail: String?
    }

    private var discoveredNodes: [DisplayNode] {
        discoveredStore.peers.enumerated().map { index, peer in
            let name =
                reflectedString(
                    from: peer,
                    matching: [
                        "displayName",
                        "name",
                        "peerName",
                        "identityName",
                        "announceName"
                    ]
                )
                ?? "Discovered Node"

            let destinationHash =
                reflectedString(
                    from: peer,
                    matching: [
                        "destinationHashHex",
                        "destinationHash",
                        "identityHash",
                        "hash"
                    ]
                )

            let shortenedHash = destinationHash.map {
                shortenHash($0)
            }

            return DisplayNode(
                id: destinationHash ?? "peer-\(index)",
                name: name,
                detail: shortenedHash
            )
        }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea(edges: .bottom)

            if discoveredNodes.isEmpty {
                emptyTopology
            } else {
                topologyCanvas
            }

            if showInformationBanner {
                VStack {
                    Spacer()

                    dismissibleStatusBanner(
                        title: "Topology Mesh Map",
                        message:
                            "The center represents your connected RNode. Discovered Reticulum nodes appear around it.",
                        isPresented:
                            $showInformationBanner
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 90)
                    .transition(
                        .move(edge: .bottom)
                            .combined(with: .opacity)
                    )
                }
            }
        }
        .animation(
            .easeInOut(duration: 0.2),
            value: showInformationBanner
        )
        .animation(
            .easeInOut(duration: 0.25),
            value: discoveredNodes.count
        )
    }

    private var topologyCanvas: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let center = CGPoint(
                x: size.width / 2,
                y: size.height / 2
            )

            let peerPositions = positions(
                around: center,
                count: discoveredNodes.count,
                availableSize: size
            )

            Canvas { context, _ in
                for position in peerPositions {
                    drawConnection(
                        from: center,
                        to: position,
                        in: &context
                    )
                }

                for (index, node) in discoveredNodes.enumerated() {
                    guard peerPositions.indices.contains(index) else {
                        continue
                    }

                    drawPeerNode(
                        at: peerPositions[index],
                        node: node,
                        in: &context
                    )
                }

                drawConnectedRNode(
                    at: center,
                    in: &context
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 45)
        .padding(.bottom, 115)
    }

    private var emptyTopology: some View {
        VStack(spacing: 18) {
            Spacer()

            connectedRNodePreview

            VStack(spacing: 6) {
                Text("Connected RNode")
                    .font(.headline)

                Text(
                    "Discovered Reticulum nodes will appear around your RNode."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 90)
    }

    private var connectedRNodePreview: some View {
        ZStack {
            Circle()
                .fill(
                    Color.accentColor.opacity(0.14)
                )
                .frame(
                    width: 108,
                    height: 108
                )

            VStack(spacing: 0) {
                Image(
                    systemName:
                        "antenna.radiowaves.left.and.right"
                )
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .offset(y: 3)

                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
                .fill(Color.accentColor)
                .frame(
                    width: 57,
                    height: 44
                )
                .overlay {
                    VStack(spacing: 5) {
                        Capsule()
                            .fill(Color.white.opacity(0.95))
                            .frame(
                                width: 27,
                                height: 4
                            )

                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.green)
                                .frame(
                                    width: 7,
                                    height: 7
                                )

                            Circle()
                                .fill(Color.white.opacity(0.8))
                                .frame(
                                    width: 7,
                                    height: 7
                                )
                        }
                    }
                }
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                    .stroke(
                        Color.white.opacity(0.9),
                        lineWidth: 2
                    )
                }
            }
        }
    }

    private func positions(
        around center: CGPoint,
        count: Int,
        availableSize: CGSize
    ) -> [CGPoint] {
        guard count > 0 else {
            return []
        }

        let displayedCount = min(count, 12)

        let horizontalRadius = min(
            max(115, availableSize.width * 0.34),
            165
        )

        let verticalRadius = min(
            max(125, availableSize.height * 0.28),
            215
        )

        return (0..<displayedCount).map { index in
            let angle =
                (Double(index) / Double(displayedCount))
                * (Double.pi * 2)
                - (Double.pi / 2)

            return CGPoint(
                x:
                    center.x
                    + CGFloat(cos(angle))
                    * horizontalRadius,
                y:
                    center.y
                    + CGFloat(sin(angle))
                    * verticalRadius
            )
        }
    }

    private func drawConnection(
        from start: CGPoint,
        to end: CGPoint,
        in context: inout GraphicsContext
    ) {
        var glowPath = Path()
        glowPath.move(to: start)
        glowPath.addLine(to: end)

        context.stroke(
            glowPath,
            with: .color(
                Color.accentColor.opacity(0.12)
            ),
            style: StrokeStyle(
                lineWidth: 7,
                lineCap: .round
            )
        )

        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        context.stroke(
            path,
            with: .color(
                Color.accentColor.opacity(0.58)
            ),
            style: StrokeStyle(
                lineWidth: 2,
                lineCap: .round,
                dash: [7, 6]
            )
        )
    }

    private func drawConnectedRNode(
        at point: CGPoint,
        in context: inout GraphicsContext
    ) {
        let outerRect = CGRect(
            x: point.x - 46,
            y: point.y - 46,
            width: 92,
            height: 92
        )

        context.fill(
            Path(ellipseIn: outerRect),
            with: .color(
                Color.accentColor.opacity(0.16)
            )
        )

        let antenna = context.resolve(
            Image(
                systemName:
                    "antenna.radiowaves.left.and.right"
            )
        )

        context.draw(
            antenna,
            in: CGRect(
                x: point.x - 14,
                y: point.y - 43,
                width: 28,
                height: 28
            )
        )

        let bodyRect = CGRect(
            x: point.x - 31,
            y: point.y - 16,
            width: 62,
            height: 48
        )

        context.fill(
            Path(
                roundedRect: bodyRect,
                cornerRadius: 11
            ),
            with: .color(Color.accentColor)
        )

        context.stroke(
            Path(
                roundedRect: bodyRect,
                cornerRadius: 11
            ),
            with: .color(
                Color.white.opacity(0.92)
            ),
            lineWidth: 2.5
        )

        let displayRect = CGRect(
            x: point.x - 17,
            y: point.y - 6,
            width: 34,
            height: 7
        )

        context.fill(
            Path(
                roundedRect: displayRect,
                cornerRadius: 3
            ),
            with: .color(
                Color.white.opacity(0.9)
            )
        )

        let statusRect = CGRect(
            x: point.x - 4,
            y: point.y + 10,
            width: 8,
            height: 8
        )

        context.fill(
            Path(ellipseIn: statusRect),
            with: .color(Color.green)
        )

        let title = context.resolve(
            Text("Connected RNode")
                .font(
                    .caption.weight(.bold)
                )
                .foregroundStyle(.primary)
        )

        context.draw(
            title,
            at: CGPoint(
                x: point.x,
                y: point.y + 53
            ),
            anchor: .center
        )
    }

    private func drawPeerNode(
        at point: CGPoint,
        node: DisplayNode,
        in context: inout GraphicsContext
    ) {
        let circleRect = CGRect(
            x: point.x - 28,
            y: point.y - 28,
            width: 56,
            height: 56
        )

        context.fill(
            Path(ellipseIn: circleRect),
            with: .color(
                Color(.secondarySystemGroupedBackground)
            )
        )

        context.stroke(
            Path(ellipseIn: circleRect),
            with: .color(
                Color.accentColor.opacity(0.85)
            ),
            lineWidth: 3
        )

        let symbol = context.resolve(
            Image(
                systemName:
                    "dot.radiowaves.left.and.right"
            )
        )

        context.draw(
            symbol,
            at: point,
            anchor: .center
        )

        let title = context.resolve(
            Text(node.name)
                .font(
                    .caption.weight(.semibold)
                )
                .foregroundStyle(.primary)
        )

        context.draw(
            title,
            at: CGPoint(
                x: point.x,
                y: point.y + 39
            ),
            anchor: .center
        )

        if let detail = node.detail {
            let subtitle = context.resolve(
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            )

            context.draw(
                subtitle,
                at: CGPoint(
                    x: point.x,
                    y: point.y + 54
                ),
                anchor: .center
            )
        }
    }

    private func reflectedString(
        from value: Any,
        matching names: [String]
    ) -> String? {
        var currentMirror: Mirror? = Mirror(
            reflecting: value
        )

        while let mirror = currentMirror {
            for child in mirror.children {
                guard let label = child.label else {
                    continue
                }

                guard names.contains(label) else {
                    continue
                }

                if let string = unwrapString(
                    child.value
                ) {
                    let cleaned =
                        string.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )

                    if !cleaned.isEmpty {
                        return cleaned
                    }
                }
            }

            currentMirror = mirror.superclassMirror
        }

        return nil
    }

    private func unwrapString(
        _ value: Any
    ) -> String? {
        let mirror = Mirror(
            reflecting: value
        )

        if mirror.displayStyle == .optional {
            guard let child = mirror.children.first else {
                return nil
            }

            return unwrapString(child.value)
        }

        if let string = value as? String {
            return string
        }

        if let data = value as? Data {
            return data
                .map {
                    String(
                        format: "%02x",
                        $0
                    )
                }
                .joined()
        }

        return nil
    }

    private func shortenHash(
        _ hash: String
    ) -> String {
        let cleaned = hash
            .replacingOccurrences(
                of: " ",
                with: ""
            )
            .lowercased()

        guard cleaned.count > 12 else {
            return cleaned
        }

        return
            "\(cleaned.prefix(6))…\(cleaned.suffix(6))"
    }
}

private func dismissibleStatusBanner(
    title: String,
    message: String,
    isPresented: Binding<Bool>
) -> some View {
    HStack(spacing: 12) {
        Image(
            systemName:
                "antenna.radiowaves.left.and.right"
        )
        .font(.title3)
        .foregroundStyle(.blue)

        VStack(
            alignment: .leading,
            spacing: 3
        ) {
            Text(title)
                .font(
                    .subheadline.weight(.semibold)
                )

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Spacer()

        Button {
            isPresented.wrappedValue = false
        } label: {
            Image(systemName: "xmark")
                .font(
                    .caption.weight(.bold)
                )
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    Color.secondary.opacity(0.12)
                )
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss message")
    }
    .padding(14)
    .background(.ultraThinMaterial)
    .clipShape(
        RoundedRectangle(cornerRadius: 16)
    )
    .overlay {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                Color.secondary.opacity(0.2),
                lineWidth: 1
            )
    }
}
