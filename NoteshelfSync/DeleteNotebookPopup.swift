import SwiftUI

struct DeleteNotebooksPopup: View {
    @Binding var isPresented: Bool
    @Binding var notebooks: [String]
    @Binding var selected: Set<String>

    var body: some View {
        VStack(spacing: 16) {
            Text("Delete Notebooks")
                .font(.headline)
            
            ForEach(notebooks, id: \.self) { notebook in
                HStack {
                    Text(notebook)
                    Spacer()
                    Image(systemName: selected.contains(notebook) ? "checkmark.square.fill" : "square")
                        .foregroundColor(.indigo)
                }
                .onTapGesture {
                    if selected.contains(notebook) {
                        selected.remove(notebook)
                    } else {
                        selected.insert(notebook)
                    }
                }
            }
            
            HStack {
                Button(action: {
                    selected.removeAll()
                    isPresented = false
                }) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                }
                
                Button(action: {
                    notebooks.removeAll { selected.contains($0) }
                    selected.removeAll()
                    isPresented = false
                }) {
                    Text("Delete Selected")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
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
