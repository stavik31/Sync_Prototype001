# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Working agreement

Satvik writes every line of actual functionality personally. Claude's role there is to read, investigate, explain, and suggest — findings go in the reply as prose with snippets inline for him to type himself. Exceptions for when Satvik asks edits from claude explicitly

**Exception, added 2026-08-24:** Claude may make mechanical edits that touch no logic — deleting code (including a whole file), commenting code out, and replacing already-commented-out code with a short marker comment. These are reversible via git and carry none of the risk the rule above exists to avoid. If there's any judgment call about *what* the replacement comment should say or *which* lines constitute the logical unit to remove, ask or describe it first rather than guessing.

Still off-limits regardless: writing any new logic, and any command that mutates history or discards work — `git checkout`, `git stash`, `git reset`, formatters that reformat logic. Reading (`Read`, `Grep`, `git diff`) and read-only `xcodebuild` builds are fine, as is `sed`/`Edit` for the mechanical edits above.

The one exception is this file. Satvik will say "update CLAUDE.md" at the end of a session; that is the cue to fold in what was learned. Nothing else in the repo gets written.

The app currently works. Unrequested improvement is not wanted.

## Project

iOS (SwiftUI) client for Noteshelf Sync, a cloud-connected notebook app. This repo is **only** the iOS client — the AWS backend (Cognito, S3, API Gateway) lives in the AWS console and is not versioned here. A separate Android codebase exists against related backend infrastructure; the `Interface/` layer (see Architecture) is deliberately shaped to mirror the Android side's Kotlin `FTSyncRemoteStore.kt`, method-for-method, so any change to those method signatures — not just the raw endpoints — is a cross-team contract change, even though `AWSSyncRemoteStore` itself is the only implementation of that interface right now.

Background beyond what the code shows (backend build history, roadmap, mental models) is in `~/Desktop/Noteshelf_Sync_Full_Handoff.md.pdf`. No system PDF extractor is installed; the Anaconda `python3` has `pdfplumber`.

## Commands

```bash
# Build for simulator (verified working)
xcodebuild -project NoteshelfSync.xcodeproj -scheme NoteshelfSync \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run: open in Xcode and Cmd+R, or
xcrun simctl boot "iPhone 17 Pro" && open -a Simulator
xcrun simctl install booted <path-to>/NoteshelfSync.app
xcrun simctl launch booted com.satvik.NoteshelfSync
```

