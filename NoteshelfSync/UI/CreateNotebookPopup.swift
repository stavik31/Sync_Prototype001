import SwiftUI

// Popup for naming and creating a notebook.
//
// Create does two things: NotebookStore builds the real folder, notebook.json
// and first page on disk, then the name is appended to the in-memory list so
// it shows up immediately.
//
// No validation — empty names and duplicates are both accepted, and a duplicate
// name would collide with the existing folder.
struct CreateNotebookPopup: View {
    @Binding var isPresented: Bool
    @Binding var notebooks: [String]
    @State private var name: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Create New Notebook")
                .font(.headline)
            
            TextField("Notebook Name", text: $name)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            HStack {
                Button(action: {
                    isPresented = false
                }) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                }
                
                Button(action: {
                    NotebookStore.createNotebook(named: name)
                    notebooks.append(name)
                    isPresented = false
                    name = ""
                }) {
                    Text("Create")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.indigo)
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
