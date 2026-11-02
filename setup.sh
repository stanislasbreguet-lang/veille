#!/usr/bin/env bash
# Prérequis du skill veille-video (macOS + Homebrew). Lisible en 30 secondes, à lire avant de lancer.
# 1. installe yt-dlp, ffmpeg, whisper-cpp, jq et gh via Homebrew (ignorés s'ils sont déjà là) ;
# 2. télécharge le modèle Whisper « small » (465 Mo, bon en français) depuis le dépôt officiel
#    de whisper.cpp et vérifie son empreinte SHA-256 avant de le garder.
set -euo pipefail

command -v brew >/dev/null || { echo "Homebrew requis : https://brew.sh" >&2; exit 1; }
for f in yt-dlp ffmpeg whisper-cpp jq gh; do
  brew list --formula "$f" >/dev/null 2>&1 || brew install "$f"
done

MODEL_DIR="$HOME/.cache/whisper"; MODEL="$MODEL_DIR/ggml-small.bin"
SHA="1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
mkdir -p "$MODEL_DIR"
if [ -f "$MODEL" ] && [ "$(shasum -a 256 "$MODEL" | cut -d' ' -f1)" = "$SHA" ]; then
  echo "modèle déjà présent et vérifié"
else
  curl -fL --progress-bar -o "$MODEL.part" https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
  [ "$(shasum -a 256 "$MODEL.part" | cut -d' ' -f1)" = "$SHA" ] || { rm -f "$MODEL.part"; echo "empreinte invalide, modèle supprimé" >&2; exit 1; }
  mv "$MODEL.part" "$MODEL"; echo "modèle téléchargé et vérifié"
fi

mkdir -p "$HOME/.claude/veille"
[ -f "$HOME/.claude/veille/journal.md" ] || printf '# Journal de veille vidéo\n\ndate | vidéo | outil (repo) | verdict | raison\n--- | --- | --- | --- | ---\n' > "$HOME/.claude/veille/journal.md"
gh auth status >/dev/null 2>&1 || echo "conseil : lance « gh auth login » pour que Claude puisse vérifier les repos cités"
echo "prêt : colle un lien de vidéo dans Claude Code"
