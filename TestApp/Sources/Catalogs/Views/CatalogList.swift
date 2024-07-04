//
//  Copyright 2024 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import ReadiumOPDS
import SwiftUI

/// Screen of list of catalog feeds, first in the stack
struct CatalogList: View {
    let catalogRepository: CatalogRepository
    let catalogFeed: (Catalog) -> CatalogFeed
    let publicationDetail: (OPDSPublication) -> PublicationDetail

    @State private var showingSheet = false
    @State private var showingAlert = false
    @State private var catalogs: [Catalog] = []

    var body: some View {
        NavigationStack {
            VStack {
                List {
                    ForEach(catalogs, id: \.id) { catalog in
                        /// Use the `value` argument for navigationDestination to use.
                        /// In this case, it is a catalog of type `Catalog`. See below navigationDestination comment.
                        NavigationLink(value: catalog) {
                            ListRowItem(title: catalog.title)
                        }
                    }
                    .onDelete { offsets in
                        let catalogIds = offsets.map { catalogs[$0].id! }
                        Task {
                            try await deleteCatalogs(ids: catalogIds)
                        }
                    }
                }
                .onReceive(catalogRepository.all()
                    .replaceError(with: nil))
                { catalogsOrNil in
                    if let catalogs = catalogsOrNil {
                        self.catalogs = catalogs
                    } else {
                        print("Error fetching catalogs")
                    }
                }
                .listStyle(DefaultListStyle())
            }
            .navigationTitle("Catalogs")
            /// We define the different destinations here, which are applicable to everywhere in the stack.
            /// Use the `for` argument to pass the type of data. This should match what is being passed in NavigationLink.
            /// In the first case below, it is of type `Catalog`, the same as NavigationLink above.
            .navigationDestination(for: Catalog.self) { catalog in
                catalogFeed(catalog)
            }
            .navigationDestination(for: OPDSPublication.self) { opdsPublication in
                publicationDetail(opdsPublication)
            }
            .toolbar(content: toolbarContent)
        }
        .sheet(isPresented: $showingSheet) {
            AddFeedSheet { title, url in
                Task {
                    try await addCatalog(title: title, url: url)
                }
            }
        }
        .alert("Error", isPresented: $showingAlert, actions: {
            Button("OK", role: .cancel, action: {})
        }, message: {
            Text("Feed is not valid, please try again.")
        })
    }

    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(.add, action: {
                showingSheet = true
            })
        }
    }
}

extension CatalogList {
    func addCatalog(title: String, url: String) async throws {
        do {
            guard let catalogURL = URL(string: url) else {
                showingAlert = true
                return
            }
            OPDSParser.parseURL(url: catalogURL) { _, _ in }
            var savedCatalog = Catalog(title: title, url: url)
            try await catalogRepository.save(&savedCatalog)
        } catch {
            showingAlert = true
        }
    }

    func deleteCatalogs(ids: [Catalog.Id]) async throws {
        try? await catalogRepository.delete(ids: ids)
    }
}
