{ pkgs, ... }:
let
  # "dii" -- there's no official female pt_BR voice in rhasspy/piper-voices
  # (only male: cadu/edresson/faber/jeff), so this comes from OpenVoiceOS's
  # community-trained collection instead.
  # See <https://huggingface.co/collections/OpenVoiceOS/pipertts-voices>.
  #
  # piper1-gpl (OHF-Voice's actively-maintained fork, packaged as
  # pkgs.piper-tts -- pkgs.piper is a completely unrelated GTK app for
  # ratbagd mouse config, same name, different project) ignores its own
  # --config flag at runtime and always looks for "<model>.json" sitting
  # next to the .onnx file, so both fetched files have to land in the same
  # derivation output under matching names, not just be independently
  # fetched.
  piperVoice = pkgs.runCommand "piper-voice-pt_BR-dii" { } ''
    mkdir -p "$out"
    ln -s ${pkgs.fetchurl {
      url = "https://huggingface.co/OpenVoiceOS/pipertts_pt-BR_dii/resolve/main/dii_pt-BR.onnx";
      sha256 = "0sq83phnzqllfz74rqibwxhgfc8h3jkzxznjw4ibk0klp93s85gv";
    }} "$out/dii_pt-BR.onnx"
    ln -s ${pkgs.fetchurl {
      url = "https://huggingface.co/OpenVoiceOS/pipertts_pt-BR_dii/resolve/main/dii_pt-BR.onnx.json";
      sha256 = "117cf23dhs5ayjyyqpg1841h87mkcnnqm7518ffl8sn9b8lrhs9h";
    }} "$out/dii_pt-BR.onnx.json"
  '';

  # Takes response text on stdin and speaks it -- deliberately dumb and
  # direct. This used to be wired as an automatic Stop hook, which only
  # gets a transcript_path (not the text itself) on stdin, forcing a whole
  # JSONL-scraping + async-write-race retry dance just to recover the
  # response text. Now it's called from the /voice skill instead (see
  # ~/.claude/skills/voice/SKILL.md below), which already has its own
  # response text in hand and can just pipe it straight in -- no hook, no
  # transcript, no race, no retry loop.
  claudeSpeak = pkgs.writeShellApplication {
    name = "claude-speak";
    runtimeInputs = [ pkgs.piper-tts pkgs.pipewire pkgs.gnused pkgs.coreutils ];
    text = ''
      text=$(cat)
      [ -n "$text" ] || exit 0

      # Piper reads this literally -- strip fenced code blocks entirely
      # (nobody wants to hear a diff read aloud) and the common inline
      # markdown markup so it doesn't narrate asterisks/backticks/hashes.
      # shellcheck disable=SC2016
      clean=$(printf '%s' "$text" \
        | sed '/^```/,/^```/d' \
        | sed -E 's/`[^`]*`/ /g; s/\[([^]]*)\]\([^)]*\)/\1/g; s/[*_#>`-]//g')
      [ -n "$clean" ] || exit 0

      wav=$(mktemp --suffix .wav)
      trap 'rm -f "$wav"' EXIT
      printf '%s' "$clean" | piper --model "${piperVoice}/dii_pt-BR.onnx" --output_file "$wav"
      # --volume is a stream-relative multiplier on top of whatever the
      # sink's own volume is currently set to, not an absolute level -- so
      # 0.5 here means "half however loud the system is right now".
      pw-play --volume 0.5 "$wav"
    '';
  };
in
{
  home.packages = [ claudeSpeak ];

  # Personal skill (not project-level), so ~/.claude/skills/ is the right
  # spot -- managed via home.file rather than left as a live hand-edited
  # file, same reasoning as ~/.claude/CLAUDE.md in modules/home/ai.nix:
  # this is owned, static content, not evolving app state (unlike
  # ~/.claude/settings.json, which stays hand-edited on purpose).
  home.file.".claude/skills/voice/SKILL.md".text = ''
    ---
    name: voice
    description: Speaks the assistant's current response aloud in Portuguese using local TTS (claude-speak/piper). ONLY invoke when the user explicitly runs the /voice command in that turn -- never proactively, regardless of how relevant it might seem.
    ---

    After writing your normal response for this turn, pipe that same
    response text (not a summary, not a paraphrase -- the literal text you
    just wrote) into `claude-speak` via stdin, e.g.:

    ```
    claude-speak <<'EOF'
    <your response text here>
    EOF
    ```

    claude-speak already strips markdown/code fences before synthesizing,
    so pass your response as written -- no need to clean it up by hand
    first. This only applies to the current turn; do not keep speaking
    subsequent responses unless /voice is invoked again.
  '';
}
