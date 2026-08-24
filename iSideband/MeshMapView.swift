import SwiftUI
import MapKit
import CoreLocation
import Combine

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
        .navigationTitle("Situation Map")
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

    @AppStorage(RNodePreferenceKey.displayName)
    private var connectedRNodeLabel = "KPU5-1"

    @StateObject private var locationManager =
        MeshMapLocationManager()
    @ObservedObject private var reticulumCore =
        ReticulumCoreBridge.shared
    @ObservedObject private var contactStore =
        LXMFContactStore.shared

    @State private var cameraPosition: MapCameraPosition
    @State private var isShowingInformation = false
    @State private var hasCenteredOnFirstLocation = false
    @State private var selectedRemoteNode: RemoteNodeLocation?
    @State private var mapFreshnessDate = Date()

    private let mapFreshnessTimer = Timer.publish(
        every: 60,
        on: .main,
        in: .common
    ).autoconnect()

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
                if let coordinate =
                    locationManager.coordinate {
                    Annotation(
                        "",
                        coordinate: coordinate,
                        anchor: .bottom
                    ) {
                        geographicRNodeMarker
                    }
                }
                ForEach(remoteNodeLocations) { node in
                    Annotation(
                        remoteNodeLabel(node),
                        coordinate: node.coordinate,
                        anchor: .bottom
                    ) {
                        remoteNodeMarker(node)
                    }
                }
            }
            .mapStyle(selectedMapStyle.mapStyle)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea(edges: .bottom)

            currentLocationButton

            VStack {
                HStack {
                    mapInformationButton(
                        title: "Situation Map",
                        message:
                            "Your connected RNode is shown at this iPhone's live GPS position. Nodes that opt in to location sharing will appear here.",
                        isPresented: $isShowingInformation
                    )
                    Spacer()
                }
                Spacer()
            }
            .padding(.top, 12)
            .padding(.leading, 16)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                mapStyleMenu
            }
        }
        .sheet(item: $selectedRemoteNode) { node in
            RemoteNodeTelemetryView(
                node: node,
                displayName: remoteNodeLabel(node)
            )
            .presentationDetents([.medium])
        }
        .onAppear {
            locationManager.startUpdating()
        }
        .onDisappear {
            locationManager.stopUpdating()
        }
        .onChange(
            of: locationManager.coordinateKey
        ) { _, _ in
            centerOnFirstLocationIfNeeded()
        }
        .onReceive(mapFreshnessTimer) { date in
            mapFreshnessDate = date
        }
    }

    private var geographicRNodeMarker: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(
                        width: 58,
                        height: 58
                    )
                    .shadow(
                        color:
                            Color.black.opacity(0.16),
                        radius: 7,
                        y: 3
                    )

                Circle()
                    .stroke(
                        Color.accentColor,
                        lineWidth: 2.5
                    )
                    .frame(
                        width: 58,
                        height: 58
                    )

                Image(
                    systemName:
                        "antenna.radiowaves.left.and.right"
                )
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            }

            Text(connectedRNodeLabel)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(connectedRNodeLabel) at current GPS location"
        )
    }

    private var remoteNodeLocations: [RemoteNodeLocation] {
        Array(
            reticulumCore.remoteNodeLocations.values.filter {
                mapFreshnessDate.timeIntervalSince($0.receivedAt) <
                    ReticulumCoreBridge.remoteNodeStaleInterval
            }.sorted {
                $0.receivedAt > $1.receivedAt
            }.prefix(200)
        )
    }

    private func remoteNodeLabel(
        _ node: RemoteNodeLocation
    ) -> String {
        contactStore.contact(
            for: node.sourceHash
        )?.displayName ??
            "Sideband \(node.sourceHash.prefix(8))"
    }

    private func remoteNodeMarker(
        _ node: RemoteNodeLocation
    ) -> some View {
        Button {
            selectedRemoteNode = node
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 48, height: 48)
                        .shadow(
                            color: Color.black.opacity(0.16),
                            radius: 6,
                            y: 3
                        )

                    Circle()
                        .stroke(Color.orange, lineWidth: 2.5)
                        .frame(width: 48, height: 48)

                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.orange)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(remoteNodeLabel(node)) on Situation Map"
        )
        .accessibilityHint("Tap to show announced telemetry")
    }

    private var currentLocationButton: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                Button {
                    locationManager.startUpdating()

                    guard let coordinate =
                        locationManager.coordinate else {
                        cameraPosition = .userLocation(
                            followsHeading: false,
                            fallback: .automatic
                        )
                        return
                    }

                    withAnimation {
                        cameraPosition = .region(
                            MKCoordinateRegion(
                                center: coordinate,
                                span: MKCoordinateSpan(
                                    latitudeDelta: 0.025,
                                    longitudeDelta: 0.025
                                )
                            )
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
                    "Go to connected RNode location"
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

    private func centerOnFirstLocationIfNeeded() {
        guard !hasCenteredOnFirstLocation,
              let coordinate =
                locationManager.coordinate else {
            return
        }

        hasCenteredOnFirstLocation = true

        withAnimation {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(
                        latitudeDelta: 0.025,
                        longitudeDelta: 0.025
                    )
                )
            )
        }
    }
}

