# Secrets

This repo uses [sops-nix](https://github.com/Mic92/sops-nix) with `age`
encryption. Encrypted files (like `secrets/caixa.yaml`) are safe to commit;
only the decrypted plaintext, and the private age key that can decrypt it,
are sensitive.

## Status

caixa's age keypair has already been generated (it doesn't need to happen
*on* caixa — it's just a keypair, generated wherever is convenient, the same
way you'd generate an SSH key before a server exists). Its public half is
already in `.sops.yaml`, and `secrets/caixa.yaml` is already sops-encrypted
against it.

**What's still needed before caixa can decrypt its own secrets:**

1. Copy the private key file you were given (`caixa-key.txt`) onto caixa, at:

   ```
   /var/lib/sops-nix/key.txt
   ```

   Do this any time before the first `nixos-rebuild switch` that uses this
   flake — e.g. right after first boot, via a USB stick, `scp`, or pasting it
   in during the install's live session. Permissions should be root-only
   (`chmod 600`).

2. Add the Cloudflare Tunnel's token (Zero Trust dashboard → Networks →
   Tunnels → this tunnel → Configure — it's the long string after
   `--token` in the install command shown there) as the
   `cloudflared_tunnel_token` key in `secrets/caixa.yaml`. Edit it in
   place with `sops` —
   this decrypts, opens your editor, and re-encrypts on save — you need
   the same `caixa-key.txt` available locally (e.g. also at
   `~/.config/sops/age/keys.txt`, sops's default lookup path) to do this:

   ```sh
   sops secrets/caixa.yaml
   ```

3. Commit the re-encrypted `secrets/caixa.yaml`.

## Rotating the Cloudflare Tunnel credentials later

Same as step 2 above — `sops secrets/caixa.yaml` decrypts, lets you edit,
and re-encrypts on save.

## Losing the private key

If `caixa-key.txt` / `/var/lib/sops-nix/key.txt` is lost, `secrets/caixa.yaml`
becomes permanently undecryptable as-is. Recovery: generate a fresh age
keypair, update `.sops.yaml` with the new public key, and re-encrypt
`secrets/caixa.yaml` from a plaintext copy of the secret (i.e. you'll need
the Cloudflare Tunnel's token again too).

## Bootstrapping marvin

marvin is a new physical host (see
`docs/superpowers/specs/2026-09-21-marvin-host-design.md`). Unlike caixa,
`secrets/marvin.yaml` does not exist yet -- `.sops.yaml` currently has a
placeholder public key for marvin (`&marvin`) that must be replaced before
this works. Steps, done by hand (not by this repo's automation):

1. Generate a real age keypair (anywhere, not necessarily on marvin):

   ```sh
   age-keygen -o keys/marvin-key.txt
   ```

   `keys/` is gitignored -- this private key file is never committed.

2. Replace the placeholder `&marvin age1PLACEHOLDER...` value in
   `.sops.yaml` with the real public key printed by `age-keygen` (also
   found in the comment atop `keys/marvin-key.txt`).

3. Generate the real password hash for henrique's local login on marvin:

   ```sh
   mkpasswd -m sha-512
   ```

4. Create `secrets/marvin.yaml` with that hash under
   `henrique_password_hash`, encrypting it against the now-real `&marvin`
   key from `.sops.yaml`:

   ```sh
   sops secrets/marvin.yaml
   ```

   (sops picks up the recipient from `.sops.yaml`'s `creation_rules` for
   this path automatically; you need `keys/marvin-key.txt` available
   locally, e.g. at `~/.config/sops/age/keys.txt`, to open/re-encrypt it
   again later.)

5. Commit both the updated `.sops.yaml` and the new `secrets/marvin.yaml`.

6. At install time, copy `keys/marvin-key.txt` to
   `/var/lib/sops-nix/key.txt` on marvin (root-only, `chmod 600`) before
   the first `nixos-rebuild switch` there.

marvin has no `cloudflared` (see the design spec), so there's no tunnel
token to add -- only `henrique_password_hash` is needed in
`secrets/marvin.yaml`.
