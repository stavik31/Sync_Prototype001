import Foundation
import SQLite

// Remembers what each notebook looked like at its last SUCCESSFUL upload.
//
// This is what makes "has anything changed?" answerable. Compare a notebook's
// current last_mod against the value stored here:
//   same      -> nothing changed since the last upload, skip it
//   different -> it's been edited, upload it
//
// It's also what lets conflicts be detected at all. Comparing local against the
// server directly tells you they differ, but not WHO changed — this table is
// the shared reference point both get compared against.
//
// THE RULE: only ever write here after a commit has succeeded. Writing early
// makes the next upload believe it already sent something it didn't, and that
// failure is silent — you'd only notice when two devices disagree.
//
// Stored as a single SQLite file (Documents/sync.sqlite3), one row per notebook.
struct SyncTable {

    // The table and its columns, declared as Swift values rather than raw SQL
    // strings so the compiler catches typos. Nothing outside this file needs them.
    
    private static let table = Table("sync")
    private static let name = SQLite.Expression<String>("name")
    private static let packageId = SQLite.Expression<String>("packageId")
    private static let lastMod = SQLite.Expression<Int64>("lastMod")
    private static let conflict = SQLite.Expression<Bool>("conflict")
    
    // Opens the database and creates the table if it isn't there yet.
    // The trailing () means this block runs once, the first time anything
    // touches `db`, and the result is kept for the rest of the app's life.
    // Optional because opening can fail; every function below handles nil.
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
    
    // What this notebook looked like at its last successful upload.
    // nil means it has never been uploaded — that's how the engine spots a
    // brand-new notebook.
    static func record(for notebook: String) -> (packageId: String, lastMod: Int64)? {
        guard let db else { return nil }
        guard let row = try? db.pluck(table.filter(name == notebook)) else { return nil }
        
        return (row[packageId], row[lastMod])
    }
    
    // Records a successful upload. Call this ONLY after commit returned OK.
    //
    // insert(or: .replace) handles both first upload and every later one —
    // the notebook name is the primary key, so an existing row is overwritten
    // rather than duplicated.
    static func save(notebook: String, packageId id: String, lastMod mod: Int64) {
        guard let db else { return }
        _ = try? db.run(table.insert(or: .replace,
                                     name <- notebook,
                                     packageId <- id,
                                     lastMod <- mod,
                                     conflict <- false
                                    ))
    }
    
    static func markConflict(notebook: String, conflict flag: Bool) {
        guard let db else { return }
        _ = try? db.run(table.filter(name == notebook).update(conflict <- flag))
    }
    
    static func remove(notebook: String) {
        guard let db else { return }
        _ = try? db.run(table.filter(name == notebook).delete())
    }
}
