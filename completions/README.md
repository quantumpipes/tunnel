# Shell Completions for QP Tunnel

Tab-completion for all `tunnel-*.sh` commands, including dynamic peer and service name lookups.

## What Gets Completed

| Command | Completions |
|---|---|
| `tunnel-setup-relay.sh` | `--provider=`, `--host=`, `--user=`, `--generate-script` |
| `tunnel-setup-relay.sh --provider=` | `digitalocean`, `ssh`, `local`, `script` |
| `tunnel-remove-peer.sh` | Active peer names from `peers.json` |
| `tunnel-close.sh --name` | Active service names from `services.json` |
| `tunnel-open.sh` | `--name`, `--to`, `--port`, `--help` |
| `make` | All tunnel Makefile targets with descriptions (zsh) |

## Prerequisites

Dynamic completions require `jq` to parse config files. Install it if you haven't:

```bash
# macOS
brew install jq

# Debian/Ubuntu
sudo apt install jq
```

## Bash Installation

### Option A: Source in your profile

Add this line to `~/.bashrc` or `~/.bash_profile`:

```bash
source /path/to/tunnel/completions/tunnel.bash
```

### Option B: System-wide (Linux)

```bash
sudo cp completions/tunnel.bash /etc/bash_completion.d/tunnel
```

### Option C: Homebrew-managed (macOS)

```bash
cp completions/tunnel.bash "$(brew --prefix)/etc/bash_completion.d/tunnel"
```

### Verify

Open a new shell and type:

```bash
tunnel-setup-relay.sh --pr<TAB>
# Should complete to --provider=

tunnel-setup-relay.sh --provider=<TAB>
# Should show: digitalocean  ssh  local  script
```

## Zsh Installation

### Option A: User-local (recommended)

```bash
mkdir -p ~/.zsh/completions
cp completions/tunnel.zsh ~/.zsh/completions/_tunnel
```

Add to `~/.zshrc` (before `compinit`):

```zsh
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
```

### Option B: System-wide (Linux)

```bash
sudo cp completions/tunnel.zsh /usr/local/share/zsh/site-functions/_tunnel
```

### Option C: Homebrew-managed (macOS)

```bash
cp completions/tunnel.zsh "$(brew --prefix)/share/zsh/site-functions/_tunnel"
```

### Verify

Open a new shell and type:

```zsh
tunnel-setup-relay.sh --<TAB>
# Should show all options with descriptions

tunnel-close.sh --name <TAB>
# Should show active service names
```

## Configuration

The completions read config files from `$TUNNEL_CONFIG_DIR`. If that variable is not set, they default to `$HOME/.config/$TUNNEL_APP_NAME` (which itself defaults to `qp-tunnel`).

Override these in your shell profile if your tunnel uses a custom config path:

```bash
export TUNNEL_CONFIG_DIR="$HOME/.config/my-tunnel"
```

## Troubleshooting

**Completions not loading:** Make sure your shell is sourcing the file (bash) or that the file is in your `$fpath` (zsh). Run `complete -p tunnel-setup-relay.sh` (bash) or `whence -v _tunnel-setup-relay.sh` (zsh) to verify registration.

**Peer/service names not completing:** Check that `jq` is installed and that the config files exist:

```bash
ls "$(_tunnel_config_dir)/peers.json"
ls "$(_tunnel_config_dir)/services.json"
```

**Stale completions after zsh update:** Delete the compiled cache and restart:

```zsh
rm -f ~/.zcompdump
exec zsh
```
