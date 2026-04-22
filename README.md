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
- [docker/agent](/home/minigubben/utveckling_git/agentContainer/docker/agent)
- [scripts](/home/minigubben/utveckling_git/agentContainer/scripts)

## Environment

Copy `.env.example` to `.env`:

```bash
cp .env.example .env
```

Required settings:

- `HOST_WORKSPACE_ROOT=/home/your-user/dev_workspace`
- `CONTAINER_WORKSPACE_NAME=dev_workspace`
- `AGENT_UID=$(id -u)`
- `AGENT_GID=$(id -g)`
- `T3_WEB_PORT=3773`
- `T3_PUBLIC_BASE_URL=http://127.0.0.1:${T3_WEB_PORT}`

That mounts the host directory `/home/your-user/dev_workspace` as `/home/agent/dev_workspace` inside the container.

Optional git identity env vars are also passed through into the agent runtime:

- `GIT_AUTHOR_NAME`
- `GIT_AUTHOR_EMAIL`
- `GIT_COMMITTER_NAME`
- `GIT_COMMITTER_EMAIL`

## Start The Stack

Start:

```bash
docker compose up -d --build
```

Stop:

```bash
docker compose down --remove-orphans
```

If you generated a USB override, include it explicitly when using `docker compose` directly:

```bash
docker compose -f compose.yml -f compose.usb.generated.yml up -d --build
```

`scripts/up-local` still exists as a thin wrapper around the same compose setup and automatically includes `compose.usb.generated.yml` when present.

## Workspace Mount

The stack mounts one host workspace root into the remote user home directory and keeps only the top-level directory name.

Example:

- host: `/home/hostuser/dev_workspace`
- container: `/home/agent/dev_workspace`

This matches the current T3 remote limitation: projects can be added from the GUI when they live under the remote user home directory.

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
The helper defaults to `--ttl 30m`.

Examples:

```bash
scripts/t3-pairing-link
scripts/t3-pairing-link --ttl 5m
scripts/t3-pairing-link --base-url http://192.168.1.20:3773
scripts/t3-pairing-link --json
```

Use that URL in the AppImage under `Settings` -> `Connections` -> `Add environment`.

Important:

- pairing tokens are one-time credentials
- the startup token printed by `docker logs` is not meant to be reused repeatedly
- once a token is consumed, later pairing attempts with the same token will fail with `Invalid bootstrap credential`
- do not open the pairing URL in a browser first if you intend to use it in the AppImage

## Projects In T3

Add projects from the T3 UI using the container path under `/home/agent/${CONTAINER_WORKSPACE_NAME}`.

With the example environment above, projects live under `/home/agent/dev_workspace`.

## USB Pass-Through

By default, no USB devices are exposed.

Generate a selective override:

```bash
scripts/gen-usb-compose --device /dev/ttyACM0 --device /dev/bus/usb/001/005
```

That writes `compose.usb.generated.yml`.

Use it with either:

- `docker compose -f compose.yml -f compose.usb.generated.yml up -d --build`
- `scripts/up-local`

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
- compose rendering

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
