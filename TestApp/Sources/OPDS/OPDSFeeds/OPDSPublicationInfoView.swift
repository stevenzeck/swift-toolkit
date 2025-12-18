//
//  Copyright 2025 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import ReadiumShared
import SwiftUI

struct OPDSPublicationInfoView: View {
    let publication: Publication
    let download: (ReadiumShared.Link, @escaping (Double) -> Void) async throws -> Book

    @State private var isDownloading = false
    @State private var alert: AlertMessage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 20) {
                    coverView
                        .frame(width: 120, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(publication.metadata.title ?? "")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)

                        Text(publication.metadata.authors.map(\.name).joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                if let description = publication.metadata.description {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("About")
                            .font(.headline)

                        Text(description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            if let downloadLink = publication.downloadLinks.first {
                VStack {
                    Button(action: {
                        Task {
                            await download(link: downloadLink)
                        }
                    }) {
                        HStack {
                            if isDownloading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Download")
                                    .fontWeight(.bold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isDownloading)
                }
                .padding()
                .background(.bar)
                .overlay(Divider(), alignment: .top)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $alert) { message in
            Alert(title: Text(message.title), message: Text(message.message), dismissButton: .cancel())
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var coverView: some View {
        if let coverURL = imageURL {
            AsyncImage(url: coverURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if phase.error != nil {
                    PlaceholderView(publication: publication)
                } else {
                    ZStack {
                        Color(.secondarySystemBackground)
                        ProgressView()
                    }
                }
            }
        } else {
            PlaceholderView(publication: publication)
        }
    }

    // MARK: - Logic

    private var imageURL: URL? {
        let primaryURL = publication.coverLink?.url(relativeTo: publication.baseURL).httpURL?.url
        let fallbackURL = publication.images.first?.url(relativeTo: publication.baseURL).httpURL?.url
        return primaryURL ?? fallbackURL
    }

    private func download(link: ReadiumShared.Link) async {
        isDownloading = true
        do {
            let book = try await download(link) { _ in }
            alert = AlertMessage(
                title: NSLocalizedString("success_title", comment: "Title of the alert when a publication is successfully downloaded"),
                message: String(format: NSLocalizedString("library_download_success_message", comment: "Message of the alert when a publication is successfully downloaded"), book.title)
            )
        } catch {
            alert = AlertMessage(
                title: NSLocalizedString("error_title", comment: "Title of the alert when an error occurred"),
                message: error.localizedDescription
            )
        }
        isDownloading = false
    }

    struct AlertMessage: Identifiable {
        var id: String { title + message }
        let title: String
        let message: String
    }

    struct PlaceholderView: View {
        let publication: Publication

        var body: some View {
            GeometryReader { _ in
                ZStack {
                    Color(red: 0.06, green: 0.18, blue: 0.25)

                    VStack {
                        if let title = publication.metadata.title {
                            Text(title)
                            Text("_________")
                        }

                        Text(publication.metadata.authors.map(\.name).joined(separator: ", "))
                    }
                    .font(.system(size: 9))
                    .foregroundColor(Color(red: 0.86, green: 0.86, blue: 0.86))
                    .padding()
                }
                .border(Color(red: 0.08, green: 0.26, blue: 0.36), width: 5)
            }
        }
    }
}

private extension Publication {
    /// Finds the first link with `cover` or thumbnail relations.
    var coverLink: ReadiumShared.Link? {
        links.firstWithRel(.cover)
            ?? links.firstWithRel("http://opds-ps.org/image")
            ?? links.firstWithRel("http://opds-ps.org/image/thumbnail")
    }
}
