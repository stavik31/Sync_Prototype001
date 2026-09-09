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
                        refreshToken: $refreshToken,
                        isLoggedIn: $isLoggedIn,
                        pageIndex: $pageIndex
                    )
                } else {
                    NotebookListView(
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
        // Runs once when the app opens (not on every foreground — see the
        // simulator gotcha in the project README/CLAUDE.md if a change on disk
        // ever seems to not show up: it won't, until a true relaunch).
        //
        // Three things happen here:
        //  1. Load the notebook list from disk.
        //  2. Point SyncAPI's three storage hooks at Keychain. This is the one
        //     piece of setup SyncAPI can't do itself — see SyncAPI.swift's
        //     header for why it's shaped as closures instead of a direct call.
        //     Nothing that hits the network works correctly until this runs.
        //  3. Log the user straight back in if a token was saved last time.
        //     This only checks that a token EXISTS — it never asks whether
        //     it's still valid. A stale token gets you past the login screen
        //     and only fails later, when something actually calls the server.
        .onAppear {
            notebooks = NotebookStore.listNotebooks()

            SyncAPI.loadRefreshToken = { KeychainManager.load(key: "refreshToken") }
            SyncAPI.onTokenRefreshed = { newToken in
                KeychainManager.save(token: newToken, key: "authToken")
            }
            SyncAPI.onRefreshFailed = {
                _ = KeychainManager.delete(key: "authToken")
                _ = KeychainManager.delete(key: "refreshToken")
            }

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
