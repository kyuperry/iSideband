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

    @State private var showMapStyleMenu = false
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

            mapStyleControls

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
        .animation(
            .easeInOut(duration: 0.2),
            value: showMapStyleMenu
        )
        .animation(
            .easeInOut(duration: 0.2),
            value: showInformationBanner
        )
    }

    private var mapStyleControls: some View {
        VStack {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 10
                ) {
                    Button {
                        showMapStyleMenu.toggle()
                    } label: {
                        Image(
                            systemName:
                                selectedMapStyle.icon
                        )
                        .font(
                            .body.weight(.semibold)
                        )
                        .frame(width: 40, height: 40)
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
                        "Choose map style"
                    )

                    if showMapStyleMenu {
                        mapStyleMenu
                            .transition(
                                .move(edge: .leading)
                                    .combined(
                                        with: .opacity
                                    )
                            )
                    }
                }

                Spacer()
            }

            Spacer()
        }
        .padding(.top, 4)
        .padding(.leading, 14)
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
        VStack(
            alignment: .leading,
            spacing: 4
        ) {
            ForEach(
                GeographicMapStyle.allCases
            ) { style in
                Button {
                    selectedMapStyle = style
                    showMapStyleMenu = false
                } label: {
                    HStack(spacing: 10) {
                        Image(
                            systemName: style.icon
                        )
                        .frame(width: 22)

                        Text(style.title)

                        Spacer()

                        if selectedMapStyle == style {
                            Image(
                                systemName: "checkmark"
                            )
                            .fontWeight(.semibold)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(width: 175)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
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
}

struct TopologyMeshMapView: View {
    @State private var showInformationBanner = true

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea(edges: .bottom)

            Canvas { context, size in
                let center = CGPoint(
                    x: size.width / 2,
                    y: size.height / 2
                )

                let topNode = CGPoint(
                    x: center.x,
                    y: center.y - 125
                )

                let leftNode = CGPoint(
                    x: center.x - 105,
                    y: center.y + 65
                )

                let rightNode = CGPoint(
                    x: center.x + 105,
                    y: center.y + 65
                )

                let lowerNode = CGPoint(
                    x: center.x,
                    y: center.y + 165
                )

                drawConnection(
                    from: topNode,
                    to: leftNode,
                    in: &context
                )

                drawConnection(
                    from: topNode,
                    to: rightNode,
                    in: &context
                )

                drawConnection(
                    from: leftNode,
                    to: rightNode,
                    in: &context
                )

                drawConnection(
                    from: leftNode,
                    to: lowerNode,
                    in: &context
                )

                drawConnection(
                    from: rightNode,
                    to: lowerNode,
                    in: &context
                )

                drawNode(
                    at: topNode,
                    label: "You",
                    in: &context
                )

                drawNode(
                    at: leftNode,
                    label: "Node A",
                    in: &context
                )

                drawNode(
                    at: rightNode,
                    label: "Node B",
                    in: &context
                )

                drawNode(
                    at: lowerNode,
                    label: "Node C",
                    in: &context
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 80)

            if showInformationBanner {
                VStack {
                    Spacer()

                    dismissibleStatusBanner(
                        title: "Topology Mesh Map",
                        message:
                            "Live Reticulum paths and discovered nodes will appear here later.",
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
    }

    private func drawConnection(
        from start: CGPoint,
        to end: CGPoint,
        in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        context.stroke(
            path,
            with: .color(
                Color.secondary.opacity(0.45)
            ),
            style: StrokeStyle(
                lineWidth: 2,
                dash: [7, 6]
            )
        )
    }

    private func drawNode(
        at point: CGPoint,
        label: String,
        in context: inout GraphicsContext
    ) {
        let circleSize = CGSize(
            width: 58,
            height: 58
        )

        let circleRect = CGRect(
            x: point.x - circleSize.width / 2,
            y: point.y - circleSize.height / 2,
            width: circleSize.width,
            height: circleSize.height
        )

        context.fill(
            Path(ellipseIn: circleRect),
            with: .color(Color.accentColor)
        )

        context.stroke(
            Path(ellipseIn: circleRect),
            with: .color(
                Color.white.opacity(0.9)
            ),
            lineWidth: 3
        )

        let symbol = context.resolve(
            Image(
                systemName:
                    "antenna.radiowaves.left.and.right"
            )
        )

        context.draw(
            symbol,
            at: point,
            anchor: .center
        )

        let text = context.resolve(
            Text(label)
                .font(
                    .caption.weight(.semibold)
                )
                .foregroundStyle(.primary)
        )

        context.draw(
            text,
            at: CGPoint(
                x: point.x,
                y: point.y + 42
            ),
            anchor: .center
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
