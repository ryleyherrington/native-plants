import SwiftUI
import UIKit

struct BundleImage: View {
    let name: String
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            if let image = loadImage(named: name) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Image(systemName: "leaf")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .accessibilityHidden(true)
    }

    private func loadImage(named name: String) -> UIImage? {
        guard let url = Bundle.main.url(
            forResource: (name as NSString).deletingPathExtension,
            withExtension: (name as NSString).pathExtension,
            subdirectory: "Images"
        ) else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
}
