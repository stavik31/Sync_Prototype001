# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Working agreement

**Do not write or apply new logic in this repository. Ever.** Satvik writes every line of actual functionality personally. Claude's role there is to read, investigate, explain, and suggest — findings go in the reply as prose with snippets inline for him to type himself.

This holds even when a message sounds like a direct instruction to fix something ("fix the typo", "make it handle X"). That is a request for a recommendation, not for an edit. It has already been misread once. If a change seems obviously correct, describe it and stop.

**Exception, added 2026-08-24:** Claude may make mechanical edits that touch no logic — deleting code (including a whole file), commenting code out, and replacing already-commented-out code with a short marker comment. These are reversible via git and carry none of the risk the rule above exists to avoid. If there's any judgment call about *what* the replacement comment should say or *which* lines constitute the logical unit to remove, ask or describe it first rather than guessing.

Still off-limits regardless: writing any new logic, and any command that mutates history or discards work — `git checkout`, `git stash`, `git reset`, formatters that reformat logic. Reading (`Read`, `Grep`, `git diff`) and read-only `xcodebuild` builds are fine, as is `sed`/`Edit` for the mechanical edits above.

The one exception is this file. Satvik will say "update CLAUDE.md" at the end of a session; that is the cue to fold in what was learned. Nothing else in the repo gets written.

The app currently works. Unrequested improvement is not wanted.

## Project

iOS (SwiftUI) client for Noteshelf Sync, a cloud-connected notebook app. This repo is **only** the iOS client — the AWS backend (Cognito, S3, DynamoDB, Lambda, API Gateway) lives in the AWS console and is not versioned here. Two teammates maintain a separate Android codebase against the same backend, so any change to the request/response shape of the three endpoints below is a cross-team contract change.

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

Single target and single scheme, both named `NoteshelfSync`. **There is no test target** — `xcodebuild test` will fail. Verification is manual, in the Simulator.

Deployment target is iOS 26.5, so the simulator must be an iOS 26.x device.

**Test in the real Simulator, not the Xcode Canvas preview.** They are separate environments with different Documents directories and unreliable networking in Canvas; mixing them previously produced phantom/duplicate notebooks that took a while to diagnose.

## Architecture

### State lives in exactly one place

`ContentView` owns every `@State` variable in the app (notebooks, open notebook, note text, login flag, both tokens, popup flags). Every other view receives `@Binding`s. There are no `ObservableObject`s, view models, or environment objects, and no view holds long-lived state of its own. `ContentView.body` is a `Group` that switches on `isLoggedIn` and `openNotebook` to pick between `LoginPage`, `NotebookListView`, and `NoteEditorView`.

When adding a screen or a piece of state, follow this: add the `@State` to `ContentView`, thread a `@Binding` down. Introducing a view model here would fight the existing design.

### Two persistence stores, deliberately split

- `NotesFileManager` — notebook content as flat `.txt` files in the Documents directory. `listNotebooks()` scans the filesystem rather than reading a tracked list, so the filesystem is always the source of truth and cannot drift. Notebook name == filename == `notebookId` used in API calls.
- `KeychainManager` — Cognito tokens only, wrapping `SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete` keyed on `kSecAttrAccount`. Two accounts: `"authToken"` (ID token) and `"refreshToken"`.

Tokens go in the Keychain because they are sensitive; notebook content does not because it isn't.

### Networking: two managers, no SDK

There is no AWS SDK dependency. Every call is a hand-built `URLRequest` + `URLSession.shared.data(for:)`.

- `AuthManager` talks directly to `https://cognito-idp.{region}.amazonaws.com/` using the raw JSON protocol — `Content-Type: application/x-amz-json-1.1` plus an `X-Amz-Target: AWSCognitoIdentityProviderService.InitiateAuth` header. `login` uses the `USER_PASSWORD_AUTH` flow and returns `(idToken, refreshToken)`; `refresh` uses `REFRESH_TOKEN_AUTH` and returns a new ID token only.
- `SyncManager` talks to API Gateway with `Authorization: Bearer <idToken>`, computing MD5 checksums via `CryptoKit`'s `Insecure.MD5`.

