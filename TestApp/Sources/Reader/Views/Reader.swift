//
//  Copyright 2024 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import SwiftUI

struct Reader: View {
    @State private var isFullScreen = true

    var book: Book

    var body: some View {
        VStack {
            Text("Reader")
                .font(.title2)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(isFullScreen ? .hidden : .visible, for: .navigationBar)
        .statusBar(hidden: isFullScreen)
        .onTapGesture {
            withAnimation {
                isFullScreen.toggle()
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}
