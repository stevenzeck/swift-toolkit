//
//  Copyright 2025 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation

/// Represents a publication stored as a file on the local file system.
@available(*, unavailable, message: "Use an `AssetRetriever` instead. See the migration guide.")
public final class FileAsset: PublicationAsset {
    public init(url: URL, mediaType: String? = nil) {}
    public init(url: URL, mediaType: MediaType?) {}
}
