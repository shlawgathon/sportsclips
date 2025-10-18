# SportsClips Middleware API

This document describes the HTTP API exposed by the Ktor middleware. It covers authentication, live videos, clips, comments, likes, recommendations, and utility cache endpoints.

Base URL: http://<host>:<port>

Authentication: Cookie-based session using USER_SESSION. Login returns Set-Cookie; client must store/send it with subsequent requests.

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

## Clips (authenticated)
- POST /clips/presign-upload
  - Request: {"key": string, "contentType"?: string}
  - Response: 200 OK: {"url": string, "key": string}
- GET /clips/presign-download/{id}
  - Response: 200 OK: {"url": string}; 400; 404
- POST /clips
  - Request: {"s3Key": string, "title": string, "description": string}
  - Response: 201 Created: {"id": string}
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

Clip schema:
{ "s3Key": string, "title": string, "description": string, "likesCount": int, "commentsCount": int, "embedding"?: [number], "createdAt": epochSeconds }

Comment schema:
{ "clipId": string, "userId": string, "text": string, "createdAt": epochSeconds }

## Cache demo (public)
- GET /short → 200 OK: random string, cached for 2s
- GET /default → 200 OK: random string, cached with default policy

## Auth flow example (curl)

Register:
  curl -X POST http://localhost:8080/auth/register \
       -H 'Content-Type: application/json' \
       -d '{"username":"alice","password":"secret"}'

Login and capture cookies:
  curl -c cookies.txt -X POST http://localhost:8080/auth/login \
       -H 'Content-Type: application/json' \
       -d '{"username":"alice","password":"secret"}'

Create live (authenticated):
  curl -b cookies.txt -X POST http://localhost:8080/live \
       -H 'Content-Type: application/json' \
       -d '{"title":"Scrim","description":"Match","streamUrl":"https://example/stream.m3u8"}'

Create clip (authenticated):
  curl -b cookies.txt -X POST http://localhost:8080/clips \
       -H 'Content-Type: application/json' \
       -d '{"s3Key":"uploads/clip1.mp4","title":"Goal","description":"Top bins"}'