private struct RemoteNodeTelemetryView: View {
    let node: RemoteNodeLocation
    let displayName: String

    var body: some View {
        NavigationStack {
            Form {
                Section("Node") {
                    LabeledContent("Name", value: displayName)
                    LabeledContent("Destination") {
                        Text(node.sourceHash)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }

                Section("Announced Location") {
                    LabeledContent(
                        "Coordinates",
                        value: String(
                            format: "%.6f, %.6f",
                            node.latitude,
                            node.longitude
                        )
                    )
                    LabeledContent(
                        "Accuracy",
                        value: node.accuracy > 0
                            ? String(format: "±%.0f m", node.accuracy)
                            : "Unavailable"
                    )
                    if let telemetryDate = node.telemetryDate {
                        LabeledContent(
                            "Measured",
                            value: telemetryDate.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                    }
                    LabeledContent(
                        "Received",
                        value: node.receivedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    LabeledContent(
                        "Last Update",
                        value: node.receivedAt.formatted(
                            .relative(presentation: .named)
                        )
                    )
                }
            }
            .navigationTitle("Node Telemetry")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

final class MeshMapLocationManager:
    NSObject,
    ObservableObject,
    CLLocationManagerDelegate {

    @Published private(set) var coordinate:
        CLLocationCoordinate2D?

    private let manager = CLLocationManager()

    var coordinateKey: String {
        guard let coordinate else {
            return "none"
        }

        return String(
            format: "%.6f,%.6f",
            coordinate.latitude,
            coordinate.longitude
        )
    }

    override init() {
        super.init()

        manager.delegate = self
        manager.desiredAccuracy =
            kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }

    func startUpdating() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()

        case .authorizedAlways,
             .authorizedWhenInUse:
            manager.startUpdatingLocation()

        case .restricted,
             .denied:
            break

        @unknown default:
            break
        }
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        switch manager.authorizationStatus {
        case .authorizedAlways,
             .authorizedWhenInUse:
            manager.startUpdatingLocation()

        default:
            break
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last,
              location.horizontalAccuracy >= 0 else {
            return
        }

        DispatchQueue.main.async {
            self.coordinate = location.coordinate
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        privacySafeLog(
            "Mesh map location error: \(error.localizedDescription)"
        )
    }
}

struct TopologyMeshMapView: View {
    @AppStorage(RNodePreferenceKey.displayName)
    private var connectedRNodeLabel = "KPU5-1"

    @ObservedObject private var discoveredStore =
        ReticulumDiscoveredPeerStore.shared
    @ObservedObject private var reticulumCore =
        ReticulumCoreBridge.shared
    @ObservedObject private var contactStore =
        LXMFContactStore.shared
    @State private var isShowingInformation = false
    @State private var selectedPeer:
        ReticulumDiscoveredPeer?
    @State private var topologyZoom: CGFloat = 1
    @GestureState private var pinchZoom: CGFloat = 1

    private let dimAfter: TimeInterval = 5 * 60
    private let hideAfter =
        ReticulumCoreBridge.remoteNodeStaleInterval

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let peers = visiblePeers(at: now)

            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea(edges: .bottom)

                if peers.isEmpty {
                    emptyTopology
                } else {
                    liveTopology(
                        peers: peers,
                        now: now
                    )
                }

                VStack {
                    HStack {
                        mapInformationButton(
                            title: "Live Topology",
                            message:
                                "Nodes are arranged in stable rings by the number of mesh hops from your connected RNode.",
                            isPresented: $isShowingInformation
                        )
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, 12)
                .padding(.leading, 16)
            }
            .sheet(item: $selectedPeer) { peer in
                peerDetailsSheet(
                    peer: peer,
                    now: now
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func liveTopology(
        peers: [ReticulumDiscoveredPeer],
        now: Date
    ) -> some View {
        GeometryReader { geometry in
            let size = geometry.size

            let center = CGPoint(
                x: size.width / 2,
                y: size.height / 2
            )

            let positions = nodePositions(
                center: center,
                size: size,
                peers: peers
            )

            ZStack {
                Canvas { context, _ in
                    for (index, position) in positions.enumerated() {
                        guard peers.indices.contains(index) else {
                            continue
                        }

                        let peer = peers[index]
                        let age = max(
                            0,
                            now.timeIntervalSince(
                                lastRelevantUpdate(for: peer)
                            )
                        )

                        drawConnection(
                            from: center,
                            to: position,
                            age: age,
                            in: &context
                        )
                    }
                }

                connectedRNodeView
                    .position(center)
                    .zIndex(2)

                ForEach(
                    Array(peers.enumerated()),
                    id: \.element.id
                ) { index, peer in
                    if positions.indices.contains(index) {
                        peerNodeView(
                            peer: peer,
                            now: now
                        )
                        .position(positions[index])
                        .onTapGesture {
                            selectedPeer = peer
                        }
                        .zIndex(3)
                    }
                }
            }
            .scaleEffect(currentTopologyZoom, anchor: .center)
            .contentShape(Rectangle())
            .highPriorityGesture(topologyResetGesture)
            .simultaneousGesture(topologyMagnificationGesture)
        }
        .padding(.horizontal, 18)
        .padding(.top, 30)
        .padding(.bottom, 115)
    }

    private var connectedRNodeView: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(
                        Color(
                            .secondarySystemGroupedBackground
                        )
                    )
                    .frame(
                        width: 72,
                        height: 72
                    )
                    .shadow(
                        color:
                            Color.accentColor.opacity(0.20),
                        radius: 10
                    )

                Circle()
                    .stroke(
                        Color.accentColor,
                        lineWidth: 3
                    )
                    .frame(
                        width: 72,
                        height: 72
                    )

                Image(
                    systemName:
                        "antenna.radiowaves.left.and.right"
                )
                .font(
                    .system(
                        size: 28,
                        weight: .semibold
                    )
                )
                .foregroundStyle(Color.accentColor)
            }

            Text(connectedRNodeLabel)
                .font(
                    .caption.weight(.bold)
                )
                .foregroundStyle(.primary)

            Text("You")
                .font(.caption2)
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 110)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(connectedRNodeLabel), you"
        )
    }

    private func peerNodeView(
        peer: ReticulumDiscoveredPeer,
        now: Date
    ) -> some View {
        let age = max(
            0,
            now.timeIntervalSince(
                lastRelevantUpdate(for: peer)
            )
        )

        let isFresh = age < 10
        let opacity = nodeOpacity(for: age)

        return VStack(spacing: 5) {
            ZStack {
                if isFresh {
                    Circle()
                        .stroke(
                            Color.green.opacity(0.35),
                            lineWidth: 4
                        )
                        .frame(
                            width: 72,
                            height: 72
                        )
                }

                Circle()
                    .fill(
                        Color(
                            .secondarySystemGroupedBackground
                        )
                    )
                    .frame(
                        width: 58,
                        height: 58
                    )

                Circle()
                    .stroke(
                        isFresh
                            ? Color.green
                            : Color.accentColor.opacity(0.85),
                        lineWidth: 3
                    )
                    .frame(
                        width: 58,
                        height: 58
                    )

                Image(
                    systemName:
                        "dot.radiowaves.left.and.right"
                )
                .font(
                    .system(
                        size: 22,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    isFresh
                        ? Color.green
                        : Color.accentColor
                )
            }

            Text(displayName(for: peer))
                .font(
                    .caption.weight(.semibold)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(
                "\(hopLabel(for: peer)) • " +
                lastHeardText(peer, now: now)
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(width: 115)
        .opacity(opacity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(displayName(for: peer)), \(lastHeardText(peer, now: now))"
        )
    }

    private var emptyTopology: some View {
        VStack(spacing: 18) {
            Spacer()

            connectedRNodeView

            VStack(spacing: 6) {
                Text("No Recently Heard Nodes")
                    .font(.headline)

                Text(
                    "Reticulum nodes will animate into the topology when their announces are received."
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

    private func peerDetailsSheet(
        peer: ReticulumDiscoveredPeer,
        now: Date
    ) -> some View {
        NavigationStack {
            List {
                Section("Node") {
                    LabeledContent(
                        "Name",
                        value: displayName(for: peer)
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 6
                    ) {
                        Text("Destination Hash")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(peer.destinationHash)
                            .font(
                                .system(
                                    .footnote,
                                    design: .monospaced
                                )
                            )
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }

                Section("Activity") {
                    LabeledContent(
                        "Status",
                        value: statusText(
                            for: peer,
                            now: now
                        )
                    )

                    LabeledContent(
                        "First Seen",
                        value: peer.firstSeenAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )

                    LabeledContent(
                        "Last Seen",
                        value: peer.lastSeenAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )

                    LabeledContent(
                        "Last Heard",
                        value: lastHeardText(
                            peer,
                            now: now
                        )
                    )
                }

                Section {
                    Text(
                        "This connection represents a node announcement heard by your RNode. It does not yet prove a direct or multi-hop route."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(displayName(for: peer))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Done") {
                        selectedPeer = nil
                    }
                }
            }
        }
    }

    private func nodePositions(
        center: CGPoint,
        size: CGSize,
        peers: [ReticulumDiscoveredPeer]
    ) -> [CGPoint] {
        guard !peers.isEmpty else {
            return []
        }

        let groupedPeers = Dictionary(grouping: peers) {
            hopDistance(for: $0)
        }
        let maximumHop = max(groupedPeers.keys.max() ?? 1, 1)
        let horizontalRadius = min(size.width * 0.38, 155)
        let verticalRadius = min(size.height * 0.36, 225)

        var positionsByID: [UUID: CGPoint] = [:]
        for hop in groupedPeers.keys.sorted() {
            let peersAtHop = (groupedPeers[hop] ?? []).sorted {
                $0.destinationHash < $1.destinationHash
            }
            let ringScale = CGFloat(hop) / CGFloat(maximumHop)

            for (index, peer) in peersAtHop.enumerated() {
                let angle =
                    (Double(index) / Double(peersAtHop.count))
                    * Double.pi * 2 - Double.pi / 2
                positionsByID[peer.id] = CGPoint(
                    x: center.x + CGFloat(cos(angle)) *
                        horizontalRadius * ringScale,
                    y: center.y + CGFloat(sin(angle)) *
                        verticalRadius * ringScale
                )
            }
        }

        return peers.map { positionsByID[$0.id] ?? center }
    }

    private var topologyMagnificationGesture: some Gesture {
        MagnifyGesture()
            .updating($pinchZoom) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                topologyZoom = min(
                    max(topologyZoom * value.magnification, 0.25),
                    3
                )
            }
    }

    private var topologyResetGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                topologyZoom = 1
            }
    }

    private var currentTopologyZoom: CGFloat {
        min(max(topologyZoom * pinchZoom, 0.25), 3)
    }

    private func hopDistance(
        for peer: ReticulumDiscoveredPeer
    ) -> Int {
        Int(peer.announcedHops ?? 0) + 1
    }

    private func hopLabel(
        for peer: ReticulumDiscoveredPeer
    ) -> String {
        let hops = hopDistance(for: peer)
        return "\(hops) \(hops == 1 ? "hop" : "hops")"
    }

    private func drawConnection(
        from start: CGPoint,
        to end: CGPoint,
        age: TimeInterval,
        in context: inout GraphicsContext
    ) {
        let freshness = connectionFreshness(
            for: age
        )

        let lineColor = freshness.color
        let opacity = freshness.opacity

        var glow = Path()
        glow.move(to: start)
        glow.addLine(to: end)

        context.stroke(
            glow,
            with: .color(
                lineColor.opacity(
                    0.10 * opacity
                )
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
                lineColor.opacity(
                    0.62 * opacity
                )
            ),
            style: StrokeStyle(
                lineWidth:
                    age < 10
                        ? 2.6
                        : 2,
                lineCap: .round,
                dash: [7, 6]
            )
        )
    }

    private func connectionFreshness(
        for age: TimeInterval
    ) -> (
        color: Color,
        opacity: Double
    ) {
        if age < 60 {
            return (
                .green,
                1
            )
        }

        if age < 5 * 60 {
            return (
                .accentColor,
                0.95
            )
        }

        if age < 15 * 60 {
            return (
                .purple,
                0.75
            )
        }

        return (
            .secondary,
            0.50
        )
    }

    private func visiblePeers(
        at now: Date
    ) -> [ReticulumDiscoveredPeer] {
        discoveredStore.peers
            .filter { peer in
                now.timeIntervalSince(
                    lastRelevantUpdate(for: peer)
                ) < hideAfter
            }
            .sorted {
                lastRelevantUpdate(for: $0) >
                    lastRelevantUpdate(for: $1)
            }
    }

    private func nodeOpacity(
        for age: TimeInterval
    ) -> Double {
        guard age > dimAfter else {
            return 1
        }

        let fadeDuration =
            hideAfter - dimAfter

        let fadeProgress =
            (age - dimAfter)
            / fadeDuration

        return max(
            0.25,
            1 - fadeProgress
        )
    }

    private func statusText(
        for peer: ReticulumDiscoveredPeer,
        now: Date
    ) -> String {
        let age = now.timeIntervalSince(
            lastRelevantUpdate(for: peer)
        )

        if age < 10 {
            return "Just heard"
        }

        if age < dimAfter {
            return "Recently heard"
        }

        return "Stale"
    }

    private func lastHeardText(
        _ peer: ReticulumDiscoveredPeer,
        now: Date
    ) -> String {
        let seconds = max(
            0,
            Int(
                now.timeIntervalSince(
                    lastRelevantUpdate(for: peer)
                )
            )
        )

        if seconds < 5 {
            return "Now"
        }

        if seconds < 60 {
            return "<1 min"
        }

        let minutes = seconds / 60

        if minutes < 60 {
            return "\(minutes) \(minutes == 1 ? "min" : "mins")"
        }

        let hours = minutes / 60
        return "\(hours) \(hours == 1 ? "hr" : "hrs")"
    }

    private func lastRelevantUpdate(
        for peer: ReticulumDiscoveredPeer
    ) -> Date {
        let locationUpdate = remoteLocation(
            for: peer
        )?.receivedAt

        return max(
            peer.lastSeenAt,
            locationUpdate ?? .distantPast
        )
    }

    private func remoteLocation(
        for peer: ReticulumDiscoveredPeer
    ) -> RemoteNodeLocation? {
        reticulumCore.remoteNodeLocations.first {
            $0.key.caseInsensitiveCompare(
                peer.destinationHash
            ) == .orderedSame
        }?.value
    }

    private func displayName(
        for peer: ReticulumDiscoveredPeer
    ) -> String {
        contactStore.contact(
            for: peer.destinationHash
        )?.displayName ?? peer.resolvedDisplayName
    }
}


private struct RadioTowerGlyph: View {
    var body: some View {
        Canvas { context, size in
            let color = Color.accentColor
            let centerX = size.width / 2
            let topY = size.height * 0.24
            let baseY = size.height * 0.84

            var mast = Path()
            mast.move(
                to: CGPoint(
                    x: centerX,
                    y: topY
                )
            )
            mast.addLine(
                to: CGPoint(
                    x: size.width * 0.31,
                    y: baseY
                )
            )
            mast.move(
                to: CGPoint(
                    x: centerX,
                    y: topY
                )
            )
            mast.addLine(
                to: CGPoint(
                    x: size.width * 0.69,
                    y: baseY
                )
            )
            mast.move(
                to: CGPoint(
                    x: size.width * 0.31,
                    y: baseY
                )
            )
            mast.addLine(
                to: CGPoint(
                    x: size.width * 0.69,
                    y: baseY
                )
            )

            context.stroke(
                mast,
                with: .color(color),
                style: StrokeStyle(
                    lineWidth: 4,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            let braceLevels: [CGFloat] = [
                0.42,
                0.57,
                0.72
            ]

            for level in braceLevels {
                let y = size.height * level
                let progress =
                    (y - topY)
                    / (baseY - topY)

                let leftX =
                    centerX
                    + (
                        size.width * 0.31
                        - centerX
                    )
                    * progress

                let rightX =
                    centerX
                    + (
                        size.width * 0.69
                        - centerX
                    )
                    * progress

                var brace = Path()
                brace.move(
                    to: CGPoint(
                        x: leftX,
                        y: y
                    )
                )
                brace.addLine(
                    to: CGPoint(
                        x: rightX,
                        y: y
                    )
                )

                context.stroke(
                    brace,
                    with: .color(color),
                    style: StrokeStyle(
                        lineWidth: 2.5,
                        lineCap: .round
                    )
                )
            }

            let transmitterRect = CGRect(
                x: centerX - 5,
                y: topY - 5,
                width: 10,
                height: 10
            )

            context.fill(
                Path(ellipseIn: transmitterRect),
                with: .color(color)
            )

            drawWave(
                centerX: centerX,
                centerY: topY,
                radius: size.width * 0.20,
                startAngle: .degrees(205),
                endAngle: .degrees(335),
                in: &context,
                color: color
            )

            drawWave(
                centerX: centerX,
                centerY: topY,
                radius: size.width * 0.31,
                startAngle: .degrees(205),
                endAngle: .degrees(335),
                in: &context,
                color: color
            )
        }
    }

    private func drawWave(
        centerX: CGFloat,
        centerY: CGFloat,
        radius: CGFloat,
        startAngle: Angle,
        endAngle: Angle,
        in context: inout GraphicsContext,
        color: Color
    ) {
        var path = Path()

        path.addArc(
            center: CGPoint(
                x: centerX,
                y: centerY
            ),
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )

        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: 3.5,
                lineCap: .round
            )
        )
    }
}

private func mapInformationButton(
    title: String,
    message: String,
    isPresented: Binding<Bool>
) -> some View {
    Button {
        isPresented.wrappedValue.toggle()
    } label: {
        Image(systemName: "info.circle.fill")
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.blue, .ultraThinMaterial)
            .frame(width: 40, height: 40)
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(
                        Color.secondary.opacity(0.25),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: Color.black.opacity(0.14),
                radius: 5,
                y: 2
            )
    }
    .buttonStyle(.plain)
    .accessibilityLabel("About \(title)")
    .popover(isPresented: isPresented, arrowEdge: .top) {
        HStack(alignment: .top, spacing: 12) {
            Image(
                systemName:
                    "antenna.radiowaves.left.and.right"
            )
            .font(.title3)
            .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(idealWidth: 310)
        .presentationCompactAdaptation(.popover)
    }
}
