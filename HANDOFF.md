# Handoff — AWSSyncRemoteStore work, SQLite bug in progress

(CLAUDE.md already governs the working rules in this repo — read that first.
This file is just session-specific status, not a replacement for it.)

## What's done and confirmed working today

- Interface files exist and are correct: `Interface/SyncRemoteStore.swift` (12
  empty methods, matches the real `FTSyncRemoteStore.kt` given via Slack
  exactly), `Interface/SyncModels.swift` (all model types).
- `Interface/AWSSyncRemoteStore.swift` — 5 of 12 methods fully implemented and
  tested live in the Simulator: `isAvailable`, `accountDetails`,
  `listNotebooks`, `maxVersionNotebook`, `uploadNotebook`. The rest are
  intentional stubs (download/delete/tombstones blocked on backend work not
  assigned to this session; folder-plist/mapThrowable deliberately deferred).
- `AWS/SyncAPI.swift` — `put(content:to:)` added, takes `Data` not `String` (so
  it doesn't assume text content — real fix, not cosmetic).
- Both AWS Lambdas fixed and deployed: the upload Lambda no longer hardcodes
  `.rtf`; the download Lambda now takes `{packageId, files: [id,...]}` instead
  of raw paths (matches what the Android side was already sending — verified
  via a fork comparing this repo against github.com/arnav-maryala/notebook-android).
- `Logic/UploadEngine.swift`'s `upload()` was rewritten: it still does its own
  page-level diffing (calls `SyncAPI.getManifest` directly — that's allowed,
  glue code isn't restricted the way `AWSSyncRemoteStore` is), but now stages
  changed pages into a temp folder and calls `AWSSyncRemoteStore.uploadNotebook`
  instead of talking to AWS directly. `uploadAll` and `notebookLastMod` are
  untouched — `uploadAll` didn't need to change since it already calls `upload`.
- Fixed a real bug in `UI/NotebookListView.swift`: opening a notebook from the
  list now resets `pageIndex = 0` (it didn't before, causing stale-page-index
  content mismatches after leaving and reopening a notebook).
- All of the above is committed and pushed to `main` on the `personal` remote
  (`github.com/stavik31/Sync_Prototype001.git` — note this repo was renamed
  from `Noteshelf-Internship`, so the git remote URL may still show a redirect
  notice on push, that's expected and harmless).
- Confirmed via live Simulator testing: notebook creation, page add/edit/nav
  work correctly. Upload actually reaches S3 successfully (confirmed via
  console: no `prepare failed`/`commit failed` prints).

## Known, understood, non-blocking things

- `getManifest failed: 500 — "Unable to access package manifest"` is a
  pre-existing S3 IAM permissions quirk (documented before this session even
  started): S3 returns 403/AccessDenied instead of 404 for a genuinely
  nonexistent object, because the Lambda's execution role isn't scoped to
  distinguish the two. Not a code bug. Needs an AWS console IAM fix
  (broaden `s3:ListBucket`/`s3:GetObject` on the Lambda's execution role) —
  out of scope for this repo, not urgent.
- Manual "start fresh" testing must delete `sync.sqlite3` too, not just
  `MyNotes` + S3 objects — it's a separate local SQLite file
  (`SyncTable.swift`) that a manual folder deletion doesn't touch. A full
  `xcrun simctl erase <device>` clears everything at once; manual deletion
  does not.
- Auth: no interim solution built yet for a *different* client (e.g. the
  Android side, or Fluid Touch's real app) to get a token — `FTServiceAccountHandler`
  is entirely unbuilt (deferred, priority 2 after sync). For testing in *this*
  app specifically, existing login (`LoginPage`/`AuthManager.login`) works fine
  and is not the blocker.

## OPEN BUG — where to pick up

`SyncTable` (`Storage/SyncTable.swift`) never actually creates `sync.sqlite3`
on disk, even after a successful upload that should call `SyncTable.save(...)`.

Ruled out already, don't re-check these:
- Not a code logic bug in `SyncTable.swift`, `UploadEngine.swift`, or
  `NoteEditorView.swift` — all traced correctly by hand.
- Not the wrong app bundle being checked — confirmed via
  `xcrun simctl get_app_container <device> com.satvik.NoteshelfSync bundle`
  (NOT the `Index.noindex` DerivedData path, which is Xcode's separate
  background-indexing build and gave a false negative once already).
- Not a stale build — did a full Clean Build Folder (Shift+Cmd+K), rebuilt,
  reinstalled fresh. Still zero SQLite symbols in the binary afterward.

Confirmed via `nm` and `strings` on the actual installed binary
(`xcrun simctl get_app_container ... bundle`, then check `<path>/NoteshelfSync`):
**zero SQLite symbols and zero "sqlite" strings anywhere in the compiled app,
even though `SQLite.swift 0.16.0` shows correctly as a Package Dependency and
is listed under the NoteshelfSync target's "Frameworks, Libraries, and
Embedded Content."** The "Embed" column for it isn't clickable, which is
normal/expected for a library-type SPM product (no bug there).

So: the project is *configured* to depend on SQLite.swift, but the actual
compiled binary genuinely does not contain it — and this survives a clean
rebuild, which rules out simple build-cache staleness.

Next things to check, not yet tried:
- Whether `Storage/SyncTable.swift` (the only file with `import SQLite`) is
  actually a member of the `NoteshelfSync` target's **Compile Sources** build
  phase (Build Phases tab → Compile Sources list) — if it got excluded from
  the target somehow (e.g. during the AWS/Storage/Logic/UI folder
  reorganization done earlier this week), it wouldn't compile at all, and the
  import would be silently dead weight rather than erroring, if nothing else
  in the target actually forces a real reference to it. Worth confirming
  `SyncTable.swift` is checked in that list for the NoteshelfSync target.
- Whether the package product name is actually `SQLite` vs. something else
  (check `Package.swift`/the resolved package's product name matches exactly
  what's imported as `import SQLite` in `SyncTable.swift`).
- Whether there are actually *two* different `SyncTable.swift`-like files or
  duplicate target memberships confusing which one really builds.

## Working agreement reminder

Per CLAUDE.md: don't write/edit logic in this repo — describe fixes, let
Satvik type them. Mechanical deletions/comment-outs are the only exception.
