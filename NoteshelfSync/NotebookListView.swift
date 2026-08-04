import SwiftUI

struct NotebookListView: View {
    @Binding var syncedNotebooks: Set<String>
    @Binding var notebooks: [String]
    @Binding var openNotebook: String?
    @Binding var createPopup: Bool
    @Binding var deletePopup: Bool
    @Binding var newNotebookName: String
    @Binding var selectedForDeletion: Set<String>
    @Binding var noteText: String
    @Binding var lastSavedText: String
    @Binding var authToken: String

    var body: some View {
        ZStack {
            
            VStack(spacing: 0){
                Color.indigo
                    .frame(height: 80)
                
                
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 5)
                
                HStack {
                    
                    Text("Notebooks")
                        .padding()
                        .font(.title)
                        .bold()
                    Spacer()
                    
                    Button(action: {
                        Task {
                            let changes = await SyncManager.fetchChanges(since: "2026-07-01T00:00:00Z", authToken: authToken)
                            for change in changes {
                                if let notebookId = change["notebookId"] as? String,
                                   let fileContent = change["fileContent"] as? String {
                                    NotesFileManager.saveNote(for: notebookId, content: fileContent)
                                    if !notebooks.contains(notebookId) {
                                        notebooks.append(notebookId)
                                    }
                                    syncedNotebooks.insert(notebookId)
                                }
                            }
                        }
                    }){
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 25))
                            .foregroundColor(.black)
                            .padding(10)
                    }
                    
                    Button(action: {
                        deletePopup = true
                    }){
                        Image(systemName: "trash")
                            .font(.system(size: 25))
                            .foregroundColor(.red)
                            .padding(15)
                    }
                }
                
                ForEach(notebooks, id: \.self) { notebook in
                    NotebookCard(notebook: notebook, isSynced: syncedNotebooks.contains(notebook), onTap: {
                        noteText = NotesFileManager.loadNote(for: notebook)
                        lastSavedText = noteText
                        openNotebook = notebook
                    })
                }
                
                Spacer()
            }
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        createPopup = true
                    }) {
                        Image(systemName: "plus")
                            .foregroundColor(.black)
                            .frame(width: 56, height: 56)
                            .background(Color.indigo)
                            .clipShape(Circle())
                    }
                    .padding()
                }
            }
            
            if createPopup {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                
                CreateNotebookPopup(isPresented: $createPopup, notebooks: $notebooks)
            }
            
            if deletePopup {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                
                DeleteNotebooksPopup(isPresented: $deletePopup, notebooks: $notebooks, selected: $selectedForDeletion)
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}
