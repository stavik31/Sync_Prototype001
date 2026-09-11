# Sync Interface Handoff

What to hand off, what each piece does, and how they connect — written in plain
words, no code, so it's readable without knowing Swift.

## What gets handed off — exactly 6 files

Copy these into the new client's project. Nothing else is required.

| File | Job |
|---|---|
| `Interface/SyncRemoteStore.swift` | The contract itself — a list of every sync operation a backend must be able to do (list notebooks, upload one, download one, delete one, etc). Mirrors the Android side's equivalent interface, method for method. |
| `Interface/SyncModels.swift` | The shapes of data that get passed around when those operations run — just descriptions of information, no behavior. |
| `Interface/AWSSyncRemoteStore.swift` | **The actual AWS implementation of the contract.** This is where the real work happens — it fulfills every promise made in `SyncRemoteStore.swift` by actually talking to AWS. |
| `AWS/SyncAPI.swift` | Every raw network call to the backend lives here — asking for the notebook list, asking for one notebook's file list, asking where to upload a file, asking where to download a file, locking/unlocking a notebook during publish. `AWSSyncRemoteStore` is the only thing that calls into this file. |
| `AWS/SyncTypes.swift` | Describes the exact shape of the JSON the backend sends and expects — nothing more than that. |
| `AWS/AuthManager.swift` | Talks to the login service (Cognito) directly — logging in, refreshing an expired session, and reading a user's id out of their login token. It doesn't store anything itself; it just hands results back to whoever asked. |

## How they connect — the chain of responsibility

Think of it as four layers, each one only knowing about the layer directly
below it:

1. **The contract** (`SyncRemoteStore.swift`) says what must be possible — it
   doesn't do anything itself, it's just a checklist.
2. **The AWS implementation** (`AWSSyncRemoteStore.swift`) is the thing that
   actually satisfies that checklist. Every method on the checklist has a real
   body here.
3. To do its job, the AWS implementation asks a lower layer, **the network
   layer** (`SyncAPI.swift`), to actually make the HTTP requests.
4. That network layer, in turn, leans on two small supporting pieces: one that
   knows the exact shape of the backend's data (`SyncTypes.swift`), and one
   that knows how to log in and refresh a session (`AuthManager.swift`).

`SyncModels.swift` sits slightly outside this chain — it's not a layer that
*does* anything, it's just the shared vocabulary (the data shapes) that every
layer above uses when talking to each other.

Nothing flows backwards. `AuthManager` doesn't know `SyncAPI` exists.
`SyncAPI` doesn't know `AWSSyncRemoteStore` exists. Each layer only reaches
downward, never up or sideways.

## What's actually working vs. still a placeholder

Of the 12 things the contract asks for, **5 are genuinely built and tested**:
checking availability, getting account details, listing notebooks, checking a
single notebook's latest version, uploading a notebook, and downloading a
notebook.

The other 7 are placeholders waiting on backend work that hasn't been
assigned yet — reading what's been deleted, deleting a notebook remotely,
reading and writing folder/category information, translating errors into a
standard shape, and writing out a deletion list to a file. None of these will
crash if called — they just don't do anything real yet. Each one is marked in
the code as waiting on further backend work.

## The one thing a new client actually has to supply — a login token

Neither the AWS implementation nor the network layer stores a login token
anywhere themselves, and neither of them knows anything about how *this* app
happens to store its own tokens. That was done on purpose, specifically so a
different client — with a completely different way of storing its own
login session — could plug in without needing to change either of these
files.

Concretely, a new client needs to do two things: hand the AWS implementation
whatever valid login token it currently has whenever it wants to do something,
and — separately — tell the network layer three things once, when its app
starts up: how to fetch its own saved session-renewal token when needed, what
to do when a session gets renewed (so the new token can be saved wherever that
client keeps it), and what to do if a renewal attempt fails (so the client can
clear its own session). Those three things exist because a login token can
expire in the middle of an operation, and when that happens, the network layer
needs a way to get a fresh one and hand it back — without ever needing to know
where or how that client stores it.

That's the entire integration point. Nothing else needs to be configured.

## How uploading and downloading actually work, in plain terms

Both directions follow the same overall shape: something first decides
*whether* a notebook needs syncing at all, and only once that's decided does
the actual network work begin.

That "deciding" step is deliberately **not** part of the handoff — it lives in
this app's own code, because it depends entirely on how this specific app
stores notebooks on someone's phone. A different client would need to write
its own version of that decision, based on its own local storage, but it would
call the exact same handoff methods to actually do the syncing once it's
decided something needs to happen.

**Uploading:** this app first figures out which pages of a notebook actually
changed, and copies just those changed pages into a temporary holding folder.
Once that's ready, it hands that whole folder to the AWS implementation, which
takes over from there — it locks the notebook so no other device can publish
conflicting changes at the same time, asks the server where to upload each
file, sends the files, tells the server the upload is complete, and then
releases the lock.

**Downloading:** this app first decides a given notebook needs to come down
from the server. Once that's decided, it hands the AWS implementation the
notebook's identity and the exact folder it should end up in. The AWS
implementation takes it from there — it asks the server what files exist,
downloads each one into a temporary holding folder first, double-checks that
nothing changed on the server while it was downloading, and only then swaps
the temporary folder in to become the real, final notebook folder — keeping a
backup of whatever was there before, in case that last step fails.

## Known limitations — not bugs, just not built yet

- Downloading a notebook always re-downloads every one of its files, even
  ones that haven't changed since the last time. It works correctly, it's
  just not the most efficient way to do it.
- There's one specific, known edge case around a page that gets deleted on
  the server at the exact same time a different device is downloading that
  notebook — it can survive locally when it shouldn't. This is called out
  directly in the code, right above the function it affects.
- Asking the server for a notebook's file list gives back the exact same
  "nothing here" answer whether the notebook genuinely doesn't exist or
  whether something else went wrong on the backend. This is a quirk of how
  the backend's permissions are currently set up, not something fixable from
  this side alone.
