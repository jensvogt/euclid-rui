# Euclid RUI

A Qt6/QML desktop admin dashboard for the [Euclid](https://github.com/jensvogt/euclid) backend - a
header-routed HTTP gateway exposing account management, storage, queueing, notification, and key
management services behind a single endpoint.

## Modules

The dashboard covers the following Euclid modules:

| Module | Description |
|--------|-------------|
| EAM | Accounts, namespaces, users, and user groups |
| EQS | Queues and messages |
| ESM | Buckets and objects |
| ENS | Topics and messages |
| EKM | Encryption keys |
| EMM | Module registry / status |
| EMO | Monitoring metrics (CPU, memory, service counters) |

Each module has a live status overview plus list/detail pages for its resources, with tag
management, copy-to-clipboard identifiers, and context-menu actions (view details, delete, etc.)
throughout.

## How it talks to the backend

Euclid exposes a single POST endpoint; the target service and action are selected via
`x-euclid-target` / `x-euclid-action` request headers rather than distinct URLs. `EuclidBaseClient`
owns the shared `QNetworkAccessManager`, session token, and account/region/namespace state; each
module gets its own thin client (`EqsClient`, `EsmClient`, `EnsClient`, `EkmClient`, `EamClient`,
`EmmClient`, `EmoClient`) that composes `EuclidBaseClient` and issues requests through it, so every
client rides the same authenticated session.

## Requirements

- Qt 6.4+ (Core, Gui, Network, Qml, Quick, QuickControls2, QuickDialogs2)
- CMake 3.16+
- A C++23 compiler
- A running Euclid gateway (defaults to `https://localhost:5566/`, self-signed dev cert)

## Building

```bash
cmake -S . -B build -G Ninja -DCMAKE_PREFIX_PATH=/path/to/qt
cmake --build build
```

If `CMAKE_PREFIX_PATH` isn't set, it defaults to `/opt/qt-static` (a statically-linked Qt build).

## Running

```bash
./build/euclid_rui
```

By default the app shows a login dialog. To skip it (e.g. for scripting or development), pass
credentials on the command line:

```bash
./build/euclid_rui --user admin --password admin --namespace development
```

| Option | Description |
|--------|-------------|
| `-u`, `--user` | Username or email to sign in with |
| `-p`, `--password` | Password to sign in with |
| `-n`, `--namespace` | Namespace to select after signing in; defaults to the first available |

## Releases

Tagged releases are built via GitHub Actions (`.github/workflows/build-release.yml`), which builds
a static Qt from source (cached per OS) and packages `euclid_rui` as a self-contained binary for
Linux (`.deb`/`.rpm`), macOS (`.dmg`), and Windows (`.zip`) - see the
[releases page](https://github.com/jensvogt/euclid-rui/releases) or [Changelog](CHANGELOG.md).

### Installing via APT (Debian/Ubuntu)

Every release is also published to a signed APT repository, so updates can be picked up with the
regular `apt update`/`apt upgrade` workflow instead of manually downloading a new `.deb` each time:

```bash
curl -fsSL https://jensvogt.github.io/euclid-rui/apt/euclid-rui.gpg.asc \
  | sudo gpg --dearmor -o /usr/share/keyrings/euclid-rui.gpg
echo "deb [signed-by=/usr/share/keyrings/euclid-rui.gpg] https://jensvogt.github.io/euclid-rui/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/euclid-rui.list
sudo apt update
sudo apt install euclid-rui
```

From then on, `sudo apt update && sudo apt upgrade` will pick up new releases.