Scheme/target for the app itself is `NoteshelfSync`. A `NoteshelfSyncTests` target also exists in the project (Xcode's default auto-generated scaffold, added 2026-08-24), but it holds no real tests — just the one-line `@Test func example()` stub Xcode creates automatically. `xcodebuild test` will now run without erroring, but it isn't exercising anything meaningful. Verification is still effectively manual, in the Simulator.

Deployment target is iOS 26.5, so the simulator must be an iOS 26.x device.

**Test in the real Simulator, not the Xcode Canvas preview.** They are separate environments with different Documents directories and unreliable networking in Canvas; mixing them previously produced phantom/duplicate notebooks that took a while to diagnose. Canvas previews also run through a simulator-backed process under the hood — killing/shutting down simulators from the CLI can take the preview canvas down with them (seen 2026-09-03; recovers via the canvas's own "Resume" button, or reopening Xcode).

The Xcode project uses the newer `PBXFileSystemSynchronizedRootGroup` format (`objectVersion 77`): file/target membership is inferred from folder structure, not enumerated by filename in `project.pbxproj`. Don't read "this file isn't mentioned in project.pbxproj" as evidence it's excluded from the target — it isn't, unless there's an explicit membership exception (there currently are none). Debug builds also compile the app's actual Swift code into a separate `NoteshelfSync.debug.dylib` sitting next to a thin launcher executable — if you ever inspect the built binary directly (`nm`, `strings`), check the `.debug.dylib`, not the main executable; the main executable is expected to look almost empty.

## Architecture

### State lives in exactly one place

`ContentView` owns every `@State` variable in the app (notebooks, open notebook, note text, login flag, both tokens, user id, popup flags). Every other view receives `@Binding`s. There are no `ObservableObject`s, view models, or environment objects, and no view holds long-lived state of its own. `ContentView.body` is a `Group` that switches on `isLoggedIn` and `openNotebook` to pick between `LoginPage`, `NotebookListView`, and `NoteEditorView`.

When adding a screen or a piece of state, follow this: add the `@State` to `ContentView`, thread a `@Binding` down. Introducing a view model here would fight the existing design.

Don't compute a value once and cache it in `@State` if it can instead be recomputed live from an existing source of truth on every redraw — that was the shape of a real bug (see `NotebookCard`'s sync dot, fixed 2026-09-04): a `syncedNotebooks` cache went stale the moment a notebook changed after its last upload, because nothing repopulated it except the upload button itself. The fix removed the cache entirely in favor of a live comparison computed fresh each time the list draws.

### Notebooks are multi-page now, stored via `NotebookStore`

`Storage/NotebookStore.swift` (not `NotesFileManager` — that name is gone) owns everything about notebooks on disk. Layout for a notebook named "Physics":

```
Documents/
  MyNotes/
    Physics/
      notebook.json       <- the notebook's uuid + its page order
      Pages/
        <page-uuid>.rtf    <- one file per page
```

Page files are named by uuid, not position — `notebook.json`'s `order` array is the only place page order lives, so inserting a page in the middle never renames files. There's no stored `last_mod`; it's read live from the filesystem's own modification date and converted to unix-milliseconds. `listNotebooks()` still scans the filesystem (a folder counts as a notebook only if it contains a `notebook.json`), so it can't drift from reality the way a tracked list could.

`KeychainManager` is unchanged from before: Cognito tokens only, wrapping `SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete` keyed on `kSecAttrAccount`, two accounts (`"authToken"`, `"refreshToken"`). Every `OSStatus` is still ignored, so a failed write is silent.

### Networking: AuthManager + SyncAPI + UploadEngine + AWSSyncRemoteStore

No AWS SDK. Every call is a hand-built `URLRequest` + `URLSession.shared.data(for:)`. The old `SyncManager` (a single flat networking file) is gone, replaced by a layered structure built to mirror the Android side's sync interface:

- **`AWS/AuthManager.swift`** — talks directly to Cognito (`https://cognito-idp.{region}.amazonaws.com/`), raw JSON protocol (`Content-Type: application/x-amz-json-1.1`, `X-Amz-Target: AWSCognitoIdentityProviderService.InitiateAuth`). `login` uses `USER_PASSWORD_AUTH`, returns `(idToken, refreshToken)`. `refresh` uses `REFRESH_TOKEN_AUTH`, returns a new ID token only, and discards Cognito's own error body — a genuine refresh rejection and a malformed response look identical here. `userId(from:)` decodes the `sub` claim out of a token locally, no network call, signature unverified (fine — it's a token Cognito just issued us).
- **`AWS/SyncAPI.swift`** — the actual backend calls: `listPackages`, `getManifest`, `prepare`, `commit`, plus `put` (raw bytes to a presigned S3 URL — deliberately carries no auth header, permission is baked into the URL). All four authenticated calls route through a shared private `send(_:)` helper (added 2026-09-04) rather than calling `URLSession` directly.
- **`Logic/UploadEngine.swift`** — decides *what* needs uploading (diffs local `lastMod` against `SyncTable`'s last-successful-upload record, calls `SyncAPI.getManifest` directly for page-level diffing — that's allowed, glue code isn't restricted the way `AWSSyncRemoteStore` is), stages changed pages into a temp folder, and calls `AWSSyncRemoteStore.uploadNotebook`.
- **`Interface/AWSSyncRemoteStore.swift`** — implements the `SyncRemoteStore` protocol (`Interface/SyncRemoteStore.swift`), which mirrors the Android Kotlin interface (see Project section). 5 of 12 methods are real (`isAvailable`, `accountDetails`, `listNotebooks`, `maxVersionNotebook`, `uploadNotebook`); the rest are intentional stubs — `downloadNotebook`, `readTombstones`, `deleteNotebookRemote`, `readFolderPlist`/`writeFolderPlist`, `downloadDeletionListFile`, `mapThrowable` all need backend work (new Lambdas) that hasn't been assigned yet, and are marked `// TODO — second intern` in the code itself.
- **`Storage/SyncTable.swift`** — a local SQLite file (`Documents/sync.sqlite3`, via `SQLite.swift` 0.16.0) holding one row per notebook: what it looked like at its last *successful* upload. This is the comparison point both "has this changed locally" and future conflict detection are built on. Write to it only after a commit has succeeded — writing early makes the next upload believe it already sent something it didn't, and that failure is silent.

### Token expiry: discovered and handled in one place, not predicted

There is still no timer, no `scenePhase` observer, no JWT `exp` parsing anywhere in the app — expiry is only ever discovered by making a request and getting a 401 back. What changed (2026-09-04) is *where* the reaction to that lives.

The old pattern (401 → refresh → retry, duplicated verbatim at three UI call sites) is gone. It now lives in exactly one place: `SyncAPI`'s private `send(_:)` helper, which every authenticated call routes through. On a 401, it loads `refreshToken` from the Keychain, calls `AuthManager.refresh`, and on success saves the new token to the Keychain and silently retries the original request once — callers (`UploadEngine`, `AWSSyncRemoteStore`) never know a refresh happened. On refresh failure, it clears both Keychain entries right there and returns `nil`.

Nothing below the UI layer holds a binding to `isLoggedIn`, so the UI still has to notice a session died in the *current* session (not just on next relaunch). The pattern for that: after a network-triggered action completes, check `KeychainManager.load(key: "authToken") == nil` — if the token's gone, it can only mean `send()` cleared it, so clear the in-memory token/user state and set `isLoggedIn = false`. This check currently lives in `NotebookListView`'s upload button (the only UI call site that triggers `SyncAPI` calls today). **Any new UI entry point that triggers a `SyncAPI`-backed call needs this same post-call check added — it does not happen automatically.** Known accepted quirk: if the refresh token dies mid-`uploadAll` (which loops per notebook), every remaining notebook in that loop still gets its own failed attempt (and its own console prints) before the loop ends and this check finally runs — noisy, not incorrect.

`NotebookListView` also now has a working **Logout** button (top-right of the indigo header bar) — clears both Keychain entries, clears in-memory `authToken`/`refreshToken`/`userId`, sets `isLoggedIn = false`. Same teardown as the session-died path above, just user-triggered instead of discovered.

### Save is local-only, by design

`NoteEditorView`'s Save buttons (top bar, and inside the unsaved-changes popup) only ever call `NotebookStore.savePage(...)` — they do not, and are not meant to, trigger any network call. Uploading only happens through the explicit upload button in `NotebookListView`. This is deliberate, not a gap — don't "restore" an upload call there.

The sync/refresh button in `NotebookListView`'s header (the circular-arrow icon) is intentionally still dead — its body is empty, marked with a comment pointing at this. It's waiting specifically on download being implemented (see `AWSSyncRemoteStore.downloadNotebook`'s stub above); only once both directions exist does it get wired up.

## Backend contract

Region `eu-north-1`. Base URL `https://j21sih3zdd.execute-api.eu-north-1.amazonaws.com`. Cognito client id `388s6r4q4n7e40gv66m0qea6v8` (no client secret) — pool id not yet confirmed in this file, check the AWS console if needed.

| Endpoint | Notes |
| --- | --- |
| `GET /getallpackagemetadata` | `listPackages` — every notebook the server holds for this user |
| `GET /getpackagemanifest/{packageId}` | `getManifest` — one notebook's page list. A notebook the server doesn't have returns 500, not 404 (S3 permissions quirk on the backend — Lambda's execution role can't distinguish the two) |
| `POST /upload` | Serves both `prepare` (action: "prepare" — returns one presigned S3 PUT link per page, 15-minute expiry) and `commit` (action: "commit" — publishes; the manifest sent is the *complete* truth, anything not listed gets deleted from that notebook's S3 folder) |
| presigned S3 URL from `prepare` | `SyncAPI.put` PUTs raw page bytes here directly, no auth header |

`LoginPage.swift` currently hardcodes `madhavchoudhary296@gmail.com` / `Syncprototype@001` for dev speed. There is no sign-up flow.

## Known gaps

These are understood and deferred, not oversights — don't "fix" them incidentally:

- Create-notebook has no validation — empty and duplicate names are accepted (`CreateNotebookPopup.swift`).
- Deleting a notebook (`DeleteNotebooksPopup.swift`) only removes it from the local in-memory array. The folder stays on disk, so it reappears on next launch when the list is rebuilt by scanning the filesystem — and the server never learns about the deletion either (`AWSSyncRemoteStore.deleteNotebookRemote` is a stub). Needs an actual `NotebookStore` removal function plus a real delete Lambda + `SyncAPI.delete(...)`.
- Conflict handling is minimal: `UploadEngine.uploadAll` checks the server's `last_mod` against `SyncTable`'s recorded one and just skips (prints `"conflict: <notebook>, skipped"`) on a mismatch — no resolution flow, no UI surfacing. `POST /notebooks/{id}/resolve`-style conflict resolution doesn't exist in the current `SyncAPI` at all.
- Download, remote delete, tombstones (deletion tracking), folder/category plist sync, and typed error mapping are all unbuilt — stubbed in `AWSSyncRemoteStore` with `// TODO — second intern` comments. Each needs a new Lambda plus a matching `SyncAPI` function before it can be real.
- The sync button in `NotebookListView` stays dead until download exists (see Architecture above) — deliberate sequencing, not forgotten.
- No offline detection.
- **Open, unresolved as of 2026-09-04 — `sync.sqlite3` never appears on disk.** `SyncTable.save(...)` should create/write `Documents/sync.sqlite3` after a successful upload, but it's been observed not to. Ruled out already: it's not a target-membership or build issue (confirmed via `nm`/`strings` on the correct build artifact — see the Commands section's note on `NoteshelfSync.debug.dylib` vs the main executable; earlier "zero SQLite symbols" findings were from checking the wrong file and are not evidence of a real problem), not a stale build, and `SyncTable`'s call sites (`UploadEngine.swift`, `NotebookListView.swift`) are real and reachable — if `SyncTable.swift` weren't compiling, the whole target would fail to build, and it builds fine. Still unconfirmed: whether `Connection(path)` inside `SyncTable`'s lazy `db` initializer is actually succeeding at runtime — that init swallows failure via `try?`, so a failed open is currently silent. Next step is confirming at runtime (breakpoint or otherwise) whether that `guard let connection = try? Connection(path)` line is succeeding. Satvik is checking this independently.
- CLAUDE.md's own history: a bug was once documented here where `LoginPage.swift` saved the ID token under Keychain account `"AuthToken"` (capital A) while everything else used `"authToken"`, breaking auto-login on relaunch. As of 2026-09-04, that bug is **not present** in the current `LoginPage.swift` — it correctly uses `"authToken"` everywhere. Either it was fixed as part of a later rewrite, or it was never actually in the version of the file this description was written against. No code fix needed; noting it here so it isn't rediscovered as if new.
