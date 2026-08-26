import SwiftUI

struct ContentView: View {
    
    @State private var syncedNotebooks: Set<String> = []
    @State private var createPopup: Bool = false
    @State private var deletePopup: Bool = false
    @State private var selectedForDeletion: Set<String> = []
    @State private var newNotebookName: String = ""
    @State private var notebooks: [String] = []
    @State private var openNotebook: String? = nil
    @State private var noteText: String = ""
    @State private var lastSavedText: String = ""
    @State private var unsavedPopup: Bool = false
    @State private var isLoggedIn: Bool = false
    @State private var authToken: String = ""
    @State private var refreshToken: String = ""
    @State private var pageIndex: Int = 0
    
    var body: some View {
        Group {
            if isLoggedIn == false {
                LoginPage(
                    isLoggedIn: $isLoggedIn,
                    authToken: $authToken,
                    refreshToken: $refreshToken
                )
            } else {
                if let notebook = openNotebook {
                    NoteEditorView(
                        notebook: notebook,
                        noteText: $noteText,
                        lastSavedText: $lastSavedText,
                        openNotebook: $openNotebook,
                        unsavedPopup: $unsavedPopup,
                        authToken: $authToken,
                        syncedNotebooks: $syncedNotebooks,
                        refreshToken: $refreshToken,
                        isLoggedIn: $isLoggedIn,
                        pageIndex: $pageIndex
                    )
                } else {
                    NotebookListView(
                        syncedNotebooks: $syncedNotebooks,
                        notebooks: $notebooks,
                        openNotebook: $openNotebook,
                        createPopup: $createPopup,
                        deletePopup: $deletePopup,
                        newNotebookName: $newNotebookName,
                        selectedForDeletion: $selectedForDeletion,
                        noteText: $noteText,
                        lastSavedText: $lastSavedText,
                        authToken: $authToken,
                        refreshToken: $refreshToken,
                        isLoggedIn: $isLoggedIn,
                        pageIndex: $pageIndex
                    )
                }
            }
        }
        .onAppear {
            notebooks = NotebookStore.listNotebooks()
            
            if let savedToken = KeychainManager.load(key: "authToken") {
                authToken = savedToken
                refreshToken = KeychainManager.load(key: "refreshToken") ?? ""
                isLoggedIn = true
            }
        }
    }
}

#Preview {
    ContentView()
}
