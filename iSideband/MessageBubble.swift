import SwiftUI
import UIKit

struct MessageBubble: View {
    let text: String
    let date: Date
    let isOutgoing: Bool
    let status: String?

    let isPhoto: Bool
    let isFile: Bool

    let attachmentName: String?
    let attachmentPath: String?
    let attachmentSize: Int?

    @State private var selectedImage: UIImage?

    var body: some View {
        HStack {
            if isOutgoing {
                Spacer()
            }

            VStack(
                alignment: isOutgoing
                    ? .trailing
                    : .leading,
                spacing: 4
            ) {
                messageContent

                HStack(spacing: 5) {
                    Text(
                        date.formatted(
                            date: .omitted,
                            time: .shortened
                        )
                    )

                    if let status {
                        Text("•")
                        Text(status)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if !isOutgoing {
                Spacer()
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: {
                    selectedImage != nil
                },
                set: { isPresented in
                    if !isPresented {
                        selectedImage = nil
                    }
                }
            )
        ) {
            if let selectedImage {
                PhotoViewer(
                    image: selectedImage
                )
            }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        if isPhoto,
           let attachmentPath,
           let image = UIImage(
               contentsOfFile: attachmentPath
           ) {
            Button {
                selectedImage = image
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        maxWidth: 260,
                        maxHeight: 320
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
            }
            .buttonStyle(.plain)
        } else if isFile {
            fileBubble
        } else {
            textBubble
        }
    }

    private var textBubble: some View {
        Text(text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleColor)
            .foregroundStyle(
                isOutgoing
                    ? .white
                    : .primary
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
    }

    private var fileBubble: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.title2)

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(
                    attachmentName
                        ?? "Attachment"
                )
                .font(.subheadline.bold())
                .lineLimit(1)

                if let attachmentSize {
                    Text(
                        ByteCountFormatter.string(
                            fromByteCount:
                                Int64(attachmentSize),
                            countStyle: .file
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        isOutgoing
                            ? Color.white.opacity(0.8)
                            : .secondary
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(bubbleColor)
        .foregroundStyle(
            isOutgoing
                ? .white
                : .primary
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    private var bubbleColor: Color {
        isOutgoing
            ? Color.accentColor
            : Color.secondary.opacity(0.2)
    }
}
