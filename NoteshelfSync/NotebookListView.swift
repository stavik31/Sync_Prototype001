import SwiftUI

// The home screen: every notebook, as a tappable card.
//
// Tapping one loads its first page and opens the editor.
// The + button bottom-right creates a notebook; the trash top-right opens the
// multi-select delete popup.
//
// The circular arrow button in the header is the old sync button. Its body was
// stripped when the previous backend was removed and it does nothing right now.
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
    @Binding var refreshToken: String
    @Binding var isLoggedIn: Bool
    @Binding var pageIndex: Int
    @Binding var userId: String
    @State private var uploading = false

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
                            uploading = true
                            await UploadEngine.uploadAll(userId: userId, authToken: authToken)
                            syncedNotebooks = Set(notebooks.filter { SyncTable.record(for: $0) != nil })
                            uploading = false
                        }
                    }) {
                        if uploading {
                            ProgressView()
                                .frame(width: 45, height: 45)
                        } else {
                            Image(systemName: "icloud.and.arrow.up")
                                .font(.system(size: 25))
                                .foregroundColor(.black)
                                .padding(10)
                        }
                    }
                    .disabled(uploading)
                    
                    Button(action: {
// used to call fetchChanges, handle 401 refresh/retry, and write incoming notes — see SyncManager.swift history / P4
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
                        noteText = NotebookStore.loadPage(notebook, page: "\(NotebookStore.loadInfo(for: notebook)?.order.first ?? "").rtf")
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
