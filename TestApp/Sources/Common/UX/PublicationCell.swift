//
//  Copyright 2025 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import ReadiumShared
import SwiftUI

struct PublicationCell: View {
    let title: String
    let authors: String?
    let coverURL: URL?

    private let coverHeight: CGFloat = 200
    private let coverWidth: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            coverImage
                .frame(width: coverWidth, height: coverHeight)
                .cornerRadius(8)
                .shadow(radius: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .foregroundColor(.primary)

                if let authors = authors {
                    Text(authors)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: coverWidth)
    }

    @ViewBuilder
    private var coverImage: some View {
        if let url = coverURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    Color(white: 0.9)
                        .overlay(ProgressView())
                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(white: 0.9)
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundColor(.gray)
        }
    }
}
