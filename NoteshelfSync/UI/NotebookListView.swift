import SwiftUI

// The home screen: every notebook, as a tappable card.
//
// Tapping one loads its first page and opens the editor.
// The + button bottom-right creates a notebook; the trash top-right opens the
// multi-select delete popup.
//
// The circular arrow button in the header is the download/refresh button.
// It's intentionally still dead — no body — because it depends on
// AWSSyncRemoteStore.downloadNotebook, which is still a stub. Only once
// download is real does this get wired up; this isn't a forgotten TODO.
struct NotebookListView: View {

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
    @State private var downloading = false

    var body: some View {
        ZStack {
            
            VStack(spacing: 0){
                ZStack(alignment: .trailing) {
                    Color.indigo
                    
                    Button(action: {
                        KeychainManager.delete(key: "authToken")
                        KeychainManager.delete(key: "refreshToken")
                        authToken = ""
                        refreshToken = ""
                        userId = ""
                        isLoggedIn = false
                    }) {
                        Text("Logout")
                            .font(.system(size: 19))
                            .foregroundColor(.white)
                            .padding(.trailing, 20)
                            .padding(.top, 20)
                    }
                }
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
                            downloading = true
                            let packages = await SyncAPI.listPackages(authToken: authToken) ?? []
                            for package in packages {
                                _ = await DownloadEngine.syncNotebook(package: package, authToken: authToken)
                            }
                            notebooks = NotebookStore.listNotebooks()
                            downloading = false
                        }
                    }) {
                        if downloading {
                            ProgressView()
                                .frame(width: 45, height: 45)
                        } else {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.system(size: 25))
                                .foregroundStyle(.black)
                                .padding(10)
                        }
                    }
                    .disabled(downloading)
                    
                    Button(action: {
                        Task {
                            uploading = true
                            await UploadEngine.uploadAll(userId: userId, authToken: authToken)

                            // SyncAPI clears both Keychain entries itself if a mid-upload
                            // refresh fails — nothing propagates that back to isLoggedIn
                            // directly, so this is how the UI notices the session died
                            // during this call rather than waiting for next launch.
                            if KeychainManager.load(key: "authToken") == nil {
                                authToken = ""
                                refreshToken = ""
                                userId = ""
                                isLoggedIn = false
                            }
                            

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
                        // Empty on purpose — see the comment above the header.
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
                
                ScrollView {
                    ForEach(notebooks, id: \.self) { notebook in
                        NotebookCard(notebook: notebook, isSynced: SyncTable.record(for: notebook)?.lastMod == UploadEngine.notebookLastMod(notebook), onTap: {
                            pageIndex = 0
                            noteText = NotebookStore.loadPage(notebook, page: "\(NotebookStore.loadInfo(for: notebook)?.order.first ?? "").rtf")
                            lastSavedText = noteText
                            openNotebook = notebook
                        })
                    }
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
