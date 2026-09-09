import SwiftUI

// Popup for selecting notebooks and deleting them.
//
// Deletes on three fronts: NotebookStore.deleteNotebook removes the folder
// from disk, SyncTable.remove drops its upload-history row, and the in-memory
// `notebooks` array is filtered so the UI updates immediately.
//
// Not covered: the server never learns about the deletion —
// AWSSyncRemoteStore.deleteNotebookRemote is still a stub — so a notebook
// deleted here can still exist (and get re-synced back down, once download
// exists) on the AWS side.
struct DeleteNotebooksPopup: View {
    @Binding var isPresented: Bool
    @Binding var notebooks: [String]
    @Binding var selected: Set<String>

    var body: some View {
        VStack(spacing: 16) {
            Text("Delete Notebooks")
                .font(.headline)
            
            ForEach(notebooks, id: \.self) { notebook in
                HStack {
                    Text(notebook)
                    Spacer()
                    Image(systemName: selected.contains(notebook) ? "checkmark.square.fill" : "square")
                        .foregroundColor(.indigo)
                }
                .onTapGesture {
                    if selected.contains(notebook) {
                        selected.remove(notebook)
                    } else {
                        selected.insert(notebook)
                    }
                }
            }
            
            HStack {
                Button(action: {
                    selected.removeAll()
                    isPresented = false
                }) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                }
                
                Button(action: {
                    for notebook in selected {
                        NotebookStore.deleteNotebook(named: notebook)
                        SyncTable.remove(notebook: notebook)
                    }
                    notebooks.removeAll { selected.contains($0) }
                    selected.removeAll()
                    isPresented = false
                }) {
                    Text("Delete Selected")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .padding(.horizontal, 40)
    }
}
