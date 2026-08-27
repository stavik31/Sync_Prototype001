import Foundation
import SQLite

struct SyncTable {
    
    private static let table = Table("sync")
    private static let name = SQLite.Expression<String>("name")
    private static let packageId = SQLite.Expression<String>("packageId")
    private static let lastMod = SQLite.Expression<Int64>("lastMod")
    private static let conflict = SQLite.Expression<Bool>("conflict")
    
    private static var db: Connection? = {
        
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let path = documents.appendingPathComponent("sync.sqlite3").path
        
        guard let connection = try? Connection(path) else { return nil }
        _ = try? connection.run(table.create(ifNotExists: true) { t in
            
            t.column(name, primaryKey: true)
            t.column(packageId)
            t.column(lastMod)
            t.column(conflict)
        })
        
        return connection
        
        
    }()
    
    static func record(for notebook: String) -> (packageId: String, lastMod: Int64)? {
        guard let db else { return nil }
        guard let row = try? db.pluck(table.filter(name == notebook)) else { return nil }
        
        return (row[packageId], row[lastMod])
    }
    
    static func save(notebook: String, packageId id: String, lastMod mod: Int64) {
        guard let db else { return }
        _ = try? db.run(table.insert(or: .replace,
                                     name <- notebook,
                                     packageId <- id,
                                     lastMod <- mod,
                                     conflict <- false
                                    ))
    }
}
