# Crowd Beats Frontend

Frontend mobile Flutter pour Crowd Beats, app mobile type Crowd DJ.

Ce dépôt contient uniquement le socle de développement frontend : bootstrap Flutter, configuration locale, clients API/WebSocket et stockage de token. Les modèles et parcours métier restent à implémenter selon le contrat figé du backend.

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

Le backend local attendu :

```txt
API: http://localhost:8080
WebSocket: ws://localhost:8080/ws?room_id=<room_uuid>
```

Headers utilisés :

```txt
Content-Type: application/json
Authorization: Bearer <session_token>
```

## Flow De Test Local

1. Lancer le backend local sur le port `8080`.
2. Créer une room côté backend.
3. Créer ou récupérer le QR code de join.
4. Lancer l'app Flutter avec `flutter run`.
5. Vérifier l'écran placeholder `App ready`.
6. Utiliser le bouton `Test API` pour vérifier `GET /health/ready` (HTTP 200 si PostgreSQL est disponible, 503 sinon).

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
    join/
    room/
  main.dart
```

## Limitations Actuelles

- Le contrat public backend est figé : les réponses REST utilisent l'enveloppe `data/error/meta` et des clés `snake_case`. Voir `../crowd-beats-api/docs/api.md`.
- Le join se fait par `POST /api/v1/rooms/join-by-qr` avec `qr_code` et `nickname`. La réponse contient `session.token` et `ws.url` (chemin relatif) ; le QR transmet un code, pas une image ou une URL renvoyée par l'API.
- Le WebSocket utilise `Authorization: Bearer <session_token>` et `room_id`. Après `sync_required`, charger `GET /api/v1/rooms/{roomID}/queue` ; `queue_updated` contient un snapshot complet. Voir `../crowd-beats-api/docs/websocket.md`.
- La restauration complète de session, la synchronisation de queue et les modèles contractuels restent à implémenter.
- Le MVP est en construction.
- Aucun écran métier complet n'est implémenté dans ce socle.
