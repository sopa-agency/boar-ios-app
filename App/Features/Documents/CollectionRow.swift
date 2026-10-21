import BoarRAG
import SwiftUI

/// One imported collection: its name and document count, switched on or off for answers.
struct CollectionRow: View {
    let collection: KnowledgeBase.Collection
    @Bindable var documents: DocumentsController

    var body: some View {
        Toggle(isOn: $documents[activeFor: collection.id]) {
            Label {
                Text(verbatim: collection.name)
                Text("^[\(collection.docCount) document](inflect: true)")
            } icon: {
                Image(systemName: Symbols.collection)
            }
        }
        .accessibilityHint("When off, answers don't use this collection")
    }
}
