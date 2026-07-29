# runcore

`runcore` is an `lxmd`-compatible (config/behavior) LXMF daemon that runs Reticulum in-process (no separate `rnsd`).

## Implemented (current)

### Go core

- Reticulum+LXMF in a single process (no `rnsd`), `lxmd`-compatible config/storage layout.
- Announces: sent automatically (periodic + change-driven) and received announces are persisted to `<configdir>/storage/announces.json`.
- Profile: lives on disk under `contacts/` (own profile is a folder tagged as `me`; LXMF id is stored in `contacts/<me>/lxmf`; avatar is `avatar.*`).
- Messages: inbound is written to `messages/<srcHashHex>/…`; outbound is triggered by dropping files into `send/<destHashHex>/…` (with xattr-based status).
- Interfaces: managed via config; Go handles network side, UI reads/writes files.

### Flutter host (iOS + Mac Catalyst)

- Flutter app lives in `flutter/` (Dart UI).
- iOS host app is `flutter/ios/Runner` and links `Runcore.xcframework` from `flutter/native/apple/Frameworks/iOS`.

## Screenshots
Screenshots below may differ from the current Flutter UI.

| Chat with images | Add new contact |
| --- | --- |
| ![Chats](screenshots/screenshot_1.png) | ![Image bubble](screenshots/screenshot_2.png) |

| Setting status | Profile |
| --- | --- |
| ![Fullscreen preview](screenshots/screenshot_3.png) | ![Diagnostics](screenshots/screenshot_4.png) |

## Quick start

Running without arguments creates an `lxmd`-compatible config directory and a default `config`.

```bash
go run ./cmd/runcore
```

Print an example config and exit:

```bash
go run ./cmd/runcore -exampleconfig
```

By default, the Reticulum config is generated once into `<configdir>/rns/config` from an embedded template (after that you can edit it manually).

## Using as a library

Minimal example:

```go
cfgDir := "/path/to/AppSupport/runcore"
_, _ = runcore.EnsureLXMDConfig(cfgDir)
_, _ = runcore.EnsureRNSConfig(cfgDir, 4)

n, err := runcore.Start(runcore.Options{Dir: cfgDir})
if err != nil { panic(err) }
defer n.Close()

n.SetInboundHandler(func(m *lxmf.LXMessage) {
	// m.TitleAsString(), m.ContentAsString(), m.SourceHash, ...
})
```

Config management (load/edit/save/reset defaults):

- Load: `runcore.LoadLXMDConfig(cfgDir)`
- Save: `runcore.SaveLXMDConfig(cfg, cfgDir)`
- Reset: `runcore.ResetLXMDConfig(cfgDir)`

Reticulum config:

- Ensure exists: `runcore.EnsureRNSConfig(cfgDir, logLevel)`
- Reset: `runcore.ResetRNSConfig(cfgDir, logLevel)`

## Two instances

Reticulum in `go-reticulum` is a singleton, so to run two nodes you must run two separate processes with different `-config` directories:

```bash
go run ./cmd/runcore -config .nodeA -v
go run ./cmd/runcore -config .nodeB -v
```
