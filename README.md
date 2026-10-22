# Dev Cockpit — binaires

Les versions publiées de **Dev Cockpit**. Rien d'autre : le code source et son historique vivent
dans un dépôt privé, et ce dépôt-ci ne porte que les artefacts signés, leur `latest.json` et la
config distante.

C'est ce dépôt que l'app interroge pour ses mises à jour. Elle n'a donc besoin d'**aucun accès**
au dépôt de code.

## Installer

```bash
gh api repos/jeremie-vasco/dev-cockpit-dist/contents/install.sh --jq .content | base64 --decode | bash
```

`--beta` pour le canal beta, `--version vX.Y.Z` pour une version précise, `--deb` sous Linux pour
le paquet plutôt que l'AppImage. Les versions suivantes arrivent dans l'app, toutes seules.

## Ce que porte une release

| Fichier | Pour |
|---|---|
| `Dev.Cockpit_<version>_universal.app.tar.gz` + `.sig` | macOS, c'est ce que l'updater installe |
| `Dev.Cockpit_<version>_universal.dmg` | macOS, première installation à la main |
| `Dev.Cockpit_<version>_amd64.AppImage` + `.sig` | Linux, mise à jour automatique |
| `Dev.Cockpit_<version>_amd64.deb` + `.sig` | Linux, paquet (root, mises à jour manuelles) |
| `latest.json` | le manifeste que l'app lit : version, notes, signature par plateforme |

Chaque artefact est signé (minisign). L'app vérifie la signature avec sa clé publique intégrée et
refuse toute mise à jour dont la signature ne correspond pas.

La release fixe `remote-config` porte la configuration distante signée, que les apps relisent
toutes les heures.
