import SwiftUI

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
