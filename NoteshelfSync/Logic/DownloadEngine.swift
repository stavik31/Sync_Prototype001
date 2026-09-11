import Foundation

struct DownloadEngine {

    static func syncNotebook(package: PackageMetadata, authToken: String) async -> Bool {
        let notebookName = URL(fileURLWithPath: package.path).lastPathComponent
        let destination = NotebookStore.notebookURL(notebookName)
        
        let node = RemoteNode(remoteId: package.id, name: nil, documentId: package.id, driveId: nil, version: nil, documentVersion: nil, syncVersion: nil, relativePath: package.path, createdDevice: nil, lastUpdDevice: nil, createdAt: nil, modifiedAt: package.last_mod, revisionToken: nil, isFolder: false)

        print("")
        print("📦 Starting package synchronization")
        print("Package ID:", package.id)
        print("Package path:", package.path)

        let packageExists = FileManager.default.fileExists(atPath: destination.path)

        print("")
        print("📁 LOCAL PACKAGE DIRECTORY")
        print(destination.path)
        print("")

        let syncRecord = SyncTable.record(for: notebookName)

        guard packageExists, let syncRecord else {
            print("🆕 Package has not been synchronized before")
            print("⬇️ Downloading all files")
            let outcome = await AWSSyncRemoteStore(authToken: authToken).downloadNotebook(node: node, destination: destination, conflictFlow: false)
            return outcome.status == .downloaded
        }

        guard NotebookStore.loadInfo(for: notebookName) != nil else {
            print("⚠️ Could not determine local modification time")
            print("⬇️ Downloading package")
            let outcome = await AWSSyncRemoteStore(authToken: authToken).downloadNotebook(node: node, destination: destination, conflictFlow: false)
            return outcome.status == .downloaded
        }

        let localLastMod = UploadEngine.notebookLastMod(notebookName)
        let syncLastMod = syncRecord.lastMod
        let serverLastMod = package.last_mod

        let localSeconds = localLastMod / 1000
        let syncSeconds = syncLastMod / 1000

        print("")
        print("========== SYNC COMPARISON ==========")
        print("Package:", package.id)
        print("Local lastMod:", localLastMod)
        print("SyncTable lastMod:", syncLastMod)
        print("Server lastMod:", serverLastMod)
        print("-------------------------------------")
        print("Local seconds:", localSeconds)
        print("Sync seconds:", syncSeconds)
        print("=====================================")
        print("")

        if localSeconds == syncSeconds && syncLastMod < serverLastMod {
            print("⬇️ CASE 1")
            print("Local == SyncTable < Server")
            print("Server has newer data")
            print("⬇️ Download required")
            let outcome = await AWSSyncRemoteStore(authToken: authToken).downloadNotebook(node: node, destination: destination, conflictFlow: false)
            return outcome.status == .downloaded
        }

        if localSeconds == syncSeconds && syncLastMod == serverLastMod {
            print("✅ CASE 2")
            print("Local == SyncTable == Server")
            print("No changes required")
            return true
        }

        if localSeconds > syncSeconds && syncLastMod == serverLastMod {
            print("⬆️ CASE 3")
            print("Local > SyncTable == Server")
            print("UPLOAD NEEDS TO BE DONE")
            print("Package:", package.id)
            return true
        }

        if localSeconds > syncSeconds && syncLastMod < serverLastMod {
            print("⚠️ CASE 4")
            print("Local > SyncTable < Server")
            print("CONFLICT DETECTED")
            print("Package:", package.id)
            SyncTable.markConflict(notebook: notebookName, conflict: true)
            return false
        }

        if localSeconds == syncSeconds && syncLastMod > serverLastMod {
            print("ℹ️ CASE 5")
            print("Local == SyncTable > Server")
            print("Ignoring this case")
            return true
        }

        print("⚠️ Unhandled synchronization state")
        print("Local:", localLastMod)
        print("SyncTable:", syncLastMod)
        print("Server:", serverLastMod)
        return false
    }
}
