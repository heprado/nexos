# Secrets

This repo uses [sops-nix](https://github.com/Mic92/sops-nix) with `age`
encryption. Encrypted files are safe to commit; only the decrypted
plaintext (which never touches the repo) is sensitive.

## One-time setup on caixa

1. Generate caixa's age key (do this on caixa itself, as root):

   ```sh
   mkdir -p /var/lib/sops-nix
   age-keygen -o /var/lib/sops-nix/key.txt
   ```

   This prints a line like `Public key: age1...` — copy the `age1...` value.

2. Put that public key into `.sops.yaml` at the repo root, replacing the
   `age1REPLACEME...` placeholder.

3. Generate a Tailscale auth key from the
   [Tailscale admin console](https://login.tailscale.com/admin/settings/keys) —
   a reusable, tagged key (e.g. `tag:caixa`) is recommended so it survives
   reinstalls without manual re-auth each time.

4. Encrypt it into `secrets/caixa.yaml` (from the repo root, with `sops`
   installed):

   ```sh
   sops secrets/caixa.yaml
   ```

   This opens an editor; replace the `tailscale_authkey: REPLACE_ME`
   placeholder with the real key, save, and `sops` re-encrypts the file in
   place using the recipient(s) listed in `.sops.yaml`.

5. Commit the encrypted `secrets/caixa.yaml`.

## Rotating the key

Generate a new Tailscale auth key and repeat step 4 — `sops secrets/caixa.yaml`
decrypts, lets you edit, and re-encrypts on save.
