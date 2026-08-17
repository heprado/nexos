{ pkgs, ... }:
let
  # piper1-gpl (OHF-Voice's actively-maintained fork, packaged as
  # pkgs.piper-tts -- pkgs.piper is a completely unrelated GTK app for
  # ratbagd mouse config, same name, different project) ignores its own
  # --config flag at runtime and always looks for "<model>.json" sitting
  # next to the .onnx file, so both fetched files have to land in the same
  # derivation output under matching names, not just be independently
  # fetched.
  piperVoice = pkgs.runCommand "piper-voice-pt_BR-faber-medium" { } ''
    mkdir -p "$out"
    ln -s ${pkgs.fetchurl {
      url = "https://huggingface.co/rhasspy/piper-voices/resolve/main/pt/pt_BR/faber/medium/pt_BR-faber-medium.onnx";
      sha256 = "19ssz4rkmx6abrfw805a7v859p63qiqbvrlg11brq834l3imb1c5";
    }} "$out/pt_BR-faber-medium.onnx"
    ln -s ${pkgs.fetchurl {
      url = "https://huggingface.co/rhasspy/piper-voices/resolve/main/pt/pt_BR/faber/medium/pt_BR-faber-medium.onnx.json";
      sha256 = "0vqx1baz0y5r0rawp4s8hm4vcjgv0kmlbi1jsxnw6gxfjphlssby";
    }} "$out/pt_BR-faber-medium.onnx.json"
  '';

  claudeSpeak = pkgs.writeShellApplication {
    name = "claude-speak";
    runtimeInputs = [ pkgs.jq pkgs.piper-tts pkgs.pipewire pkgs.gnused pkgs.coreutils ];
    text = ''
      # Stop hook payload (stdin JSON) only carries transcript_path/session_id,
      # not the response text itself -- has to be pulled out of the
      # transcript JSONL, where each line is a single content block (not one
      # line per turn). Walk the file from the end, collecting consecutive
      # trailing assistant "text" blocks (there can be more than one if the
      # final turn's answer was split across blocks) until hitting anything
      # else, which marks the start of this turn's actual response.
      transcript_path=$(jq -r '.transcript_path // empty')
      [ -n "$transcript_path" ] && [ -f "$transcript_path" ] || exit 0

      text=$(jq -s -r '
        reverse
        | reduce .[] as $item ({stop:false, texts:[]};
            if .stop then .
            elif ($item.type=="assistant" and (($item.message.content // [])[0].type // "")=="text") then
              .texts += [$item.message.content[0].text]
            else
              .stop = true
            end)
        | .texts | reverse | join("\n\n")
      ' "$transcript_path")
      [ -n "$text" ] || exit 0

      # Piper reads this literally -- strip fenced code blocks entirely
      # (nobody wants to hear a diff read aloud) and the common inline
      # markdown markup so it doesn't narrate asterisks/backticks/hashes.
      clean=$(printf '%s' "$text" \
        | sed '/^```/,/^```/d' \
        | sed -E 's/`[^`]*`/ /g; s/\[([^]]*)\]\([^)]*\)/\1/g; s/[*_#>`-]//g')
      [ -n "$clean" ] || exit 0

      wav=$(mktemp --suffix .wav)
      trap 'rm -f "$wav"' EXIT
      printf '%s' "$clean" | piper --model "${piperVoice}/pt_BR-faber-medium.onnx" --output_file "$wav"
      pw-play "$wav"
    '';
  };
in
{
  home.packages = [ claudeSpeak ];
}
