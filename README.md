# Agent Harness Container Stack

This repository runs a single Linux-first Docker container that contains:

- `codex`
- `opencode`
- `t3` in headless server mode for the web UI and AppImage remote pairing
- a rootless inner Docker daemon

The T3 AppImage is now treated purely as a remote client. It connects to the container through T3 pairing instead of launching `codex` through host-side wrapper scripts.

## What It Runs

- `agent`: Ubuntu-based container with:
  - `codex`
  - `opencode`
  - `t3 serve`
  - development tooling
  - its own rootless inner Docker daemon

## Prerequisites

- Linux host with Docker Engine and `docker compose`
- `/dev/fuse` available
- `/dev/net/tun` available
- user namespaces enabled
- outbound network access for image builds and provider traffic
- support for `CAP_SYS_ADMIN` on the outer `agent` container

Run:

```bash
scripts/doctor
```

## Layout

- [compose.yml](/home/minigubben/utveckling_git/agentContainer/compose.yml)
- [compose.local.yml](/home/minigubben/utveckling_git/agentContainer/compose.local.yml)
- [compose.remote.yml](/home/minigubben/utveckling_git/agentContainer/compose.remote.yml)
- [docker/agent](/home/minigubben/utveckling_git/agentContainer/docker/agent)
- [scripts](/home/minigubben/utveckling_git/agentContainer/scripts)

## Environment

Copy `.env.example` to `.env` if you want to run `docker compose` manually:

```bash
cp .env.example .env
```

The helper scripts set sane defaults automatically:

- `WORKSPACE_MODE=local-bind`
- `HOST_WORKSPACE_ROOT=$HOME`
- `CONTAINER_WORKSPACE_ROOT=/home/workspaces`
- `AGENT_UID=$(id -u)`
- `AGENT_GID=$(id -g)`
- `T3_WEB_PORT=3773`
- `T3_PUBLIC_BASE_URL=http://127.0.0.1:${T3_WEB_PORT}`

## Start The Stack

Local bind mode keeps host and container workspace paths identical:

```bash
scripts/up-local
```

Remote volume mode uses a named volume mounted at `CONTAINER_WORKSPACE_ROOT`:

```bash
scripts/up-remote
```

Stop the stack:

```bash
scripts/down
```

## Workspace Modes

### `local-bind`

This mounts `HOST_WORKSPACE_ROOT` at the exact same path in the container. Use this mode when you want Git worktrees to work seamlessly inside and outside the container.

### `remote-volume`

This mounts the named `remote-workspace` volume at `CONTAINER_WORKSPACE_ROOT`. Use:

```bash
WORKSPACE_MODE=remote-volume scripts/workspace-clone <git-url> <target-path>
WORKSPACE_MODE=remote-volume scripts/workspace-sync push <local-path> <container-path>
WORKSPACE_MODE=remote-volume scripts/workspace-sync pull <container-path> <local-path>
```

`target-path` and `container-path` can be absolute, or relative to `CONTAINER_WORKSPACE_ROOT`.

Host/container path identity is not preserved in remote-volume mode.

## Web UI

Start the stack and open:

```text
http://127.0.0.1:3773
```

The T3 backend runs inside the `agent` container in headless server mode.

## T3 AppImage Flow

Run the AppImage on the host and connect it as a remote T3 client.

To create a fresh pairing link for the AppImage:

```bash
scripts/t3-pairing-link
```

This issues a new pairing token from the container and prints a ready `/pair#token=...` URL based on `T3_PUBLIC_BASE_URL`.

Examples:

```bash
scripts/t3-pairing-link
scripts/t3-pairing-link --base-url http://192.168.1.20:3773
scripts/t3-pairing-link --json
```

Use that URL in the AppImage under `Settings` -> `Connections` -> `Add environment`.

## Project Management

T3 upstream still has a limitation for remote environments: the GUI does not fully support adding projects remotely yet.

For now, add projects on the server side with:

```bash
scripts/t3-project-add /absolute/path/to/project
scripts/t3-project-add /absolute/path/to/project --title "My Project"
```

In `local-bind` mode, use the same absolute path you use on the host.

In `remote-volume` mode, use the container path under `CONTAINER_WORKSPACE_ROOT`.

## USB Pass-Through

By default, no USB devices are exposed.

Generate a selective override:

```bash
scripts/gen-usb-compose --device /dev/ttyACM0 --device /dev/bus/usb/001/005
```

That writes `compose.usb.generated.yml`. The helper scripts automatically include it when present.

Only the `agent` service gets:

- selected `devices:`
- matching `group_add:`
- `/run/udev:/run/udev:ro`

## Validation

Run:

```bash
scripts/check
```

This validates:

- shell syntax
- local-bind compose rendering
- remote-volume compose rendering

## Notes

- The outer container is not privileged.
- The `agent` service still needs `CAP_SYS_ADMIN` so rootless Docker can create its inner user namespace and networking stack without `--privileged`.
- The `agent` service also needs `/dev/net/tun` so RootlessKit can create the tap device used by slirp4netns.
- The `agent` service also uses `systempaths=unconfined` so the inner rootless daemon can mount `/proc` for the containers it starts.
- `t3 serve` runs inside the same `agent` container as `codex` and `opencode`.
- No host Docker socket is mounted into the container.
- The inner Docker daemon lives inside `agent` and uses rootless mode.
- The AppImage is only a remote T3 client in this design.
- OpenCode is available in the container, but T3 is configured only for Codex in this first version.
