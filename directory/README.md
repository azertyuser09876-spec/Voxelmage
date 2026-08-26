# Annuaire VoxelMage (optionnel)

Le jeu **n'a pas besoin** de ce service :

| Situation | Ce qui marche sans rien installer |
|---|---|
| Meme reseau (maison, fibre, partage de connexion) | Les parties apparaissent toutes seules dans la liste (broadcast UDP) |
| Sur Internet | Le **code direct** de 8 caracteres contient l'adresse de l'hote |
| Liste publique figee | `docs/servers.json` publie par GitHub Pages |

Cet annuaire ajoute seulement :

* une **liste publique vivante** (les parties apparaissent et disparaissent toutes seules) ;
* la **resolution des codes courts a 6 caracteres** hors reseau local.

## Lancer en local

```bash
node directory/server.js       # ecoute sur le port 8080
```

## Deployer gratuitement

```bash
cd directory
fly launch --copy-config --now          # Fly.io
# ou
docker build -t voxelmage-dir . && docker run -p 8080:8080 voxelmage-dir
```

Render, Railway, Koyeb et Deta acceptent aussi directement le `Dockerfile`.

## Brancher le jeu dessus

Dans le jeu : **Options -> Annuaire dynamique**, coller l'URL (ex.
`https://voxelmage-directory.fly.dev`). C'est tout : l'hote annonce sa partie
automatiquement et les codes a 6 caracteres deviennent utilisables partout.

## API

| Methode | Route | Role |
|---|---|---|
| `GET` | `/servers` | liste des parties publiques |
| `GET` | `/resolve?code=ABC123` | resout un code court en `{ip, port}` |
| `POST` | `/announce` | l'hote annonce/rafraichit sa partie (toutes les 25 s) |
| `POST` | `/close` | l'hote ferme sa partie |

Une partie non rafraichie disparait au bout de 60 secondes.
