import SwiftUI

// One row in the notebook list: icon, name, and a sync dot.
//
// isSynced is a plain Bool passed in by the caller (NotebookListView) — this
// view holds no state of its own and does no comparison itself. The caller
// recomputes it fresh on every redraw by comparing SyncTable's last-upload
// record against the notebook's current mod time, so the dot can never go
// stale the way a cached value could.
struct NotebookCard: View {
    let notebook: String
    let isSynced: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            Button(action: onTap) {
                HStack {
                    Image(systemName: "book.closed.fill")
                        .foregroundColor(.indigo)
                    Text(notebook)
                    
                    Spacer()
                    
                    Circle()
                        .fill(isSynced ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x:0, y:2)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }
}
