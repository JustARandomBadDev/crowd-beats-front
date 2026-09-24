# Crowd Beats Frontend

Frontend mobile Flutter pour Crowd Beats, app mobile type Crowd DJ.

Le client implémente le parcours MVP invité : join par QR, restauration et heartbeat de session, room et queue REST, synchronisation WebSocket, recherche Spotify via le backend, proposition, vote et leave/changement de room.

## Installation

Version utilisée :

```sh
Flutter 3.41.9
Dart 3.11.5
```

Préparer les dépendances :

```sh
flutter pub get
```

## Lancement

Avec la configuration par défaut :

```sh
flutter run
```

Pour Android emulator, utiliser l'adresse spéciale de la machine hôte :

```sh
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8080 \
  --dart-define=WS_BASE_URL=ws://10.0.2.2:8080/ws
```

## Configuration Backend

Valeurs par défaut :

```txt
API_BASE_URL=http://localhost:8080
WS_BASE_URL=ws://localhost:8080/ws
```

Elles sont définies dans `lib/core/config/app_config.dart` et peuvent être surchargées au lancement avec `--dart-define`.

Les URL doivent avoir un schéma et un hôte valides. Les chemins REST `/api/v1/...` sont ajoutés par le client. Sur Android, le HTTP local est autorisé uniquement dans le build debug ; sur iOS, l'exception ATS ne concerne que le réseau local. Pour un appareil physique, fournir l'adresse LAN de la machine backend via `--dart-define`. Ne pas utiliser `localhost` sur l'appareil pour atteindre le PC.

Le backend local attendu :

```txt
API: http://localhost:8080
WebSocket: ws://localhost:8080/ws?room_id=<room_uuid>
```

Headers utilisés (`Authorization` uniquement pour les routes protégées) :

```txt
Content-Type: application/json
Authorization: Bearer <session_token>
```

## Parcours de test local

1. Lancer le backend local sur le port `8080`.
2. Créer une room côté backend.
3. Créer ou récupérer le QR code de join.
4. Lancer l'app Flutter avec `flutter run`.
5. Scanner le QR, saisir un pseudo et vérifier l'entrée dans la room.
6. Vérifier la queue initiale, la synchronisation temps réel, la recherche, la proposition et le vote.
7. Relancer l'app pour vérifier la restauration de session, puis utiliser `Leave` pour revenir au join.

## Structure

```txt
lib/
  core/
    api/
    websocket/
    storage/
    config/
  models/
  features/
    room/
    search/
    session/
    vote/
  main.dart
```

## Contrat backend

- Le contrat public backend est figé : les réponses REST utilisent l'enveloppe `data/error/meta` et des clés `snake_case`. Voir `../crowd-beats-api/docs/api.md`.
- Le join se fait par `POST /api/v1/rooms/join-by-qr` avec `qr_code` et `nickname`. La réponse contient `session.token` et `ws.url` (chemin relatif) ; le QR transmet un code, pas une image ou une URL renvoyée par l'API.
- Le WebSocket utilise `Authorization: Bearer <session_token>` et `room_id`. Après `sync_required`, charger `GET /api/v1/rooms/{roomID}/queue` ; `queue_updated` contient un snapshot complet. Voir `../crowd-beats-api/docs/websocket.md`.
- Les recherches Spotify passent exclusivement par le backend. Le client ne contient ni credential ni SDK Spotify.
- Les réponses REST confirment les propositions et votes personnels. Seuls les snapshots REST et `queue_updated` définissent la queue partagée et son ordre.