`SyncManager` deliberately classifies responses into `UploadResult { success, unauthorized, failure }` — 200, 401, everything-else-including-thrown-errors. That three-way split is not incidental: it is what makes the refresh-and-retry pattern possible while keeping a network error from logging the user out.

### Token expiry is discovered, never predicted

There is no timer, no `scenePhase` observer, no JWT `exp` parsing, and no expiry check anywhere in the app. The client has no idea when the 1-hour ID token dies. It finds out exactly one way: it makes a request, gets a 401 back, and reacts. Session state therefore only ever changes as a *consequence* of a network call — never on a clock.

This matters when diagnosing "it logged me out." A logout can only originate from the `else` branch below, which is reached after `await AuthManager.refresh(...)` has already completed and returned nil. There is no race and no timeout that can preempt a refresh in flight.

### The 401 / refresh / retry pattern

Duplicated verbatim at three call sites — `NotebookListView`'s sync button and both Save buttons in `NoteEditorView`:

```swift
case .unauthorized:
    if let newToken = await AuthManager.refresh(refreshToken: refreshToken) {
        authToken = newToken
        KeychainManager.save(token: newToken, key: "authToken")
        // retry the original call once with newToken
    } else {
        // delete both Keychain keys, clear authToken, isLoggedIn = false
    }
```

Any new AWS call site must follow it. Since it is copy-pasted, changing the pattern means changing all three places — they have already drifted slightly (the list view ignores the retry's result classification, the editor checks it).

## Backend contract

Region `ap-southeast-2`, account `421219980663`. Base URL `https://mhjsrxn5i2.execute-api.ap-southeast-2.amazonaws.com`. Cognito pool `ap-southeast-2_uf0HWfD76`, app client `559l79m5jdakfj5d7okp40940p` (no client secret).

| Endpoint | Body / query | Notes |
| --- | --- | --- |
| `POST /notebooks/{notebookId}/upload` | `fileContent`, `localChecksum`, `page_name` | Writes S3 only; an S3 trigger updates DynamoDB |
| `GET /notebooks/changes?since=` | — | Returns `{"changes":[{notebookId, lastModified, checksum, deviceId, syncStatus, fileContent}]}` |
| `POST /notebooks/{notebookId}/resolve` | `deviceId`, `localVersion`, `remoteVersion`, `resolution` | **Not wired into the client at all** |

It is an HTTP API (not REST), chosen for the native JWT authorizer. If you touch the Lambdas: claims are nested one level deeper than in REST APIs — `event['requestContext']['authorizer']['jwt']['claims']['sub']`. Also, the default 3s Lambda timeout has been hit repeatedly on first deploy (bump to 30s), and a fresh Lambda's execution role has CloudWatch Logs access only, so S3/DynamoDB permissions must be attached manually.

## Known gaps

These are understood and deferred, not oversights — don't "fix" them incidentally:

- `LoginPage` hardcodes `testuser@example.com` / `RealPass456!` into the fields for dev speed. There is no sign-up flow.
- Deleting a notebook removes it from the local `notebooks` array only. S3/DynamoDB never learn about it, so a subsequent sync resurrects it. Deferred to Sprint 4.
- `fetchChanges` passes a hardcoded `since` date, so every sync re-fetches everything. Incremental `lastSyncTime` is Sprint 4.
- Create-notebook has no validation — empty and duplicate names are accepted.
- No conflict resolution, no offline detection, no multi-page notebooks (one `.txt` per notebook). Sprints 2–4.
- **Open bug — diagnosed, deliberately unfixed.** `LoginPage.swift:28` saves the ID token under the Keychain account `"AuthToken"` while everything else reads/writes `"authToken"`. `kSecAttrAccount` is case-sensitive, so the launch-time auto-login in `ContentView.onAppear` finds nothing and drops the user at the login screen — on every relaunch, whether or not the token has expired. The in-session refresh path is unaffected, because the retry sites write the correctly-named key.

  Two things make this hard to confirm from the outside: `AuthManager.refresh` discards the Cognito error body (so a genuine refresh rejection is indistinguishable from any other failure), and `KeychainManager` ignores every `OSStatus`, so a failed Keychain write is silent.

  A fix was written and then reverted at Satvik's direction. Leave it alone.
