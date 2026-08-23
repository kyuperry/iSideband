import SwiftUI
import UIKit

struct PhotoViewer: View {
    @Environment(\.nightVisionModeEnabled) private var isNightVisionEnabled
    let image: UIImage

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .saturation(isNightVisionEnabled ? 0 : 1)
                    .colorMultiply(
                        isNightVisionEnabled
                            ? NightVisionPalette.primary
                            : .white
                    )
                    .brightness(isNightVisionEnabled ? -0.22 : 0)
                    .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(
                        isNightVisionEnabled
                            ? NightVisionPalette.primary
                            : .white
                    )
                }
            }
        }
    }
}

#Preview {
    PhotoViewer(
        image: UIImage(systemName: "photo")!
    )
}
