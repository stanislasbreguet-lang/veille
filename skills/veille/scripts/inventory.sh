#!/bin/bash
# Inventaire des skills installés. Planifiable chaque semaine (launchd, cron) : il ne travaille que
# les semaines ISO paires, soit une semaine sur deux ; FORCE=1 pour forcer, NODIALOG=1 sans fenêtre macOS.
# Partie mécanique seulement : liste des skills et usage réel tiré des transcripts. Le tri (garder,
# fusionner, remplacer, retirer) se fait ensuite dans Claude avec le skill veille, section « Inventaire ».
set -u
[[ ${FORCE:-0} == 1 ]] || (( 10#$(date +%V) % 2 == 0 )) || exit 0

out_dir="$HOME/.claude/veille/inventaire"
mkdir -p "$out_dir"
out="$out_dir/$(date +%F).md"

usage() { # $1 = jours
  find "$HOME/.claude/projects" -name '*.jsonl' -mtime "-$1" -print0 | xargs -0 cat 2>/dev/null \
    | grep -o '"name":"Skill","input":{"skill":"[^"]*"' | sed 's/.*"skill":"//;s/"$//' | sort | uniq -c | sort -rn
}

skills() { # nom<TAB>origine, pour chaque SKILL.md actif
  for f in "$HOME"/.claude/skills/*/SKILL.md; do
    printf '%s\tperso (%s)\n' "$(sed -n 's/^name: *//p' "$f" | head -1)" "$(stat -f %Sm -t %F "$(dirname "$f")")"
  done
  find "$HOME/.claude/plugins/cache" "$HOME/.claude/plugins/synced" -name SKILL.md -not -path '*/.trash/*' 2>/dev/null \
    | while read -r f; do
        rel=${f#"$HOME"/.claude/plugins/}
        printf '%s\t%s\n' "$(sed -n 's/^name: *//p' "$f" | head -1)" "$(echo "$rel" | cut -d/ -f1-3)"
      done
}

{
  echo "# Inventaire des skills — $(date +%F)"
  echo
  echo "## Plugins activés (~/.claude/settings.json)"
  jq -r '.enabledPlugins // {} | to_entries[] | select(.value==true) | "- " + .key' "$HOME/.claude/settings.json"
  echo
  echo "## Usage sur 14 jours (appels du tool Skill)"
  echo '```'; usage 14; echo '```'
  echo
  echo "## Usage sur 60 jours"
  echo '```'; usage 60; echo '```'
  echo
  echo "## Skills installés ($(skills | sort -u | wc -l | tr -d ' '))"
  echo '```'; skills | sort -u; echo '```'
} > "$out"

[[ ${NODIALOG:-0} == 1 ]] && { echo "$out"; exit 0; }
r=$(osascript -e 'display dialog "Inventaire des skills prêt. Dans Claude, demande : « fais l’inventaire des skills »." with title "Skills" buttons {"Plus tard", "Voir le rapport"} default button "Voir le rapport" giving up after 3600' 2>/dev/null)
[[ $r == *"Voir le rapport"* ]] && open "$out"
exit 0
