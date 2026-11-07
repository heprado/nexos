{ pkgs, osConfig, ... }:
let
  # nh finds the flake via programs.nh.flake (modules/nixos/common.nix) and
  # the output via this machine's hostname, so the same commands are right
  # on caixa and marvin. It shows what changed (added/removed/updated
  # packages) after building, and asks for sudo itself only to activate --
  # use `nrs`, not `sudo nrs`. Commands rather than zsh aliases so they
  # also work from bash, scripts and coding agents; extra arguments pass
  # through to nh (e.g. `nrs --update`, `nrb --show-trace`).
  nhOs = name: action: pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = [ osConfig.programs.nh.package ];
    text = ''exec nh os ${action} "$@"'';
  };

  # `nfu` (nix flake update) tries an update without touching the repo: it
  # writes the updated lock to a cache file, asks Nix what this host would
  # have to build with it (a dry run, nothing is built), and shows which
  # inputs move, the packages to compile with how long they took here, and
  # whether any of them is heavy. `nfu apply` then copies that lock into the
  # flake. Input names as arguments update only those inputs.
  nfu = pkgs.writeShellApplication {
    name = "nfu";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.gawk pkgs.git pkgs.gnugrep pkgs.gnused pkgs.jq ];
    text = ''
      flake=${osConfig.programs.nh.flake}
      cache="''${XDG_CACHE_HOME:-$HOME/.cache}/nexos"
      candidate="$cache/flake.lock.candidate"

      # Colors and bold only on a terminal, like nh.
      if [ -t 1 ]; then
        b=$'\e[1m' dim=$'\e[2m' red=$'\e[31m' green=$'\e[32m' yellow=$'\e[33m' r=$'\e[0m'
      else
        b="" dim="" red="" green="" yellow="" r=""
      fi
      step() { printf '%s>%s %s%s%s\n' "$b$green" "$r" "$b" "$1" "$r"; }

      if [ "''${1:-}" = apply ]; then
        if [ ! -f "$candidate" ]; then
          printf '%serror:%s no checked update yet; run nfu first\n' "$b$red" "$r" >&2
          exit 1
        fi
        cp "$candidate" "$flake/flake.lock"
        rm "$candidate"
        step "flake.lock updated"
        printf '  Next: %snrb%s, then %snrt%s or %snrs%s\n' "$b" "$r" "$b" "$r" "$b" "$r"
        exit 0
      fi

      host=$(uname -n)
      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT

      # Updating asks GitHub's API for each input's latest commit, and without
      # a token that's 60 requests an hour per IP: past it, Nix keeps the
      # cached revisions. gh's login lifts the limit to 5000. Passed through
      # the environment, so it shows in no command line and lands in no file.
      if command -v gh > /dev/null && token=$(gh auth token 2> /dev/null); then
        export NIX_CONFIG="access-tokens = github.com=$token"
      fi

      # Which of the given inputs have a newer commit upstream than the lock's,
      # asked with git ls-remote: the git protocol, outside GitHub's API rate
      # limit, all at once. Prints "name<TAB>new<TAB>date of the new commit",
      # or "name<TAB>unchecked" when the remote couldn't be read; up-to-date
      # inputs print nothing.
      # A ref that's a tag is compared through the commit it points to (^{}).
      newer() {
        local name
        for name in "$@"; do
          (
            IFS=$'\t' read -r url ref rev < <(jq -r --arg k "$name" '
              .nodes[.nodes[.root].inputs[$k] | if type == "array" then .[0] else . end]
              | [(if .original.type == "github" then "https://github.com/\(.original.owner)/\(.original.repo)"
                  elif .original.type == "git" then .original.url
                  else "-" end),
                 (.original.ref // "-"), (.locked.rev // "-")] | @tsv' "$flake/flake.lock")
            if [ "$url" = - ] || [ "$rev" = - ]; then
              printf '%s\tunchecked\n' "$name"
              exit 0
            fi
            if [ "$ref" = - ]; then
              patterns=(HEAD)
            else
              patterns=("refs/heads/$ref" "refs/tags/$ref" "refs/tags/$ref^{}")
            fi
            if ! out=$(GIT_TERMINAL_PROMPT=0 git ls-remote "$url" "''${patterns[@]}" 2> /dev/null) || [ -z "$out" ]; then
              printf '%s\tunchecked\n' "$name"
              exit 0
            fi
            head=$(awk '$2 ~ /\^\{\}$/ { print $1; exit }' <<< "$out")
            [ -n "$head" ] || head=$(awk 'NR == 1 { print $1 }' <<< "$out")
            if [ "$head" != "$rev" ]; then
              # The new commit's date, the one Nix locks as lastModified: only
              # that commit object is fetched (no files, ~100 KB), and still no
              # API request.
              repo="$tmp/git-$name"
              git init -q --bare "$repo"
              date=$(GIT_TERMINAL_PROMPT=0 git -C "$repo" fetch -q --depth=1 --filter=tree:0 "$url" "$head" 2> /dev/null \
                && git -C "$repo" log -1 --format=%cs FETCH_HEAD || echo "?")
              printf '%s\tnew\t%s\n' "$name" "$date"
            fi
          ) > "$tmp/remote-$name" &
        done
        wait
        for name in "$@"; do
          cat "$tmp/remote-$name"
        done
      }

      # With no input names, on a terminal: a menu of every input, each with
      # how long its packages took to compile here the last time. The ones
      # with a newer commit upstream can be picked, all, some or one (arrows
      # move, Enter or Space marks, Enter on Continue goes on); the up-to-date
      # ones are shown greyed out and the cursor skips them.
      if [ "$#" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
        reports="''${XDG_STATE_HOME:-$HOME/.local/state}/nix-output-monitor/build-reports.csv"
        mapfile -t inputs < <(jq -r '.nodes[.root].inputs | keys[]' "$flake/flake.lock")
        n=''${#inputs[@]}
        printf '%s  Checking upstream for new commits...%s' "$dim" "$r"
        newer "''${inputs[@]}" > "$tmp/newer"
        printf '\r\e[2K'
        open=()
        for i in "''${!inputs[@]}"; do
          if grep -q "^''${inputs[i]}"$'\t' "$tmp/newer"; then open[i]=1; else open[i]=0; fi
        done
        if [ ! -s "$tmp/newer" ]; then
          printf '%s✔ Everything is up to date%s (%s inputs)\n' "$b$green" "$r" "$n"
          exit 0
        fi

        # Per input: the packages it provides (its packages.<system>), matched
        # by name against this host's system closure, with their last compile
        # times here from nix-output-monitor's history added up. nixpkgs gets
        # the rest: everything else that was ever compiled here, though it's
        # mostly fetched from the binary cache, so it's an upper bound. Takes
        # ~20 s, so the result is kept until the lock or the history changes.
        key=$({ cat "$flake/flake.lock"; stat -c %s "$reports" 2> /dev/null || true; } | sha256sum | cut -c1-16)
        times="$cache/nfu-input-times-$key.tsv"
        mkdir -p "$cache"
        if [ ! -f "$times" ]; then
          printf '%s  Adding up past compile times per input (once per lock)...%s' "$dim" "$r"
          nix eval --json --impure --expr "
            let f = builtins.getFlake \"git+file://$flake\"; in
            builtins.mapAttrs
              (n: i: map (p: (builtins.tryEval (p.pname or (builtins.parseDrvName p.name).name)).value or null)
                (builtins.attrValues (i.packages.$(uname -m)-linux or { })))
              (builtins.removeAttrs f.inputs [ \"self\" \"nixpkgs\" ])" 2> /dev/null \
            | jq -r 'to_entries[] | .key as $k | .value[] | select(. != null) | "\($k)\t\(.)"' > "$tmp/owners"
          drv=$(nix eval --raw "$flake#nixosConfigurations.$host.config.system.build.toplevel.drvPath" 2> /dev/null)
          nix derivation show -r "$drv" 2> /dev/null | jq -r '.derivations[] | .name' | sort -u > "$tmp/closure"
          awk -F '\t' -v reports="$reports" -v closure="$tmp/closure" '
            BEGIN { while ((getline l < reports) > 0) if (split(l, f, ",") >= 4) secs[f[2]] = f[4] + 0 }
            { owner[$2] = $1 }
            END {
              while ((getline name < closure) > 0) {
                p = name
                sub(/-[0-9].*$/, "", p)
                s = (name in secs) ? secs[name] : ((p in secs) ? secs[p] : -1)
                if (s < 0) continue
                who = "nixpkgs"
                for (q in owner) if (p == q || index(p, q "-") == 1) who = owner[q]
                t[who] += s
              }
              for (w in t) printf "%s\t%d\n", w, t[w]
            }' "$tmp/owners" > "$tmp/times"
          for old in "$cache"/nfu-input-times-*.tsv; do
            [ "$old" = "$times" ] || rm -f "$old"
          done
          mv "$tmp/times" "$times"
          printf '\r\e[2K'
        fi

        rows=()
        for i in "''${!inputs[@]}"; do
          name=''${inputs[i]}
          when=$(jq -r --arg k "$name" '
            .nodes[.nodes[.root].inputs[$k] | if type == "array" then .[0] else . end].locked.lastModified
            | if . then strftime("%Y-%m-%d") else "?" end' "$flake/flake.lock")
          s=$(awk -F '\t' -v k="$name" '$1 == k { print $2 }' "$times")
          if [ -z "$s" ]; then
            took="-"
          elif [ "$s" -lt 60 ]; then
            took="<1 min"
          else
            took="$(((s + 30) / 60)) min"
          fi
          if [ "$name" = nixpkgs ] && [ -n "$s" ]; then
            took="up to $took"
          fi
          # The new commit's date, or what's known instead of it.
          if [ "''${open[i]}" -eq 0 ]; then
            update="up to date"
          else
            update=$(awk -F '\t' -v k="$name" '$1 == k { print ($2 == "new") ? $3 : "unchecked" }' "$tmp/newer")
          fi
          # Days between the locked commit and the new one.
          behind="-"
          if from=$(date -d "$when" +%s 2> /dev/null) && to=$(date -d "$update" +%s 2> /dev/null); then
            behind="$(((to - from) / 86400)) d"
          fi
          rows+=("$(printf '%-22s %-10s  %-10s  %6s  %14s' "$name" "$when" "$update" "$behind" "$took")")
        done

        marked=()
        for i in "''${!inputs[@]}"; do
          marked[i]=0
        done
        cur=0 # 0: All, 1..n: the inputs, n+1: Continue
        drawn=""
        printf '\e[?25l'
        trap 'printf "\e[?25h"; rm -rf "$tmp"' EXIT

        # Moves the cursor one step (1 down, -1 up), wrapping around and
        # skipping the up-to-date inputs.
        move() {
          local next=$cur
          while :; do
            next=$(((next + $1 + n + 2) % (n + 2)))
            if [ "$next" -eq 0 ] || [ "$next" -eq $((n + 1)) ] || [ "''${open[next-1]}" -eq 1 ]; then
              break
            fi
          done
          cur=$next
        }

        draw() {
          local count=0 all=1 i line
          for i in "''${!inputs[@]}"; do
            count=$((count + marked[i]))
            if [ "''${open[i]}" -eq 1 ] && [ "''${marked[i]}" -eq 0 ]; then all=0; fi
          done
          [ -z "$drawn" ] || printf '\e[%dA' "$((n + 4))"
          drawn=1
          printf '\e[2K%s>%s %sChoose inputs%s  %s↑↓ move · Enter or Space mark · q quit%s\n' "$b$green" "$r" "$b" "$r" "$dim" "$r"
          printf '\e[2K      %s%-22s %-10s  %-10s  %6s  %14s%s\n' "$dim" "" "locked" "update" "behind" "last compile" "$r"
          line="[$([ "$all" -eq 1 ] && echo x || echo " ")] All"
          if [ "$cur" -eq 0 ]; then printf '\e[2K\e[7m%s\e[0m\n' "  $line"; else printf '\e[2K  %s\n' "$line"; fi
          for i in "''${!inputs[@]}"; do
            if [ "''${open[i]}" -eq 0 ]; then
              printf '\e[2K  %s ✔  %s%s\n' "$dim" "''${rows[i]}" "$r"
              continue
            fi
            line="[$([ "''${marked[i]}" -eq 1 ] && echo x || echo " ")] ''${rows[i]}"
            if [ "$cur" -eq $((i + 1)) ]; then printf '\e[2K\e[7m%s\e[0m\n' "  $line"; else printf '\e[2K  %s\n' "$line"; fi
          done
          line="→ Continue ($count chosen)"
          if [ "$cur" -eq $((n + 1)) ]; then printf '\e[2K\e[7m%s\e[0m\n' "  $line"; else printf '\e[2K  %s%s%s\n' "$b" "$line" "$r"; fi
        }

        while :; do
          draw
          IFS= read -rsn1 k
          case "$k" in
            $'\e')
              rest=""
              IFS= read -rsn2 -t 0.05 rest || true
              case "$rest" in
                "[A") move -1 ;;
                "[B") move 1 ;;
              esac
              ;;
            k) move -1 ;;
            j) move 1 ;;
            q | Q) exit 0 ;;
            "" | " ")
              if [ "$cur" -eq 0 ]; then
                # All: marks every input that can be updated, or clears them.
                all=1
                for i in "''${!inputs[@]}"; do
                  if [ "''${open[i]}" -eq 1 ] && [ "''${marked[i]}" -eq 0 ]; then all=0; fi
                done
                for i in "''${!inputs[@]}"; do
                  marked[i]=$(((1 - all) * open[i]))
                done
              elif [ "$cur" -le "$n" ]; then
                marked[cur-1]=$((1 - marked[cur-1]))
              else
                picked=()
                for i in "''${!inputs[@]}"; do
                  [ "''${marked[i]}" -eq 0 ] || picked+=("''${inputs[i]}")
                done
                [ "''${#picked[@]}" -eq 0 ] || break
              fi
              ;;
          esac
        done
        printf '\e[?25h'
        # By name even when all are marked: the up-to-date inputs stay out of
        # the update and cost no API request.
        set -- "''${picked[@]}"
        checked=1
      fi

      # Any number of input names (nfu nixpkgs helium-flake disko). Names that
      # aren't inputs get a warning with the ones there are, and are dropped;
      # the rest go on.
      if [ "$#" -gt 0 ]; then
        valid=()
        for name in "$@"; do
          if jq -e --arg k "$name" '.nodes[.root].inputs | has($k)' "$flake/flake.lock" > /dev/null; then
            valid+=("$name")
          else
            printf '%swarning:%s no input named %s%s%s\n' "$b$yellow" "$r" "$b" "$name" "$r" >&2
            missing=1
          fi
        done
        if [ -n "''${missing:-}" ]; then
          printf '  Inputs: %s\n' "$(jq -r '.nodes[.root].inputs | keys | join(", ")' "$flake/flake.lock")" >&2
        fi
        if [ "''${#valid[@]}" -eq 0 ]; then
          exit 1
        fi
        set -- "''${valid[@]}"

        # Named inputs that are already up to date upstream are skipped.
        if [ -z "''${checked:-}" ]; then
          newer "$@" > "$tmp/newer"
          mapfile -t stale < <(cut -f1 "$tmp/newer")
          for name in "$@"; do
            if ! printf '%s\n' "''${stale[@]}" | grep -qxF -- "$name"; then
              printf '  %s%s is up to date%s\n' "$dim" "$name" "$r"
            fi
          done
          if [ "''${#stale[@]}" -eq 0 ]; then
            printf '%s✔ Already up to date.%s\n' "$b$green" "$r"
            exit 0
          fi
          set -- "''${stale[@]}"
        fi
      fi

      # Each GitHub input costs one API request (its latest commit); the rest
      # (lab-vms is git) none. GitHub's rate_limit endpoint is free to ask,
      # so check the budget before starting rather than run out halfway.
      need=$(jq -r --arg picked "$*" '
        (.nodes) as $n
        | ($picked | split(" ") | map(select(. != ""))) as $p
        | [.nodes[.root].inputs | to_entries[]
           | select(($p | length) == 0 or (.key as $k | $p | index($k)))
           | $n[.value | if type == "array" then .[0] else . end].original.type
           | select(. == "github")] | length
      ' "$flake/flake.lock")
      if [ -n "''${token:-}" ]; then
        limit=$(gh api rate_limit --jq '.resources.core | "\(.remaining) \(.limit) \(.reset)"' 2> /dev/null || true)
      else
        limit=$(curl -fsS --max-time 10 https://api.github.com/rate_limit 2> /dev/null \
          | jq -r '.resources.core | "\(.remaining) \(.limit) \(.reset)"' || true)
      fi
      if [ -n "$limit" ]; then
        read -r left max reset <<< "$limit"
        at=$(date -d "@$reset" +%H:%M)
        if [ "$left" -lt "$need" ]; then
          printf '%serror:%s this needs %s GitHub API requests and %s of %s are left; the limit resets at %s\n' \
            "$b$red" "$r" "$need" "$left" "$max" "$at" >&2
          exit 1
        fi
        printf '  %sGitHub API: needs %s, %s of %s requests left (resets at %s)%s\n' "$dim" "$need" "$left" "$max" "$at" "$r"
      else
        printf '  %sGitHub API: couldn'"'"'t read the rate limit; %s requests needed%s\n' "$yellow" "$need" "$r"
      fi

      step "Updating ''${*:-all inputs} (into a scratch lock)"
      if ! (cd "$flake" && nix flake update "$@" --output-lock-file "$tmp/flake.lock") 2> "$tmp/update"; then
        grep -v 'is dirty' "$tmp/update" >&2
        exit 1
      fi
      if cmp -s "$tmp/flake.lock" "$flake/flake.lock"; then
        printf '%s✔ Already up to date.%s\n' "$b$green" "$r"
        exit 0
      fi

      # Root inputs whose locked revision changed: name, dates, short revs.
      jq -r --slurpfile new "$tmp/flake.lock" '
        def roots: . as $l | $l.nodes[$l.root].inputs | to_entries
          | map({ key, value: ($l.nodes[.value | if type == "array" then .[0] else . end].locked // {}) })
          | from_entries;
        def day: if . then strftime("%Y-%m-%d") else "?" end;
        roots as $old | ($new[0] | roots) as $now
        | $now | keys[] as $k
        | select(($old[$k].rev // $old[$k].narHash) != ($now[$k].rev // $now[$k].narHash))
        | [$k, ($old[$k].lastModified | day), ($now[$k].lastModified | day),
           (($old[$k].rev // "")[0:7]), (($now[$k].rev // "")[0:7])] | @tsv
      ' "$flake/flake.lock" | while IFS=$'\t' read -r name from to oldrev newrev; do
        printf '  %-22s %s → %s%s%s  %s%s → %s%s\n' "$name" "$from" "$b" "$to" "$r" "$dim" "$oldrev" "$newrev" "$r"
      done

      step "Asking Nix what $host would build (dry run)"
      if ! nix build --dry-run --reference-lock-file "$tmp/flake.lock" \
        "$flake#nixosConfigurations.$host.config.system.build.toplevel" 2> "$tmp/dry"; then
        grep -v 'is dirty' "$tmp/dry" >&2
        exit 1
      fi

      # Derivations to build, by name. Config files, units and wrappers are
      # always built locally and take seconds; real packages carry a version.
      sed -n '/will be built:/,/will be fetched:/p' "$tmp/dry" \
        | grep -oE '/nix/store/[a-z0-9]{32}-[^ ]+\.drv' \
        | sed -E 's|^/nix/store/[a-z0-9]{32}-||; s|\.drv$||' \
        | grep -vE '^cargo-(package|src)-|-source$|\.(conf|json|txt|sh|desktop|service|patch|toml|tar\.[a-z]+)$' \
        | grep -vE -- '-(bwrap|init|fhsenv-[a-z]+|extracted|modules-shrunk)$' \
        | grep -E -- '-[0-9]+(\.[0-9]+)+' \
        | sort -u > "$tmp/packages" || true

      # How long each one took the last time it was compiled here, from the
      # history nix-output-monitor keeps (nrb/nrt/nrs build through it),
      # looked up by full name and then by name without the version.
      # -1: never compiled here.
      reports="''${XDG_STATE_HOME:-$HOME/.local/state}/nix-output-monitor/build-reports.csv"
      awk -v reports="$reports" '
        BEGIN {
          while ((getline line < reports) > 0) {
            if (split(line, f, ",") >= 4) secs[f[2]] = f[4] + 0
          }
        }
        {
          name = $0
          sub(/-[0-9].*$/, "", name)
          s = ($0 in secs) ? secs[$0] : ((name in secs) ? secs[name] : -1)
          print s "\t" $0
        }
      ' "$tmp/packages" | sort -t "$(printf '\t')" -k1,1nr > "$tmp/timed"

      # Heavy: 15 minutes or more here, or, never compiled here, one of the
      # packages known to take an hour or more. The version must end the
      # name: rust-overlay's prebuilt toolchains
      # (rustc-1.98.1-x86_64-unknown-linux-gnu) only get repackaged.
      known='^(electron(-unwrapped)?|chromium|ungoogled-chromium|nodejs(-slim)?|linux|llvm|clang|rustc|gcc|webkitgtk|qtwebengine|firefox|thunderbird|libreoffice|ghc|openjdk(-headless)?|cudatoolkit)-[0-9][^-]*$'
      awk -F '\t' -v known="$known" '{ print (($1 >= 900 || ($1 < 0 && $2 ~ known)) ? "heavy" : "-") "\t" $0 }' \
        "$tmp/timed" | LC_ALL=C sort -t "$(printf '\t')" -s -k1,1r > "$tmp/rated"

      # The whole list, for a closer look.
      mkdir -p "$cache"
      cut -f2- "$tmp/rated" > "$cache/nfu-packages.tsv"

      step "Packages to compile"
      awk -F '\t' -v b="$b" -v dim="$dim" -v red="$red" -v yellow="$yellow" -v r="$r" '
        {
          if ($1 == "heavy") {
            t = ($2 < 0) ? "?" : sprintf("%d min", ($2 + 30) / 60)
            printf "  %s%8s  %s%s  (heavy)\n", b red, t, $3, r
          } else if ($2 >= 60) {
            printf "  %s%8s%s  %s\n", yellow, sprintf("%d min", ($2 + 30) / 60), r, $3
          } else if ($2 >= 0) {
            fast++
          } else {
            unknown++
          }
          if ($2 > 0) total += $2
        }
        END {
          if (fast) printf "  %s%8s  %d more, under a minute each%s\n", dim, "<1 min", fast, r
          if (unknown) printf "  %s%8s  %d more, never compiled here%s\n", dim, "?", unknown, r
          printf "  %sKnown compile time: about %d min%s\n", b, (total + 30) / 60, r
        }
      ' "$tmp/rated"
      fetched=$(grep -oE 'these [0-9]+ paths will be fetched \([^,)]*' "$tmp/dry" | sed -E 's/these ([0-9]+) paths will be fetched \(/\1 paths, /' || true)
      [ -n "$fetched" ] && printf '  Download: %s\n' "$fetched"
      printf '  %sFull list: %s%s\n' "$dim" "$cache/nfu-packages.tsv" "$r"
      echo

      cp "$tmp/flake.lock" "$candidate"
      heavy=$(awk -F '\t' '$1 == "heavy" { printf "%s%s", sep, $3; sep = ", " }' "$tmp/rated")
      if [ -n "$heavy" ]; then
        printf '%s✗ Not ready:%s %s still to compile, not in the binary cache yet.\n' "$b$red" "$r" "$heavy"
        printf '  Try again later, or apply anyway with %snfu apply%s\n' "$b" "$r"
      else
        printf '%s✔ Ready:%s nothing heavy to compile. Apply with %snfu apply%s\n' "$b$green" "$r" "$b" "$r"
      fi
    '';
  };
in
{
  home.packages = [
    # Renders Markdown in the terminal.
    pkgs.glow
    # Build and activate, and make it the boot default.
    (nhOs "nrs" "switch")
    # Activate now without making it the boot default, so a reboot falls
    # back to the previous generation.
    (nhOs "nrt" "test")
    # Only build and show the diff against the running system: no sudo, no
    # activation -- the safe check after editing the config. switch/test
    # keep their link in a temporary directory, but `nh os build` writes
    # ./result, so it goes to the runtime dir instead (nh refuses a second
    # -o, so for another path run `nh os build -o <path>` directly).
    (nhOs "nrb" ''build --out-link "''${XDG_RUNTIME_DIR:-/tmp}/nrb-result"'')
    nfu
  ];

  # git and gh through home-manager: gh's credential helper is written into
  # ~/.config/git/config with the current gh's path on every switch, where
  # `gh auth setup-git` pins a store path that a garbage collection removes.
  programs.git.enable = true;
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
    settings.git_protocol = "https";
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    # --cmd cd makes zoxide define `cd`/`cdi` itself instead of `z`/`zi` --
    # `cd <exact-or-partial-path>` still behaves like the real builtin, it
    # only adds frecency-based jumping on top (e.g. `cd nexos` from
    # anywhere), so muscle memory doesn't need to change.
    options = [ "--cmd" "cd" ];
  };
}
