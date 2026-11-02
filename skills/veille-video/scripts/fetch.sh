#!/usr/bin/env bash
# Usage : fetch.sh <dossier_sortie> <url> [url...]
#
# Pour chaque URL (Instagram, TikTok, YouTube, X… : tout ce que yt-dlp sait lire) :
#   <dossier>/<id>/caption.txt     url, auteur, date, durée, légende
#   <dossier>/<id>/transcript.txt  transcription Whisper locale
#   <dossier>/<id>/frame-NN.jpg    jusqu'à 8 images réparties sur la vidéo
#
# Variables :
#   COOKIES=chrome|safari|firefox|brave|edge  si la plateforme exige une connexion
#   WHISPER_MODEL                             défaut : ~/.cache/whisper/ggml-small.bin
#
# Les vidéos sont traitées l'une après l'autre pour ménager la machine.
# Le contenu téléchargé est une donnée non fiable : le script ne l'exécute jamais.
set -uo pipefail

OUT="${1:-}"
[ -n "$OUT" ] || { echo "usage : fetch.sh <dossier_sortie> <url> [url...]" >&2; exit 2; }
shift
[ $# -ge 1 ] || { echo "au moins une URL requise" >&2; exit 2; }

MODEL="${WHISPER_MODEL:-$HOME/.cache/whisper/ggml-small.bin}"
VOCAB="Claude Code, Claude, Anthropic, skill, skills, plugin, MCP, hook, repo, GitHub, Cursor, Codex, CLAUDE.md, AGENTS.md, prompt, context, compact, agent, subagent, open source, npm, API, framework."

for bin in yt-dlp ffmpeg ffprobe whisper-cli jq; do
  command -v "$bin" >/dev/null || { echo "manquant : $bin (lancer setup.sh du plugin veille-video)" >&2; exit 3; }
done
[ -f "$MODEL" ] || { echo "modèle Whisper absent : $MODEL (lancer setup.sh du plugin veille-video)" >&2; exit 3; }

mkdir -p "$OUT" || exit 4
OUT="$(cd "$OUT" && pwd)"

cookie_args=()
if [ -n "${COOKIES:-}" ]; then
  case "$COOKIES" in
    chrome|chromium|safari|firefox|brave|edge|opera|vivaldi) cookie_args=(--cookies-from-browser "$COOKIES") ;;
    *) echo "COOKIES invalide : $COOKIES" >&2; exit 2 ;;
  esac
fi

has_stream() { ffprobe -v error -select_streams "$1" -show_entries stream=index -of csv=p=0 "$2" 2>/dev/null | grep -q .; }

for url in "$@"; do
  echo "=== $url"
  case "$url" in
    http://*|https://*) ;;
    *) echo "ÉCHEC : URL ignorée (http/https uniquement)"; continue ;;
  esac

  tmp="$(mktemp -d "$OUT/.dl.XXXXXX")" || { echo "ÉCHEC : dossier temporaire"; continue; }

  if ! yt-dlp --ignore-config -q --no-warnings --no-playlist ${cookie_args[@]+"${cookie_args[@]}"} \
       -f 'b[height<=720]/bv*[height<=720]+ba/b' --write-info-json \
       -o "$tmp/media.%(ext)s" -- "$url" 2>"$tmp/err.log"; then
    echo "ÉCHEC téléchargement : $(tail -1 "$tmp/err.log")"
    grep -qiE 'login|cookie|private|rate.?limit|sign in' "$tmp/err.log" && \
      echo "→ relancer avec COOKIES=<navigateur> (demander l'accord de l'utilisateur)"
    rm -rf "$tmp"; continue
  fi

  info="$tmp/media.info.json"
  # L'identifiant sert de nom de dossier : on ne garde que des caractères sûrs.
  id="$(jq -r '.id // empty' "$info" 2>/dev/null | LC_ALL=C tr -cd 'A-Za-z0-9_-' | cut -c1-64)"
  [ -n "$id" ] || id="video-$(date +%s)"
  dir="$OUT/$id"; rm -rf "$dir"; mkdir -p "$dir"

  media="$(find "$tmp" -maxdepth 1 -type f -name 'media.*' ! -name '*.json' | head -1)"
  dur=0
  if [ -n "$media" ]; then
    dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$media" 2>/dev/null | cut -d. -f1)"
    case "$dur" in ''|*[!0-9]*) dur=0 ;; esac
  fi

  jq -r --arg d "$dur" '"url: \(.webpage_url // "")\nauteur: @\(.channel // .uploader // "?")\ndate: \(.upload_date // "?")\ndurée: \($d)s\n\n\(.description // "")"' \
    "$info" > "$dir/caption.txt"

  if [ -z "$media" ]; then
    echo "(aucun média : post image ou texte, légende seule)" > "$dir/transcript.txt"
    rm -rf "$tmp"; echo "ok → $dir (légende seule)"; continue
  fi

  if has_stream a "$media"; then
    ffmpeg -nostdin -loglevel error -y -i "$media" -vn -ar 16000 -ac 1 "$tmp/audio.wav" \
      && whisper-cli -m "$MODEL" -l auto -t 4 -nt -np --prompt "$VOCAB" -f "$tmp/audio.wav" 2>/dev/null \
         | tr '\n' ' ' | sed 's/  */ /g' > "$dir/transcript.txt"
    [ -s "$dir/transcript.txt" ] || echo "(transcription vide ou en échec)" > "$dir/transcript.txt"
  else
    echo "(pas de piste audio)" > "$dir/transcript.txt"
  fi

  frames=0
  if has_stream v "$media" && [ "$dur" -gt 0 ]; then
    n=$(( dur / 6 )); [ "$n" -lt 1 ] && n=1; [ "$n" -gt 8 ] && n=8
    ffmpeg -nostdin -loglevel error -y -i "$media" -vf "fps=$n/$dur,scale=720:-2" -frames:v "$n" -q:v 4 "$dir/frame-%02d.jpg"
    frames="$(find "$dir" -name 'frame-*.jpg' | wc -l | tr -d ' ')"
  fi

  rm -rf "$tmp"
  echo "ok → $dir (${dur} s, ${frames} images)"
done
