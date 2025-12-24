//
//  Copyright 2025 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Foundation
import ReadiumShared
import ReadiumStreamer
import SwiftUI
import UIKit

protocol LibraryModuleAPI {
    var delegate: LibraryModuleDelegate? { get set }
    /// Root navigation controller containing the Library.
    /// Can be used to present the library to the user.
    var rootViewController: UINavigationController { get }

    /// Imports a new publication to the library, either from:
    /// - a local file URL
    /// - a remote URL which will be streamed
    @discardableResult
    func importPublication(
        from url: AbsoluteURL,
        sender: UIViewController,
        progress: @escaping (Double) -> Void
    ) async throws -> Book
}

protocol LibraryModuleDelegate: ModuleDelegate {
    /// Called when the user tap on a publication in the library.
    func libraryDidSelectPublication(_ publication: Publication, book: Book)
}

final class LibraryModule: LibraryModuleAPI {
    weak var delegate: LibraryModuleDelegate?

    private let library: LibraryService
    private let hostingController: UIHostingController<LibraryView>

    init(
        delegate: LibraryModuleDelegate?,
        books: BookRepository,
        readium: Readium
    ) {
        self.delegate = delegate

        let lcp = LCPModule(readium: readium)
        library = LibraryService(books: books, readium: readium, lcp: lcp)

        let viewModel = LibraryViewModel(libraryService: library)
        let view = LibraryView(viewModel: viewModel)
        hostingController = UIHostingController(rootView: view)

        rootViewController.tabBarItem = UITabBarItem(
            title: NSLocalizedString("Library", comment: "Library tab title"),
            image: UIImage(systemName: "books.vertical"),
            selectedImage: UIImage(systemName: "books.vertical.fill")
        )
        rootViewController.navigationBar.prefersLargeTitles = true

        viewModel.onSelectBook = { [weak self] book in
            self?.open(book: book)
        }
    }

    private(set) lazy var rootViewController: UINavigationController = .init(rootViewController: hostingController)

    func importPublication(
        from url: AbsoluteURL,
        sender: UIViewController,
        progress: @escaping (Double) -> Void
    ) async throws -> Book {
        try await library.importPublication(from: url, sender: sender, progress: progress)
    }

    private func open(book: Book) {
        Task {
            do {
                if let pub = try await library.openBook(book, sender: hostingController) {
                    delegate?.libraryDidSelectPublication(pub, book: book)
                }
            } catch {
                print("Error opening book: \(error)")
                if let error = error as? UserErrorConvertible {
                    delegate?.presentError(error, from: rootViewController)
                }
            }
        }
    }
}
