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

    @StateObject private var locationManager =
        MeshMapLocationManager()

    @State private var cameraPosition: MapCameraPosition
    @State private var showInformationBanner = true
    @State private var hasCenteredOnFirstLocation = false

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
                            "Your connected RNode is shown at this iPhone's live GPS position. Nodes that opt in to location sharing will appear here.",
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
        .animation(
            .easeInOut(duration: 0.2),
            value: showInformationBanner
        )
    }

    private var geographicRNodeMarker: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(Color(.white).opacity(0.88))
                    .frame(
                        width: 50,
                        height: 50
                    )
                    .shadow(
                        color: Color.black.opacity(0.14),
                        radius: 5,
                        y: 2
                    )

                Circle()
                    .stroke(
                        Color.accentColor,
                        lineWidth: 2.5
                    )
                    .frame(
                        width: 54,
                        height: 54
                    )

                RadioTowerGlyph()
                    .foregroundStyle(
                        Color.accentColor
                    )
                    .frame(
                        width: 39,
                        height: 39
                    )
            }

            Text("RNode 4272")
                .font(
                    .caption2.weight(.bold)
                )
                .foregroundStyle(.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(
                            Color.secondary.opacity(0.2),
                            lineWidth: 1
                        )
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Connected RNode at current GPS location"
        )
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
        print(
            "Mesh map location error: \(error.localizedDescription)"
        )
    }
}

struct TopologyMeshMapView: View {
    @ObservedObject private var discoveredStore =
        ReticulumDiscoveredPeerStore.shared

    @State private var showInformationBanner = true
    @State private var selectedPeer:
        ReticulumDiscoveredPeer?

    private let dimAfter: TimeInterval = 5 * 60
    private let hideAfter: TimeInterval = 30 * 60

    var body: some View {
        TimelineView(
            .animation(minimumInterval: 1.0 / 30.0)
        ) { timeline in
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

                if showInformationBanner {
                    VStack {
                        Spacer()

                        dismissibleStatusBanner(
                            title: "Live Topology",
                            message:
                                "Recently heard Reticulum nodes appear around your connected RNode. Older nodes gradually dim and disappear.",
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
                .spring(
                    response: 0.55,
                    dampingFraction: 0.78
                ),
                value: peers.map(\.id)
            )
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
                count: peers.count
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
                                peer.lastSeenAt
                            )
                        )

                        drawConnection(
                            from: center,
                            to: position,
                            age: age,
                            now: now,
                            in: &context
                        )
                    }
                }

