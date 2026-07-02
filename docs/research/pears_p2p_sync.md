# Research: Pears (Holepunch) as a P2P sync backbone for FicBatch

*Question: can we use Pears — not necessarily Bare standalone, but the Pear
P2P stack in general — to sync reading progress, library, and history between
devices?*

*Researched 2026-07 for iteration 3. Sources: docs.pears.com, the
holepunchto/pear-docs and holepunchto/bare-kit repositories.*

---

## 1. What Pears actually is

- **Pear** is Holepunch's installable P2P runtime + dev/deploy platform for
  **JavaScript** apps (desktop, terminal, mobile). Zero infrastructure: apps
  are distributed and updated peer-to-peer.
- **Bare** is the small, embeddable JS runtime underneath Pear. Unlike Node,
  embedding and mobile are first-class: it exposes a C API and ABI-stable
  native bindings. "Bare standalone" (the page you linked) is about packaging
  an app + runtime into a single executable with P2P over-the-air updates.
- The sync-relevant building blocks:
  - **Hypercore** — signed, append-only log with sparse replication.
  - **Hyperswarm** — DHT peer discovery + NAT hole-punching (UDP).
  - **Corestore** — manages collections of hypercores.
  - **Autobase** — multi-writer: each device appends ops to its own log; a
    causal DAG is deterministically linearized into a shared view. This is
    exactly the primitive you'd want for "N devices, each editing the same
    library".
  - **bare-kit** — embeds Bare in native apps as a "worklet" (web-worker-like
    thread) with an IPC stream; `bare-rpc` layers RPC on top. Official
    bindings: **Objective-C (iOS)** and **Java (Android)**; `linux/` and
    `win32/` directories exist but are undocumented. React Native is the
    documented app framework (`react-native-bare-kit`).
  - Holepunch's own example (Autopass) syncs password data between a desktop
    Pear app and a mobile app via invite-based pairing — directly analogous
    to our use case.

## 2. Could FicBatch use it?

**Conceptually, yes — it's a very good fit for the data model.** Library
membership, categories, favorites, reading progress and history are all
naturally expressible as an event log ("work 123 added to category X",
"progress(123) = chapter 4 @ 0.62"), which is what Autobase linearizes across
devices. Pairing via invites, end-to-end encryption, and no server matches
the app's "cross-platform first, no accounts" ethos.

**Practically, the integration cost for a Flutter app is high:**

| Concern | Detail |
|---|---|
| No Dart bindings | The whole stack is JavaScript. Nobody ships a Flutter/Dart binding for Hypercore/Autobase or bare-kit (checked pub.dev + GitHub topics). |
| Per-platform embedding | We'd write the sync engine in JS (bundled), then embed Bare via bare-kit using **platform channels**: Java on Android, Obj-C on iOS. Desktop (Windows/Linux/macOS) has no documented bare-kit API — we'd embed via the C API (FFI) or run a Bare **standalone sidecar** process and talk to it over a local socket. That's 3+ integrations to build and maintain. |
| Web is out | FicBatch also builds for web; Bare doesn't run in a browser. (Hypercore-in-browser needs relays, which reintroduces infrastructure.) |
| Both peers must be online | True P2P sync happens when two devices are up simultaneously (or via an always-on peer you run yourself). Background sync on mobile is constrained by OS schedulers. |
| Ecosystem maturity | Bare/bare-kit are young and moving fast; docs are thin outside React Native. |

**Effort estimate:** several weeks of work before first sync: JS sync backend
(Corestore + Autobase + Hyperswarm + pairing), three native embeddings, a
Dart↔IPC RPC bridge, plus schema/conflict design and migration. High ongoing
maintenance surface.

## 3. Alternatives, ranked by effort

1. **Folder-based sync using what we already shipped (lowest effort).**
   FicBatch already has a versioned JSON export/import with merge semantics
   that preserves reading progress, and a user-pickable, *portable* download
   folder (`{dir}/{id}.html`). Add an opt-in "Sync folder" mode: auto-export
   (debounced) into a chosen folder and auto-import-merge on launch/focus.
   Users point Syncthing / Dropbox / iCloud Drive / OneDrive at that folder
   and get multi-device sync on every platform — including nothing new to
   maintain. Syncthing itself is P2P, so a Syncthing-based setup is
   serverless too. **Recommended next step.**
2. **Dart-native CRDT (`crdt` / `sql_crdt` packages) + a transport.** Pure
   Dart merge semantics with true conflict-free multi-writer behavior; the
   open question remains transport/discovery (LAN-only via `
   flutter_p2p_connection`, or a small self-hosted endpoint). Medium effort.
3. **Pears/Bare embedding (highest fidelity to "true P2P", highest cost).**
   Worth revisiting if serverless device-to-device sync becomes a headline
   feature and the bare-kit desktop story matures — or if Holepunch ships
   official Flutter bindings.

## 3.5 Addendum (iteration 4): "why not just Rust compiled to all platforms?"

*User follow-up: rather than juggling many languages, wouldn't it be better to
use Rust and compile it everywhere? Web isn't supported anyway — and who needs
the web version when AO3 itself is a website; the app's value is the library/
offline reading on your own devices.*

Two separate points, both largely right:

1. **Web doesn't matter for sync.** Agreed — the browser can't do this app's
   core value (local library, offline files, background sync) anyway, so
   "no web support" should not veto a sync technology. That removes one of the
   blockers listed against Pears above.

2. **Rust is the right instinct for "one codebase, every platform" — but it
   doesn't unlock Pears.** The entire Pear stack (Hypercore 10, Autobase,
   Hyperswarm) is implemented **only in JavaScript**; the old community Rust
   port of Hypercore lags the protocol and has no Autobase or usable
   Hyperswarm. Choosing Rust means choosing a *different* P2P stack, not a
   Rust flavor of Pears:
   - **iroh** (n0-computer, reached 1.0): QUIC-based connections with NAT
     hole-punching, plus `iroh-blobs` (content-addressed transfer) and
     `iroh-docs` (multi-writer synced key-value store) — essentially the
     Rust-native equivalent of Hyperswarm + Hypercore/Autobase.
   - **automerge-rs** or other CRDTs for the merge layer if not using
     iroh-docs.
   - Bridged into Flutter once via **flutter_rust_bridge** or UniFFI-style
     FFI — a single native library compiled for Android/iOS/Windows/macOS/
     Linux, instead of per-platform JS-runtime embeddings.

   So if/when FicBatch outgrows the sync folder and wants built-in
   device-to-device sync, **Rust + iroh via flutter_rust_bridge is the
   preferred path** — one language, one artifact per platform, no embedded JS
   engine. It is still a multi-week effort (protocol/schema design, pairing
   UX, background execution on mobile), which is why the sync folder ships
   first: it delivers the user-visible feature now, and the merge semantics
   it hardens are exactly what an iroh-docs backend would reuse.

## 4. Recommendation

Don't adopt Pears now. The data-model fit is real, but for a Flutter app the
binding work (JS engine embedding on five platforms, no web) outweighs the
benefit while a near-zero-cost path exists: **evolve the existing
export/import into an automatic sync-folder mode** (option 1), which delivers
cross-device sync of library, progress, and history on every platform today
and keeps the door open — the same event/merge semantics we'd harden for the
sync folder are exactly what an Autobase backend would need later.

Proposed as a question in `question_4.md`.
