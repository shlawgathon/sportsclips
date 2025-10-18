# SportsClips Middleware API

This document describes the HTTP API exposed by the Ktor middleware service. It is up to date with the current routes defined in src/main/kotlin/Databases.kt and HTTP.kt.

Base URL: http://<host>:<port>

Authentication: Cookie-based session using USER_SESSION. Login returns Set-Cookie; client must store/send it with subsequent requests on all authenticated routes.

Updated: 2025-10-18

## Auth
- POST /auth/register
  - Request: {"username": string, "password": string, "profilePictureBase64"?: string}
  - Responses:
    - 201 Created: {"userId": string}
    - 409 Conflict: {"error": string}
- POST /auth/login
  - Request: {"username": string, "password": string}
  - Responses:
    - 200 OK: {"userId": string}, Set-Cookie: USER_SESSION=...
    - 401 Unauthorized
- POST /auth/logout
  - Request: none
  - Response: 200 OK, Set-Cookie clearing USER_SESSION

## Live Videos (authenticated)
- GET /live
  - Response: 200 OK: [ {"id": string, "live": LiveVideo} ]
- GET /live/{id}
  - Response: 200 OK: LiveVideo; 400 Bad Request; 404 Not Found
- POST /live
  - Request: {"title": string, "description": string, "streamUrl": string, "isLive"?: boolean}
  - Response: 201 Created: {"id": string}

LiveVideo schema:
{ "title": string, "description": string, "streamUrl": string, "isLive": boolean, "liveChatId"?: string, "createdAt": epochSeconds }

## Games (authenticated)
- POST /games
  - Request: {"gameId": string, "name": string, "sport": Sport}
  - Response: 201 Created: {"id": string}
- GET /games
  - Response: 200 OK: [ {"id": string, "game": LiveGame} ]
- GET /games/{gameId}
  - Response: 200 OK: {"id": string, "game": LiveGame}; 400; 404

LiveGame schema:
{ "gameId": string, "name": string, "sport": Sport, "createdAt": epochSeconds }

Sport enum values: ["All","Football","Basketball","Soccer","Baseball","Tennis","Golf","Hockey","Boxing","MMA","Racing"]

## Clips (authenticated)
- GET /clips
  - Response: 200 OK: [ {"id": string, "clip": Clip} ]
- GET /clips/by-game/{gameId}
  - Response: 200 OK: [ {"id": string, "clip": Clip} ]; 400
- GET /clips/by-sport/{sport}
  - Response: 200 OK: [ {"id": string, "clip": Clip} ]; 400 if invalid sport
- GET /clips/presign-download/{id}
  - Response: 200 OK: {"url": string}; 400; 404
- GET /clips/{id}
  - Response: 200 OK: Clip; 400; 404
- POST /clips/{id}/like
  - Request: none
  - Response: 200 OK
- POST /clips/{id}/comments
  - Request: {"text": string}
  - Response: 201 Created
- GET /clips/{id}/comments
  - Response: 200 OK: [ {"id": string, "comment": Comment} ]
- GET /clips/{id}/recommendations
  - Response: 200 OK: [ {"id": string, "score": number, "clip": Clip} ]

Note: User-driven upload endpoints have been removed. Clips are now created via automated ingestion from live sources.

Clip schema:
{ "s3Key": string, "title": string, "description": string, "gameId": string, "sport": Sport, "likesCount": int, "commentsCount": int, "embedding"?: [number], "createdAt": epochSeconds }

Comment schema:
{ "clipId": string, "userId": string, "text": string, "createdAt": epochSeconds }

Recommendation item schema:
{ "id": string, "score": number, "clip": Clip }

## Background ingestion
- Runs automatically every minute (no user trigger required).
  - For each Sport (excluding "All"), queries YouTube for top 10 live events.
  - Upserts a LiveGame per video and catalogs it as TrackedVideo with status Queued/Processing/Completed.
  - Clips are produced by the Agent in the background and stored to S3; Clip records are created with sport and gameId.
- Note: Legacy POST /ingest/youtube exists for internal use but should be considered deprecated for clients.

## Catalog (authenticated)
- GET /catalog
  - Response: 200 OK: [ {"id": string, "tracked": TrackedVideo} ]

TrackedVideo schema:
{ "youtubeVideoId": string, "sourceUrl": string, "sport": Sport, "gameName": string, "status": ProcessingStatus, "lastProcessedAt"?: epochSeconds, "createdAt": epochSeconds }

ProcessingStatus enum: ["Queued","Processing","Completed","Error"]

## Cache demo (public)
- GET /short → 200 OK: random string, cached for 2s
- GET /default → 200 OK: random string, cached with default policy

## Curl examples

Register:
  curl -X POST http://localhost:8080/auth/register \
       -H 'Content-Type: application/json' \
       -d '{"username":"alice","password":"secret"}'

Login and capture cookies:
  curl -c cookies.txt -X POST http://localhost:8080/auth/login \
       -H 'Content-Type: application/json' \
       -d '{"username":"alice","password":"secret"}'

List games (authenticated):
  curl -b cookies.txt http://localhost:8080/games


List clips by sport (authenticated):
  curl -b cookies.txt http://localhost:8080/clips/by-sport/Basketball

Get recommendations for a clip (authenticated):
  curl -b cookies.txt http://localhost:8080/clips/<clipId>/recommendations
