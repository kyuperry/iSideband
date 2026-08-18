import CoreTransferable
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum PhotoAttachmentError: LocalizedError {
    case couldNotLoad
    case unsupportedFormat
    case couldNotCompress

    var errorDescription: String? {
        switch self {
        case .couldNotLoad:
            return "The selected photo could not be downloaded from the photo library."
        case .unsupportedFormat:
            return "The selected item is not a supported HEIC, PNG, or JPEG photo."
        case .couldNotCompress:
            return "The selected photo could not be compressed to 20 KB."
        }
    }
}

private struct TransferablePhotoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .image) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            let source = received.file
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(
                    source.pathExtension.isEmpty ? "image" : source.pathExtension
                )
            try FileManager.default.copyItem(at: source, to: destination)
            return Self(url: destination)
        }
    }
}

enum PhotoAttachmentProcessor {
    static let maximumBytes = 20_000

    static func prepare(_ item: PhotosPickerItem) async throws -> Data {
        let sourceData: Data
        do {
            if let data = try? await item.loadTransferable(type: Data.self) {
                sourceData = data
            } else if let file = try await item.loadTransferable(
                type: TransferablePhotoFile.self
            ) {
                defer { try? FileManager.default.removeItem(at: file.url) }
                sourceData = try Data(contentsOf: file.url, options: .mappedIfSafe)
            } else {
                throw PhotoAttachmentError.couldNotLoad
            }
        } catch let error as PhotoAttachmentError {
            throw error
        } catch {
            throw PhotoAttachmentError.couldNotLoad
        }

        guard let image = UIImage(data: sourceData) else {
            throw PhotoAttachmentError.unsupportedFormat
        }
        guard let compressed = jpegData(
            from: image,
            maximumBytes: maximumBytes
        ) else {
            throw PhotoAttachmentError.couldNotCompress
        }
        return compressed
    }

    static func jpegData(
        from image: UIImage,
        maximumBytes: Int = maximumBytes
    ) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else {
            return nil
        }

        var maximumDimension: CGFloat = min(
            max(image.size.width, image.size.height),
            1_600
        )

        while maximumDimension >= 96 {
            let scale = min(
                1,
                maximumDimension / max(image.size.width, image.size.height)
            )
            let targetSize = CGSize(
                width: max(1, (image.size.width * scale).rounded()),
                height: max(1, (image.size.height * scale).rounded())
            )
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let normalized = UIGraphicsImageRenderer(
                size: targetSize,
                format: format
            ).image { context in
                UIColor.black.setFill()
                context.fill(CGRect(origin: .zero, size: targetSize))
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }

            var lower: CGFloat = 0.04
            var upper: CGFloat = 0.86
            var best: Data?
            for _ in 0..<8 {
                let quality = (lower + upper) / 2
                guard let candidate = normalized.jpegData(
                    compressionQuality: quality
                ) else {
                    return nil
                }
                if candidate.count <= maximumBytes {
                    best = candidate
                    lower = quality
                } else {
                    upper = quality
                }
            }
            if let best {
                return best
            }
            maximumDimension *= 0.78
        }
        return nil
    }
}
