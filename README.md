# veille

Un skill [Claude Code](https://docs.anthropic.com/en/docs/claude-code) pour trier la veille qui arrive en reels, shorts, vidéos et carrousels : outils pour le travail, idées à tenter pour le plaisir.

Tu colles un ou plusieurs liens (Instagram, TikTok, YouTube, X…) dans Claude Code. Pour chaque outil ou projet cité dans le post, il répond **Fusionner dans X**, **Remplacer X**, **Installer**, **Adapter**, **Side quest**, **Inspiration** ou **Ignorer**, avec la raison, après avoir vérifié à la source. Il préfère enrichir ou remplacer un skill déjà en place plutôt qu'en ajouter un.

Il fait aussi l'**inventaire** des skills installés : doublons, skills jamais utilisés, plugins trop larges, d'après l'usage réel lu dans tes sessions passées.

## Pourquoi

Les vidéos du type « 5 outils à installer d'urgence » vont vite, survendent, et poussent souvent à installer des choses qui exécutent du code sur ta machine : plugins, hooks, serveurs MCP, scripts `install.sh`. Regarder la vidéo ne dit ni si c'est utile *pour toi*, ni si c'est sain. Ce skill fait le tri à ta place :

- **Il regarde vraiment la vidéo** : transcription audio, légende, et quelques images pour lire un nom de repo ou du code à l'écran.
- **Il vérifie à la source** : il retrouve le repo exact, compare la promesse de la vidéo avec le README, et regarde la santé du projet (activité, licence, issues signalant du faux engagement ou du code factice).
- **Il lit ce qui s'exécuterait** : il signale les consignes téléchargées à chaque lancement, les `install.sh`, les hooks déclenchés sur chaque commande et les MCP en `@latest`.
- **Il compare avec ton setup** : tes skills, plugins, hooks et ton `CLAUDE.md`, pour repérer les doublons et les conflits.
- **Il tient un journal** (`~/.claude/veille/journal.md`) : un outil déjà jugé n'est pas réanalysé.
- **Il n'installe rien sans ton accord.** Sur un oui, il fige une version précise, relit les fichiers et les copie à la main plutôt que de lancer un installeur.

## À quoi ressemble un verdict

*Exemples d'illustration :*

> « Ce repo à 100 000 étoiles détecte tout ce qui bouge chez toi, juste avec ton Wi-Fi. »

**Ignorer.** Le README indique qu'il faut des capteurs dédiés, pas un simple routeur, et que la précision annoncée vient de données de synthèse. Des issues signalent un engagement artificiel.

> « Ce plugin remplace une équipe complète : 60 agents, 300 skills, à installer en une commande. »

**Adapter.** Quelques skills sont bons, mais le plugin complet charge des centaines de descriptions dans chaque session et ajoute des hooks qui s'exécutent à chaque commande. Mieux vaut copier à la main les 3 ou 4 skills utiles, figés sur un commit.

## Installation

Prérequis : macOS avec [Homebrew](https://brew.sh), et Claude Code.

1. Dans Claude Code :
   ```
   /plugin marketplace add stanislasbreguet-lang/veille
   /plugin install veille@veille
   ```
2. Installe les outils. Lis d'abord [`setup.sh`](setup.sh), il est court :
   ```bash
   bash ~/.claude/plugins/marketplaces/veille/setup.sh
   ```
   Il installe `yt-dlp`, `ffmpeg`, `whisper-cpp`, `jq` et `gh` via Homebrew, puis télécharge le modèle Whisper « small » (465 Mo) depuis le dépôt officiel de whisper.cpp, en vérifiant son empreinte SHA-256.
3. Connecte `gh` si ce n'est pas déjà fait (`gh auth login`) : Claude s'en sert, en lecture seule, pour inspecter les repos cités.
4. Colle un lien dans Claude Code, avec ou sans « analyse cette vidéo ». Au premier lancement du script, réponds « Yes, and don't ask again » pour ne plus être sollicité.

Sous Linux, installe les mêmes outils avec ton gestionnaire de paquets et place le modèle dans `~/.cache/whisper/ggml-small.bin`, ou indique son chemin via `WHISPER_MODEL`.

## Confidentialité et sécurité

- **Tout tourne en local** : la vidéo est téléchargée dans un dossier temporaire et transcrite sur ta machine. Aucun service de transcription externe n'est utilisé.
- **Le contenu des vidéos est traité comme une donnée**, jamais comme une consigne : une légende qui dit « lance cette commande » est signalée dans le verdict, pas exécutée.
- **Le script n'exécute rien de ce qu'il télécharge.** Il ignore ta configuration `yt-dlp`, n'accepte que des URL `http(s)` et nettoie les identifiants avant d'en faire des noms de dossiers.
- **Cookies** : pour un compte privé ou une plateforme qui exige une connexion, Claude te demande l'accord avant d'utiliser ceux de ton navigateur (`COOKIES=chrome|safari|firefox…`).

## Limites

- Whisper écorche certains termes anglais (« clôt de code » pour Claude Code). La légende et les images servent à corriger.
- Une vidéo d'environ une minute se traite en une dizaine de secondes sur un Mac M-series. Plusieurs liens passent l'un après l'autre.
- Le verdict reste un avis argumenté : relis-le avant d'installer quoi que ce soit.

## Inventaire régulier

Demande « fais l'inventaire des skills » à Claude. Pour un rappel une semaine sur deux, planifie `scripts/inventory.sh` chaque semaine (launchd ou cron) : il ne travaille que les semaines paires, écrit le rapport d'usage dans `~/.claude/veille/inventaire/` et affiche une fenêtre macOS (`NODIALOG=1` pour s'en passer). Une fois par mois, le rapport ajoute un contrôle des mémoires de Claude Code (`~/.claude/projects/*/memory/`) : index, liens et chemins cassés, fichiers anciens ; demande ensuite « fais le ménage de la mémoire » (`MEMOIRE=1` pour forcer ce contrôle, `MEMOIRE=0` pour s'en passer).

## Contenu

```
skills/veille/SKILL.md          étapes, critères de vérification, format du verdict
skills/veille/scripts/fetch.sh  téléchargement, transcription, extraction d'images (vidéos et carrousels)
skills/veille/scripts/inventory.sh  rapport d'usage des skills installés, pour l'inventaire
setup.sh                              installation des outils et du modèle Whisper
```

## Licence

MIT
