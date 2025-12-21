//
//  Copyright 2025 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import ReadiumShared
import SwiftUI

struct LibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel

    @State private var showingAddMenu = false
    @State private var showingURLPrompt = false
    @State private var showingFileImporter = false
    @State private var downloadURLString = ""

    @State private var selectedBookSheet: BookSheet?

    let columns = [
        GridItem(.adaptive(minimum: 140), spacing: 20, alignment: .top),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                // `id: \.url` is needed because Book is not Identifiable
                ForEach(viewModel.books, id: \.url) { book in
                    PublicationCell(
                        title: book.title,
                        authors: book.authors,
                        coverURL: viewModel.coverURL(for: book)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.select(book: book)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            viewModel.delete(book: book)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        Button {
                            selectedBookSheet = BookSheet(book: book)
                        } label: {
                            Label("Info", systemImage: "info.circle")
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingFileImporter = true }) {
                        Label("Import file", systemImage: "doc.badge.plus")
                    }
                    Button(action: { showingURLPrompt = true }) {
                        Label("Import from URL", systemImage: "link.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Import from URL", isPresented: $showingURLPrompt) {
            TextField("URL", text: $downloadURLString)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                if let url = URL(string: downloadURLString) {
                    viewModel.importURL(url)
                }
                downloadURLString = ""
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.content],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first {
                    viewModel.importURL(url)
                }
            case let .failure(error):
                print("Import failed: \(error.localizedDescription)")
            }
        }
        .alert(item: $viewModel.error) { errorWrapper in
            Alert(
                title: Text("Error"),
                message: Text(errorWrapper.error.localizedDescription),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(item: $selectedBookSheet) { sheet in
            PublicationDetailLoader(book: sheet.book, viewModel: viewModel)
        }
    }
}

// Since book is not identifiable, we use url as the id for showing the sheet
struct BookSheet: Identifiable {
    let book: Book
    var id: String { book.url }
}
