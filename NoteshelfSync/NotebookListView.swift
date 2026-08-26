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
    @Binding var refreshToken: String
    @Binding var isLoggedIn: Bool
    @Binding var pageIndex: Int

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
