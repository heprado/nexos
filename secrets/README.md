# Secrets

This repo uses [sops-nix](https://github.com/Mic92/sops-nix) with `age`
encryption. Encrypted files (like `secrets/caixa.yaml`) are safe to commit;
only the decrypted plaintext, and the private age key that can decrypt it,
are sensitive.

## Status

Two recipients per file (see `.sops.yaml`):

- **admin**: henrique's own age key, post-quantum (`age-keygen -pq`),
  passphrase-protected, kept on a USB stick (`keys/admin.age` there), never
  in this repo. It's what edits and re-encrypts every secrets file, so no
  machine's key is ever needed for that.
- **the host**: caixa decrypts with its SSH host key, converted to age
  (`sops.age.sshKeyPaths`). `machines/caixa/install.sh` generates that key
  on the installer and re-encrypts `secrets/caixa.yaml` for it with the
  admin key, so no private key is carried to caixa.

## Editing a secret

With the stick mounted (asks for the admin passphrase):

```sh
SOPS_AGE_KEY_FILE=/path/to/stick/keys/admin.age sops secrets/caixa.yaml
```

Commit the re-encrypted file, then rebuild the host.

## A host key changes (reinstall)

`install.sh` handles it. By hand: put the new `ssh-to-age` recipient in
`.sops.yaml`, then `SOPS_AGE_KEY_FILE=.../admin.age sops updatekeys
secrets/<host>.yaml`.

## Losing the admin key

The hosts keep working (they decrypt with their own keys), but nothing can
be edited or re-encrypted any more. Recovery: a new admin key, and every
secret re-created from its source (password hash, Cloudflare Tunnel token).
Keep a second copy of `admin.age` somewhere other than the stick.

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
