//
//  Copyright 2025 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import ReadiumShared
import SwiftUI

struct PublicationDetailLoader: View {
    let book: Book
    @ObservedObject var viewModel: LibraryViewModel
    @Environment(\.dismiss) var dismiss

    @State private var publication: Publication?

    var body: some View {
        NavigationView {
            Group {
                if let publication = publication {
                    PublicationMetadataView(publication: publication)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { dismiss() }
                            }
                        }
                } else {
                    ProgressView()
                        .onAppear {
                            loadPublication()
                        }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func loadPublication() {
        Task {
            do {
                publication = try await viewModel.openPublication(book: book)
            } catch {
                print("Failed to load publication: \(error)")
            }
        }
    }
}
