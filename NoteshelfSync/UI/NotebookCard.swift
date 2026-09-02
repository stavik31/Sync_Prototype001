import SwiftUI

// One row in the notebook list: icon, name, and a sync dot.
//
// The dot is green when isSynced is true. That currently comes from
// syncedNotebooks, which is held in memory only and resets to empty on every
// launch — so it reflects "synced during this session", not the real state.
// Reading it from SyncTable instead would make it survive a restart.
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
