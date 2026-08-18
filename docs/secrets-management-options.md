# Secrets management options — notes only (no implementation)

## Context

`~/.continue/config.yaml` currently has the Bifrost AI Gateway API key inline in
plaintext. Widening the question: the same machine also has SSH keys and AWS
config/credentials to think about. This repo (`~/.config/nix`) is on the
`MacBookPro` profile, which deliberately has **no 1Password** (no `op` CLI, no
SSH agent socket, no 1Password antidote plugin — see `AGENTS.md`), so any
1Password-based approach (`op inject`, etc.) is off the table here.

Current state, confirmed by exploration:

- **SSH**: no private keys in the repo (correct). `programs.ssh` is
  home-manager-managed for non-secret settings only (`ServerAliveInterval`,
  `Host *` blocks) — `homeConfigurations/MacBookPro.nix:83-95`. No
  `IdentityAgent`/`IdentityFile` pointing at a real key; keys are expected to
  exist unmanaged in `~/.ssh` and picked up by default ssh-agent lookup. This
  is standard practice, not a gap.
- **AWS**: `awscli2` is installed (`MacBookPro.nix:20`), but `~/.aws/config`
  and `~/.aws/credentials` are entirely unmanaged — no home-manager
  `xdg.configFile`/`home.file` entries. `examples/aws-config.example` is a
  copy-by-hand template (SSO profiles + a commented legacy IAM-key section),
  not wired to activation.
- **Continue**: no home-manager management of `~/.continue` at all;
  `config.yaml` is a plain unmanaged file today, edited by hand.
- **Pattern precedent**: the repo already has a "managed base + writable local
  overlay" pattern (`docs/patterns.md:10-96`), used for opencode's
  `local.jsonc`, Claude Code's `settings.local.json`, and git identity's
  `~/.gitconfig.local`. Nothing currently applies it to SSH or AWS.
- **No secrets tooling present**: no `sops`, `age`, `gnupg`, `pass`, or
  `aws-vault` packages declared anywhere; no agenix/sops-nix flake inputs.
- **Git identity/signing files** (`~/.gitconfig.local`-style, machine-local,
  not in the repo) surfaced two more plaintext-secret cases while writing
  these notes:
  - `~/.gitconfig.work` embeds a GitLab personal access token directly in a
    `url.insteadOf` rewrite (`https://andrew.bell:glpat-...@gitlab...`). Same
    exposure shape as the Bifrost token — a long-lived credential sitting in
    plaintext in a dotfile.
  - `~/.gitconfig.personal` requires SSH commit signing via
    `~/.ssh/keys/id_ed25519_personal.pub`

## Option A — agenix

Encrypt secrets as `.age` files in the repo (`secrets/*.age`), decrypted to
`/run/agenix/<name>` at activation.

- Setup cost: new flake input, `secrets.nix` mapping secrets to recipient
  public keys, `agenix -e` per secret.
- **Bootstrap gap**: decryption needs an SSH (or age) key *already on disk* to
  act as the recipient identity. It can protect the Bifrost token and AWS
  credentials once a key exists, but it cannot solve "how does an SSH key get
  onto a fresh machine in the first place" — that stays a manual step either
  way.
- Git-tracked (encrypted), so secrets travel with the repo across machines.
- Effort: moderate–high. Best fit if you want secrets fully declarative and
  versioned, and you're willing to absorb the setup once.

## Option B — sops-nix

Single `secrets.yaml` with values encrypted, keys left as readable diffs.
Edited via `sops secrets.yaml` (transparent decrypt/re-encrypt in `$EDITOR`).
Home-manager module can place per-user secrets from it directly.

- Nicer day-to-day ergonomics than agenix (one file, readable diffs, easier
  review).
- Same bootstrap limitation as agenix: needs an age key on disk, conventionally
  derived from an SSH key via `ssh-to-age` — so it doesn't remove the manual
  "get a key onto this machine" step either.
- Effort: moderate. New flake input required.

## Option C — OS-native, no new tooling

No flake input. Use macOS Keychain for the long-lived secrets that actually
need encryption at rest (Bifrost token; any AWS long-lived IAM key, if one is
ever used instead of SSO); render them into config files via a small
activation script following the existing "managed base + writable overlay"
pattern.

- **Continue**: `security add-generic-password -a bifrost -s continue-gateway
  -w '<token>'` once per machine; activation script renders
  `~/.continue/config.yaml` from a checked-in template plus
  `security find-generic-password -w`.
- **AWS**: the *non-secret* parts (SSO `start_url`, `region`, role/profile
  blocks) can become home-manager-managed (`~/.aws/config`) since they hold no
  secret at all — only `~/.aws/sso/cache/` (short-lived SSO tokens, not
  long-lived keys) stays outside Nix's control, unmanaged, exactly like
  today's `.aws` handling but declarative for the config half.
- **SSH**: left exactly as-is — unmanaged files in `~/.ssh`, standard
  permissions, no change. Not a gap that needs solving.
- Effort: low. Per-machine manual step is a single `security` command,
  documented the same way `~/.gitconfig.local` already is for git identity.
- Trade-off: rendered `config.yaml` still holds the token in plaintext once
  written to disk (Continue reads plain YAML — no way around that at the
  consumer end), and Keychain access itself isn't tied to a repo-tracked
  encryption key, so it's less "declarative" than A/B.

## Summary

| | Setup cost | New flake input | Solves SSH bootstrap | Git-tracked | Fits "no 1Password" constraint |
|---|---|---|---|---|---|
| agenix | moderate–high | yes | no | yes (encrypted) | yes |
| sops-nix | moderate | yes | no | yes (encrypted) | yes |
| OS-native | low | no | no (leaves SSH unmanaged, as today) | no | yes |

None of the three make SSH-key provisioning itself declarative — that's a
pre-existing, separate problem (getting a private key onto a new machine at
all), not something any of these secrets managers change.

No decision made yet — this is notes only, per request.
