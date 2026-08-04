import SwiftUI

struct NotebookCard: View {
    let notebook: String
    let isSynced: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            Button(action: onTap) {
                HStack {
                    Image(systemName: "book.closed.fill")
                        .foregroundColor(.indigo)
                    Text(notebook)
                    
                    Spacer()
                    
                    Circle()
                        .fill(isSynced ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x:0, y:2)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }
}
