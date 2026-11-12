#!/usr/bin/env bash
# Usage : fetch.sh <dossier_sortie> <url> [url...]
#
# Pour chaque URL (Instagram, TikTok, YouTube, X… : tout ce que yt-dlp sait lire) :
#   <dossier>/<id>/caption.txt     url, auteur, date, durée, légende
#   <dossier>/<id>/transcript.txt  transcription Whisper locale
#   <dossier>/<id>/frame-NN.jpg    vidéo : jusqu'à 8 images réparties sur la durée
#                                  carrousel ou post image : une image par élément (20 max)
#
# Carrousel (post Instagram à plusieurs éléments) : tous les éléments sont lus,
# quel que soit ?img_index. Les éléments vidéo qui ont du son (10 max) sont
# transcrits, chacun précédé de [élément NN].
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
MAX_ITEMS=20        # images gardées par carrousel
MAX_AUDIO_ITEMS=10  # éléments vidéo transcrits par carrousel

for bin in yt-dlp ffmpeg ffprobe whisper-cli jq; do
  command -v "$bin" >/dev/null || { echo "manquant : $bin (lancer setup.sh du plugin veille)" >&2; exit 3; }
done
[ -f "$MODEL" ] || { echo "modèle Whisper absent : $MODEL (lancer setup.sh du plugin veille)" >&2; exit 3; }

mkdir -p "$OUT" || exit 4
OUT="$(cd "$OUT" && pwd)"

cookie_args=()
if [ -n "${COOKIES:-}" ]; then
  case "$COOKIES" in
    chrome|chromium|safari|firefox|brave|edge|opera|vivaldi) cookie_args=(--cookies-from-browser "$COOKIES") ;;
    *) echo "COOKIES invalide : $COOKIES" >&2; exit 2 ;;
  esac
fi

ytdlp() { yt-dlp --ignore-config -q --no-warnings ${cookie_args[@]+"${cookie_args[@]}"} "$@"; }

has_stream() { ffprobe -v error -select_streams "$1" -show_entries stream=index -of csv=p=0 "$2" 2>/dev/null | grep -q .; }

# L'identifiant sert de nom de dossier : on ne garde que des caractères sûrs.
safe_id() { jq -r '.id // empty' "$1" 2>/dev/null | LC_ALL=C tr -cd 'A-Za-z0-9_-' | cut -c1-64; }

# write_caption <info.json> <dossier> <libellé durée>
write_caption() {
  jq -r --arg d "$3" '"url: \(.webpage_url // "")\nauteur: @\(.channel // .uploader // "?")\ndate: \(.upload_date // "?")\ndurée: \($d)\n\n\(.description // "")"' \
    "$1" > "$2/caption.txt"
}

# transcribe <média> <wav temporaire> : texte sur stdout, rien si pas de son
transcribe() {
  has_stream a "$1" || return 0
  ffmpeg -nostdin -loglevel error -y -i "$1" -vn -ar 16000 -ac 1 "$2" \
    && whisper-cli -m "$MODEL" -l auto -t 4 -nt -np --prompt "$VOCAB" -f "$2" 2>/dev/null \
       | tr '\n' ' ' | sed 's/  */ /g'
}