                connectedRNodeView(now: now)
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
                        .transition(
                            .scale(scale: 0.45)
                                .combined(with: .opacity)
                        )
                        .onTapGesture {
                            selectedPeer = peer
                        }
                        .zIndex(3)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 30)
        .padding(.bottom, 115)
    }

    private func connectedRNodeView(
        now: Date
    ) -> some View {
        let cycleDuration = 2.6
        let cycle =
            now.timeIntervalSinceReferenceDate
                .truncatingRemainder(
                    dividingBy: cycleDuration
                )
            / cycleDuration

        return VStack(spacing: 7) {
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let delayedProgress =
                        (
                            cycle
                            - Double(index) * 0.18
                            + 1
                        )
                        .truncatingRemainder(
                            dividingBy: 1
                        )

                    Circle()
                        .stroke(
                            Color.accentColor.opacity(
                                max(
                                    0,
                                    0.24
                                    * (
                                        1
                                        - delayedProgress
                                    )
                                )
                            ),
                            lineWidth: 2
                        )
                        .frame(
                            width: 96,
                            height: 96
                        )
                        .scaleEffect(
                            1
                            + delayedProgress * 0.48
                        )
                }

                Circle()
                    .fill(
                        Color(
                            .secondarySystemGroupedBackground
                        )
                    )
                    .frame(
                        width: 96,
                        height: 96
                    )
                    .shadow(
                        color: Color.black.opacity(0.14),
                        radius: 5,
                        y: 2
                    )

                Circle()
                    .stroke(
                        Color.accentColor,
                        lineWidth: 3
                    )
                    .frame(
                        width: 80,
                        height: 90
                    )

                RadioTowerGlyph()
                    .foregroundStyle(
                        Color.accentColor
                    )
                    .frame(
                        width: 66,
                        height: 66
                    )
            }

            Text("RNode 4272")
                .font(
                    .caption.weight(.bold)
                )
                .foregroundStyle(.primary)

            Text("You")
                .font(.caption2)
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 100)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Connected RNode, you"
        )
    }

    private func peerNodeView(
        peer: ReticulumDiscoveredPeer,
        now: Date
    ) -> some View {
        let age = max(
            0,
            now.timeIntervalSince(peer.lastSeenAt)
        )

        let isFresh = age < 10
        let opacity = nodeOpacity(for: age)

        let pulse =
            isFresh
            ? 1.0 + (
                0.08
                * sin(
                    now.timeIntervalSinceReferenceDate
                    * 4
                )
            )
            : 1.0

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
                        .scaleEffect(pulse)
                }

                Circle()
                    .fill(
                        Color(
                            .secondarySystemGroupedBackground
                        )
                    )
                    .frame(
                        width: 52,
                        height: 60
                    )

                Circle()
                    .stroke(
                        isFresh
                            ? Color.green
                            : Color.accentColor.opacity(0.85),
                        lineWidth: 2
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
                        size: 18,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    isFresh
                        ? Color.green
                        : Color.accentColor
                )
                .frame(
                    width: 52,
                    height: 60,
                    alignment: .center
                )
                .offset(y: 1)
            }

            Text(peer.resolvedDisplayName)
                .font(
                    .caption.weight(.semibold)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(
                lastHeardText(
                    peer,
                    now: now
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(width: 110)
        .opacity(opacity)
        .scaleEffect(
            isFresh
                ? pulse
                : 1
        )
        .animation(
            .spring(
                response: 0.38,
                dampingFraction: 0.72
            ),
            value: peer.lastSeenAt
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(peer.resolvedDisplayName), \(lastHeardText(peer, now: now))"
        )
    }

    private var emptyTopology: some View {
        VStack(spacing: 18) {
            Spacer()

            connectedRNodeView(now: Date())

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
                        value: peer.resolvedDisplayName
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
            .navigationTitle(peer.resolvedDisplayName)
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
        count: Int
    ) -> [CGPoint] {
        guard count > 0 else {
            return []
        }

        let displayedCount = min(count, 12)

        let horizontalRadius = min(
            max(115, size.width * 0.34),
            165
        )

        let verticalRadius = min(
            max(125, size.height * 0.28),
            210
        )

        return (0..<displayedCount).map { index in
            let angle =
                (
                    Double(index)
                    / Double(displayedCount)
                )
                * Double.pi
                * 2
                - Double.pi / 2

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
        age: TimeInterval,
        now: Date,
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

        let dashPhase = CGFloat(
            now.timeIntervalSinceReferenceDate
                .truncatingRemainder(
                    dividingBy: 14
                )
        )

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
                dash: [7, 6],
                dashPhase: -dashPhase
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
                    peer.lastSeenAt
                ) < hideAfter
            }
            .sorted {
                $0.lastSeenAt > $1.lastSeenAt
            }
            .prefix(12)
            .map { $0 }
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
            peer.lastSeenAt
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
                    peer.lastSeenAt
                )
            )
        )

        if seconds < 5 {
            return "Heard now"
        }

        if seconds < 60 {
            return "Heard \(seconds)s ago"
        }

        let minutes = seconds / 60

        if minutes < 60 {
            return "Heard \(minutes)m ago"
        }

        let hours = minutes / 60
        return "Heard \(hours)h ago"
    }
}


private struct RadioTowerGlyph: View {
    var body: some View {
        Canvas { context, size in
            let color = Color.accentColor
            let centerX = size.width / 2

            let transmitterCenter = CGPoint(
                x: centerX,
                y: size.height * 0.31
            )

            let transmitterRadius =
                min(size.width, size.height) * 0.105

            let mastWidth =
                min(size.width, size.height) * 0.13

            let mastTop =
                transmitterCenter.y
                + transmitterRadius * 0.55

            let mastBottom =
                size.height * 0.87

            let mastRect = CGRect(
                x: centerX - mastWidth / 2,
                y: mastTop,
                width: mastWidth,
                height: mastBottom - mastTop
            )

            context.fill(
                Path(
                    roundedRect: mastRect,
                    cornerRadius: mastWidth / 2
                ),
                with: .color(color)
            )

            let transmitterRect = CGRect(
                x:
                    transmitterCenter.x
                    - transmitterRadius,
                y:
                    transmitterCenter.y
                    - transmitterRadius,
                width: transmitterRadius * 2,
                height: transmitterRadius * 2
            )

            context.fill(
                Path(ellipseIn: transmitterRect),
                with: .color(color)
            )

            drawWavePair(
                radius:
                    min(size.width, size.height)
                    * 0.27,
                center: transmitterCenter,
                color: color,
                in: &context
            )

            drawWavePair(
                radius:
                    min(size.width, size.height)
                    * 0.43,
                center: transmitterCenter,
                color: color,
                in: &context
            )
        }
        .accessibilityHidden(true)
    }

    private func drawWavePair(
        radius: CGFloat,
        center: CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let lineWidth = max(
            2.5,
            radius * 0.13
        )

        var leftWave = Path()
        leftWave.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(130),
            endAngle: .degrees(230),
            clockwise: false
        )

        context.stroke(
            leftWave,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round
            )
        )

        var rightWave = Path()
        rightWave.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-50),
            endAngle: .degrees(50),
            clockwise: false
        )

        context.stroke(
            rightWave,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round
            )
        )
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
