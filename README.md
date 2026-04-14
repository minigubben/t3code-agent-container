# Agent Harness Container Stack

This repository builds a Linux-first Docker stack for running `codex` and `opencode` inside an isolated container, while keeping both T3 web mode and a host-run T3 AppImage usable.

## What It Runs

- `agent`: Ubuntu-based container with:
  - `codex`
  - `opencode`
  - development tooling
  - an SSH server
  - its own rootless inner Docker daemon
- `t3-web`: separate container that runs `npx t3 ...` and reaches `codex` through SSH wrapper binaries
- host wrappers:
  - `~/.local/bin/codex-remote`
  - `~/.local/bin/opencode-remote`

## Prerequisites

- Linux host with Docker Engine and `docker compose`
- `/dev/fuse` available
- `/dev/net/tun` available
- user namespaces enabled
- outbound network access for image builds and `npx t3`
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
- [docker/t3-web](/home/minigubben/utveckling_git/agentContainer/docker/t3-web)
- [scripts](/home/minigubben/utveckling_git/agentContainer/scripts)
- [host-bin](/home/minigubben/utveckling_git/agentContainer/host-bin)

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
- `AGENT_SSH_PORT=47722`
- `T3_WEB_PORT=3773`
- `T3_AGENT_PRIVATE_KEY_PATH=$HOME/.config/agent-harness/t3-agent/id_ed25519`
- `T3_AGENT_PUBLIC_KEY_PATH=$HOME/.config/agent-harness/t3-agent/id_ed25519.pub`

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

This mounts `HOST_WORKSPACE_ROOT` at the exact same path in both containers. Use this mode when you want Git worktrees to work seamlessly inside and outside the container.

### `remote-volume`

This mounts the named `remote-workspace` volume at `CONTAINER_WORKSPACE_ROOT` in both containers. Use:

```bash
WORKSPACE_MODE=remote-volume scripts/workspace-clone <git-url> <target-path>
WORKSPACE_MODE=remote-volume scripts/workspace-sync push <local-path> <container-path>
WORKSPACE_MODE=remote-volume scripts/workspace-sync pull <container-path> <local-path>
```

`target-path` and `container-path` can be absolute, or relative to `CONTAINER_WORKSPACE_ROOT`.

Host/container path identity is not preserved in remote-volume mode.

## T3 Web Mode

Start the stack and open:

```text
http://127.0.0.1:3773
```

The first boot writes T3 server settings to:

```text
$T3CODE_HOME/userdata/settings.json
```

with:

- `providers.codex.binaryPath=/usr/local/bin/codex-remote`
- `providers.codex.homePath=""`

The `t3-web` container does not run `codex` locally. Its wrapper shells into the `agent` container over SSH and runs `/usr/local/bin/codex` there.

## T3 AppImage Flow

Install the host wrappers and host-side T3 settings:

```bash
scripts/install-host-t3-wrappers.sh
```

This will:

- generate the SSH keypair if missing
- install:
  - `~/.local/bin/codex-remote`
  - `~/.local/bin/opencode-remote`
- update `~/.t3/userdata/settings.json` so T3 uses `~/.local/bin/codex-remote`

The AppImage flow assumes `local-bind` mode so the current working directory exists at the same absolute path inside `agent`.

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
- `no-new-privileges` remains enabled on `t3-web`, but not on `agent`. This is required because Docker rootless mode explicitly relies on `newuidmap` and `newgidmap`.
- No host Docker socket is mounted into either service.
- The inner Docker daemon lives inside `agent` and uses rootless mode.
- OpenCode is available inside `agent` and through `opencode-remote`, but T3 is configured only for Codex in this first version.
