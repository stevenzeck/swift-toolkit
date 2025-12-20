//
//  Copyright 2025 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Foundation
import ReadiumShared
import SwiftUI

final class LibraryViewModel: ObservableObject {
    @Published var books: [Book] = []
    @Published var error: IdentifiableError?

    private let libraryService: LibraryService
    private var subscriptions = Set<AnyCancellable>()

    var onSelectBook: ((Book) -> Void)?

    init(libraryService: LibraryService) {
        self.libraryService = libraryService

        libraryService.allBooks()
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case let .failure(error) = completion {
                    print("Error loading books: \(error)")
                }
            } receiveValue: { [weak self] newBooks in
                self?.books = newBooks
            }
            .store(in: &subscriptions)
    }

    func select(book: Book) {
        onSelectBook?(book)
    }

    func delete(book: Book) {
        Task {
            do {
                try await libraryService.remove(book)
            } catch {
                await MainActor.run {
                    self.error = IdentifiableError(error: UserError(error))
                }
            }
        }
    }

    func importURL(_ url: URL) {
        Task {
            do {
                guard let absoluteURL = AnyURL(string: url.absoluteString)?.absoluteURL else {
                    let err = NSError(domain: "TestApp", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
                    throw LibraryError.importFailed(err)
                }

                try await libraryService.importPublication(from: absoluteURL, sender: UIViewController()) { progress in
                    print("Import progress: \(progress)")
                }
            } catch {
                await MainActor.run {
                    self.error = IdentifiableError(error: UserError(error))
                }
            }
        }
    }

    func coverURL(for book: Book) -> URL? {
        book.cover?.url
    }
}

struct IdentifiableError: Identifiable {
    let id = UUID()
    let error: UserError
}