# fetch_gallery <url> <tmp> : carrousel ou post image.
# Code retour : 0 traité, 1 échec, 2 vidéo unique (à passer au chemin vidéo).
fetch_gallery() {
  local url="$1" tmp="$2" g="$2/gallery"
  mkdir -p "$g"
  ytdlp --ignore-no-formats-error --skip-download --write-info-json \
        --write-thumbnail --convert-thumbnails jpg --playlist-items "1:$MAX_ITEMS" \
        -o "$g/item-%(playlist_index|0)02d.%(ext)s" -- "$url" 2>"$tmp/err.log"
  local info="$g/item-00.info.json"
  [ -f "$info" ] || return 1

  local items
  items="$(find "$g" -name 'item-*.info.json' ! -name 'item-00.info.json' | wc -l | tr -d ' ')"
  if [ "$items" -eq 0 ]; then
    # Élément unique : s'il a des formats vidéo, c'est une vidéo ordinaire.
    [ "$(jq '.formats // [] | length' "$info")" -gt 0 ] && return 2
    items=1
  fi

  local id dir
  id="$(safe_id "$info")"; [ -n "$id" ] || id="post-$(date +%s)"
  dir="$OUT/$id"; rm -rf "$dir"; mkdir -p "$dir"
  write_caption "$info" "$dir" "— (post de $items élément(s))"

  local n=0 img
  while IFS= read -r img; do
    n=$((n + 1)); cp "$img" "$(printf '%s/frame-%02d.jpg' "$dir" "$n")"
  done < <(find "$g" -name 'item-*.jpg' | sort)

  local audio=0 f idx text
  : > "$dir/transcript.txt"
  while IFS= read -r f; do
    [ "$audio" -ge "$MAX_AUDIO_ITEMS" ] && break
    [ "$(jq '.formats // [] | length' "$f")" -gt 0 ] || continue
    idx="$(basename "$f" | sed -E 's/^item-0*([0-9]+)\.info\.json$/\1/')"
    case "$idx" in ''|*[!0-9]*) continue ;; esac
    rm -f "$tmp"/a.*
    ytdlp -f 'ba/b' --playlist-items "$idx" -o "$tmp/a.%(ext)s" -- "$url" 2>/dev/null || continue
    local media; media="$(find "$tmp" -maxdepth 1 -type f -name 'a.*' | head -1)"
    [ -n "$media" ] || continue
    text="$(transcribe "$media" "$tmp/audio.wav")"
    # Musique seule : Whisper ne rend que des balises comme [MUSIC PLAYING].
    if [ -n "$(printf '%s' "$text" | sed -E 's/\[[^]]*\]|\([^)]*\)//g' | tr -d '[:space:][:punct:]')" ]; then
      printf '[élément %02d] %s\n' "$idx" "$text" >> "$dir/transcript.txt"
      audio=$((audio + 1))
    fi
  done < <(find "$g" -name 'item-*.info.json' ! -name 'item-00.info.json' | sort)
  [ -s "$dir/transcript.txt" ] || echo "(aucun élément avec du son : images et légende seules)" > "$dir/transcript.txt"

  echo "ok → $dir (post de $items élément(s), $n images, $audio transcrit(s))"
  return 0
}

for url in "$@"; do
  echo "=== $url"
  case "$url" in
    http://*|https://*) ;;
    *) echo "ÉCHEC : URL ignorée (http/https uniquement)"; continue ;;
  esac

  tmp="$(mktemp -d "$OUT/.dl.XXXXXX")" || { echo "ÉCHEC : dossier temporaire"; continue; }

  # Un post Instagram peut être un carrousel : on le lit en entier d'abord.
  case "$url" in
    https://www.instagram.com/p/*|https://instagram.com/p/*)
      fetch_gallery "$url" "$tmp"; rc=$?
      [ "$rc" -eq 0 ] && { rm -rf "$tmp"; continue; }
      rm -rf "$tmp/gallery" ;;
  esac

  if ! ytdlp --no-playlist -f 'b[height<=720]/bv*[height<=720]+ba/b' --write-info-json \
       -o "$tmp/media.%(ext)s" -- "$url" 2>"$tmp/err.log"; then
    # Post sans vidéo (image seule) : on garde légende et image.
    if grep -q 'No video formats' "$tmp/err.log" && fetch_gallery "$url" "$tmp"; then
      rm -rf "$tmp"; continue
    fi
    echo "ÉCHEC téléchargement : $(tail -1 "$tmp/err.log")"
    grep -qiE 'login|cookie|private|rate.?limit|sign in' "$tmp/err.log" && \
      echo "→ relancer avec COOKIES=<navigateur> (demander l'accord de l'utilisateur)"
    rm -rf "$tmp"; continue
  fi

  info="$tmp/media.info.json"
  id="$(safe_id "$info")"
  [ -n "$id" ] || id="video-$(date +%s)"
  dir="$OUT/$id"; rm -rf "$dir"; mkdir -p "$dir"

  media="$(find "$tmp" -maxdepth 1 -type f -name 'media.*' ! -name '*.json' | head -1)"
  dur=0
  if [ -n "$media" ]; then
    dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$media" 2>/dev/null | cut -d. -f1)"
    case "$dur" in ''|*[!0-9]*) dur=0 ;; esac
  fi

  write_caption "$info" "$dir" "${dur}s"

  if [ -z "$media" ]; then
    echo "(aucun média : post image ou texte, légende seule)" > "$dir/transcript.txt"
    rm -rf "$tmp"; echo "ok → $dir (légende seule)"; continue
  fi

  if has_stream a "$media"; then
    transcribe "$media" "$tmp/audio.wav" > "$dir/transcript.txt"
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
