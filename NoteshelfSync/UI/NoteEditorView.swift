import SwiftUI

// Edits one page of one notebook.
//
// Which page is showing comes from pageIndex, a position (0, 1, 2...) into the
// notebook's order array. The uuid and filename are looked up from that.
//
// Controls:
//   top left      back, warns if there are unsaved changes
//   top right     Save, and a trash that deletes the current page
//   bottom left   < > to move between pages
//   bottom right  + to insert a page after this one
//
// Anything that changes which page is showing must save the current one first,
// or whatever was typed is lost.
struct NoteEditorView: View {
    let notebook: String
    @Binding var noteText: String
    @Binding var lastSavedText: String
    @Binding var openNotebook: String?
    @Binding var unsavedPopup: Bool
    @Binding var authToken: String

    @Binding var refreshToken: String
    @Binding var isLoggedIn: Bool
    @Binding var pageIndex: Int
    
    // This notebook's page uuids, in order.
    // Computed rather than stored, so it re-reads notebook.json every time and
    // can never be stale after a page is added or deleted.
    private var pages: [String] {
        NotebookStore.loadInfo(for: notebook)?.order ?? []
    }
    
    // The filename of the page currently showing.
    // order holds bare uuids; the file functions need the ".rtf" on the end.
    // Returns "" if pageIndex somehow points outside the array.
    private var currentPageFile: String {
        guard pageIndex >= 0 && pageIndex < pages.count else { return "" }
        return "\(pages[pageIndex]).rtf"
    }
    
    // Moves to another page: saves the current one, then loads the new one.
    // The save has to happen before pageIndex changes, while currentPageFile
    // still points at the page being left.
    // Out-of-range requests are ignored, which is what makes the arrows safe
    // at the first and last page.
    private func goToPage (_ newIndex: Int) {
        guard newIndex >= 0 && newIndex < pages.count else { return }
        NotebookStore.savePage(notebook, page: currentPageFile, content: noteText)
        pageIndex = newIndex
        noteText = NotebookStore.loadPage(notebook, page: currentPageFile)
        lastSavedText = noteText
    }

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
                        NotebookStore.savePage(notebook, page: currentPageFile, content: noteText)
                        lastSavedText = noteText
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
                    
                    Text("Page \(pageIndex + 1) of \(pages.count)")
                        .foregroundColor(.gray)
                        .padding(.top, 10)
                    
                    Button(action: {
                        pageIndex = NotebookStore.deletePage(from: notebook, at: pageIndex)
                        noteText = NotebookStore.loadPage(notebook, page: currentPageFile)
                        lastSavedText = noteText
                    }) {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.red)
                    }
                        
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
            
            VStack {
                Spacer()
                HStack{
                    Spacer()
                    
                    HStack {
                        Button(action : {goToPage(pageIndex - 1)}) {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.white)
                                .frame(width:44, height: 44)
                                .background(pageIndex > 0 ? Color.indigo : Color.gray)
                                .clipShape(Circle())
                        }
                        .disabled(pageIndex == 0)
                        
                        Button(action: {goToPage(pageIndex + 1)}) {
                            Image(systemName: "chevron.right")
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(pageIndex < pages.count - 1 ? Color.indigo : Color.gray)
                                .clipShape(Circle())
                        }
                        .disabled(pageIndex >= pages.count - 1)
                        
                        Spacer()
                    }
                    
                    Button(action: {
                        NotebookStore.savePage(notebook, page: currentPageFile, content: noteText)
                        pageIndex = NotebookStore.addPage(to: notebook, after: pageIndex)
                        noteText = ""
                        lastSavedText = ""
                    }) {
                        Image(systemName: "plus")
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.indigo)
                            .clipShape(Circle())
                    }
                    .padding()
                }
            }
            
            if unsavedPopup {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    Button(action:  {
                        noteText = NotebookStore.loadPage(notebook, page: currentPageFile)
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
                        NotebookStore.savePage(notebook, page: currentPageFile, content: noteText)
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
