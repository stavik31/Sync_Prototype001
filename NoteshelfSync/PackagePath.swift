struct PackagePath {
    static func build(userId: String, notebook: String, page: String) -> String {
        "\(userId)/\(notebook)/\(page).rtf"
    }
    
    static func parse(_ path: String) -> (userId: String, notebook: String, page: String)? {
        
        let parts = path.split(separator: "/")
        guard parts.count == 3 else { return nil }
        
        let filename = String(parts[2])
        guard filename.hasSuffix(".rtf") else { return nil }
        let page = String(filename.dropLast(4))
        
        return (String(parts[0]), String(parts[1]), page)
    }
}
