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

2. Add the Cloudflare Tunnel's `credentials.json` content (written by
   `cloudflared tunnel create` to `~/.cloudflared/<tunnel-id>.json`, or
   downloadable from the Zero Trust dashboard for that tunnel) as the
   `cloudflared_tunnel_credentials` key in `secrets/caixa.yaml` — paste the
   whole JSON file content as the value. Edit it in place with `sops` —
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
the Cloudflare Tunnel's `credentials.json` again too).
