import SwiftUI

// The root view, and the single place all app state lives.
//
// Every @State in the app is declared here; other views receive @Bindings and
// never keep their own copies. There are no view models or ObservableObjects —
// this is deliberate, and new state should follow the same pattern: add the
// @State here, thread a binding down.
//
// The body picks one of three screens based on two values:
//   not logged in        -> LoginPage
//   logged in, no open   -> NotebookListView
//   logged in, notebook  -> NoteEditorView
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
    @State private var userId: String = ""
    
    var body: some View {
        Group {
            if isLoggedIn == false {
                LoginPage(
                    isLoggedIn: $isLoggedIn,
                    authToken: $authToken,
                    refreshToken: $refreshToken,
                    userId: $userId
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
                        pageIndex: $pageIndex,
                        userId: $userId
                    )
                }
            }
        }
        // Runs once when the app opens: load the notebook list from disk, and
        // log the user straight back in if a token was saved last time.
        //
        // Note this only checks that a token EXISTS — it never asks whether
        // it's still valid. A stale token gets you past the login screen and
        // only fails later, when something actually calls the server.
        .onAppear {
            notebooks = NotebookStore.listNotebooks()
            
            if let savedToken = KeychainManager.load(key: "authToken") {
                authToken = savedToken
                refreshToken = KeychainManager.load(key: "refreshToken") ?? ""
                isLoggedIn = true
                userId = AuthManager.userId(from: savedToken) ?? ""
            }
        }
    }
}

#Preview {
    ContentView()
}
