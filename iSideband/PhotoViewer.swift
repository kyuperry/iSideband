import SwiftUI
import UIKit

struct PhotoViewer: View {
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
                    .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
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
