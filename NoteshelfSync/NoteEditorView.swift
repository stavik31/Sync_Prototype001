import SwiftUI

struct NoteEditorView: View {
    let notebook: String
    @Binding var noteText: String
    @Binding var lastSavedText: String
    @Binding var openNotebook: String?
    @Binding var unsavedPopup: Bool
    @Binding var authToken: String
    @Binding var syncedNotebooks: Set<String>

    var body: some View {
        ZStack {
            VStack(spacing: 0){
                HStack {
                    Button(action: {
                        if noteText == lastSavedText {
                            openNotebook = nil
                        } else {
                            unsavedPopup = true
                        }
                    }){
                        Image(systemName: "chevron.left")
                            .foregroundColor(.black)
                            .font(.system(size: 20))
                            .padding(15)
                            .padding(.top, 20)
                            .bold()
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        NotesFileManager.saveNote(for: notebook, content: noteText)
                        lastSavedText = noteText
                        
                        Task {
                            let success = await SyncManager.upload(
                                notebookId: notebook,
                                fileContent: noteText,
                                pageName: "\(notebook).txt",
                                authToken: authToken
                            )
                            if success {
                                syncedNotebooks.insert(notebook)
                            }
                            print("Upload Success: \(success)")
                        }
                    }) {
                        Text("Save")
                            .foregroundColor(.black)
                            .padding(15)
                            .bold()
                            .padding(.top, 20)
                    }
                }
                .padding()
                .frame(height: 80)
                .background(Color.indigo)
                
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 5)
                
                HStack {
                    Text(notebook)
                        .font(.title)
                        .bold()
                        .padding(.top, 10)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 0)
                .padding(.bottom, 8)
                
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $noteText)
                        .padding(.horizontal)
                        .scrollContentBackground(.hidden)
                    
                    if noteText.isEmpty {
                        Text("Start Typing...")
                            .foregroundColor(.gray)
                            .padding(.horizontal, 21)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
            }
            .ignoresSafeArea(edges: .top)
            
            if unsavedPopup {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    Button(action:  {
                        noteText = NotesFileManager.loadNote(for: notebook)
                        unsavedPopup = false
                        openNotebook = nil
                    }) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(10)
                    }
                    
                    Button(action: {
                        NotesFileManager.saveNote(for: notebook, content: noteText)
                        lastSavedText = noteText
                        unsavedPopup = false
                        openNotebook = nil
                    }) {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.indigo)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(16)
                .padding(.horizontal, 40)
            }
        }
    }
}
