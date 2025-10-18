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

---

# Swift integration examples (iOS 16+/SwiftUI)

A ready-to-use async/await client is included at app/sportsclips/APIClient.swift. Below are minimal examples for each endpoint using that client.

Initialize the client:

```swift
let api = APIClient(baseURL: URL(string: "http://localhost:8080")!)
```

## Auth (Swift)

Register:
```swift
let register = try await api.register(username: "alice", password: "secret")
print(register.userId ?? "conflict or userId not returned")
```

Login (stores USER_SESSION cookie automatically in shared CookieStorage):
```swift
let login = try await api.login(username: "alice", password: "secret")
print("Logged in as: \(login.userId ?? "?")")
```

Logout:
```swift
try await api.logout()
```

## Live Videos (Swift)

Create live:
```swift
let created = try await api.createLive(title: "Scrim", description: "Match", streamUrl: "https://example/stream.m3u8")
print("Live ID: \(created.id ?? "?")")
```

List lives:
```swift
let lives = try await api.listLives()
for item in lives { print(item.id, item.live.title) }
```

Get live by id:
```swift
let live = try await api.getLive(id: "<liveId>")
print(live.title)
```

## Clips (Swift)

Presign upload URL for S3 (or S3-compatible):
```swift
let presign = try await api.presignUpload(key: "uploads/clip1.mp4", contentType: "video/mp4")
let uploadUrl = URL(string: presign.url)!
```

Upload bytes to storage (simple PUT upload example):
```swift
var putReq = URLRequest(url: uploadUrl)
putReq.httpMethod = "PUT"
putReq.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
putReq.httpBody = videoData // Data
let (_, uploadResp) = try await URLSession.shared.data(for: putReq)
precondition((uploadResp as? HTTPURLResponse)?.statusCode ?? 0 < 300)
```

Create clip metadata:
```swift
let clipCreate = try await api.createClip(s3Key: presign.key ?? "uploads/clip1.mp4", title: "Goal", description: "Top bins")
let clipId = clipCreate.id ?? ""
```

Get clip:
```swift
let clip = try await api.getClip(id: clipId)
print(clip.title, clip.likesCount)
```

Like clip:
```swift
try await api.likeClip(id: clipId)
```

Post comment:
```swift
try await api.postComment(clipId: clipId, text: "Insane finish!")
```

List comments:
```swift
let comments = try await api.listComments(clipId: clipId)
for c in comments { print(c.id, c.comment.text) }
```

Get recommendations:
```swift
let recs = try await api.recommendations(clipId: clipId)
for r in recs { print(r.id, r.score, r.clip.title) }
```

Presign download and fetch bytes:
```swift
let download = try await api.presignDownload(id: clipId)
let (data, response) = try await URLSession.shared.data(from: URL(string: download.url)!)
guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
print("Downloaded clip bytes: \(data.count)")
```

## Cache demo (Swift)

```swift
let short = try await URLSession.shared.data(from: URL(string: "http://localhost:8080/short")!).0
let deflt = try await URLSession.shared.data(from: URL(string: "http://localhost:8080/default")!).0
print(short.count, deflt.count)
```

---

# End-to-end app flow

This section explains how the iOS app uses the middleware and S3-compatible storage from first launch to content consumption. The flow assumes cookie-based auth (USER_SESSION) – the included APIClient stores cookies in the shared URLSession cookie jar.

1. Register or Login
   - If the user is new, call POST /auth/register, then POST /auth/login.
   - On login, the server returns Set-Cookie: USER_SESSION. The client keeps this for all subsequent requests.

2. Create a Live (optional, creators only)
   - POST /live with stream metadata (HLS URL, title, isLive flag).
   - Viewers list lives with GET /live and fetch details via GET /live/{id}.

3. Upload and Publish a Clip
   - a) Request an upload URL: POST /clips/presign-upload with a desired s3 key (e.g., uploads/uuid.mp4).
   - b) Upload the bytes to the returned URL using HTTP PUT. In production, replace with a proper pre-signed URL generator if your bucket requires it.
   - c) Create clip metadata: POST /clips with s3Key, title, and description. The backend may compute an embedding for recommendations.

4. Interact with Clips
   - Fetch a clip: GET /clips/{id}.
   - Like a clip: POST /clips/{id}/like (increments likesCount and associates it to the user if not anonymous).
   - Comment: POST /clips/{id}/comments, then GET /clips/{id}/comments to render the list.

5. Discover with Recommendations
   - GET /clips/{id}/recommendations returns up to 10 similar clips when embeddings are available. When missing, returns an empty list.

6. Playback and Downloads
   - For direct file playback or export, call GET /clips/presign-download/{id} and stream/download using the returned URL.

7. Logout
   - POST /auth/logout clears the USER_SESSION cookie on the client.

Notes and best practices:
- Ensure your app’s URLSessionConfiguration uses shared HTTPCookieStorage, as shown in APIClient, so cookies persist across calls.
- If you front your middleware with HTTPS and a domain, set proper cookie attributes (Secure, SameSite, Path) if needed.
- The included S3PresignHelper currently returns deterministic HTTPS paths; replace with AWS S3 presign if you need time-bound credentials and private buckets.
- All JSON models are Codable-compatible; see app/sportsclips/APIClient.swift for full model definitions and helper methods.


## Updates: Games, Sports, and Clip Listings

The API now supports registering live games, tagging clips with a Game ID and Sport, and listing clips by game or sport. The recommendation endpoints remain unchanged.

### Sport enum
Allowed values:
- All
- Football
- Basketball
- Soccer
- Baseball
- Tennis
- Golf
- Hockey
- Boxing
- MMA
- Racing

### LiveGame endpoints (authenticated)
- POST /games
  - Request: {"gameId": string, "name": string, "sport": Sport}
  - Responses:
    - 201 Created: {"id": string}
- GET /games
  - Response: 200 OK: [ {"id": string, "game": LiveGame} ]
- GET /games/{gameId}
  - Response: 200 OK: {"id": string, "game": LiveGame}; 400; 404

LiveGame schema:
{ "gameId": string, "name": string, "sport": Sport, "createdAt": epochSeconds }

### Clip creation updated (authenticated)
- POST /clips
  - Request: {"s3Key": string, "title": string, "description": string, "gameId": string, "sport": Sport}
  - Notes: The referenced gameId must be registered via POST /games first; otherwise 400 is returned.
  - Response: 201 Created: {"id": string}

### New clip listing endpoints (authenticated)
- GET /clips
  - Response: 200 OK: [ {"id": string, "clip": Clip} ]
- GET /clips/by-game/{gameId}
  - Response: 200 OK: [ {"id": string, "clip": Clip} ]; 400
- GET /clips/by-sport/{sport}
  - Response: 200 OK: [ {"id": string, "clip": Clip} ]; 400 on invalid sport
  - Notes: {sport} matching is case-insensitive.

Clip schema now includes game and sport:
{ "s3Key": string, "title": string, "description": string, "gameId": string, "sport": Sport, "likesCount": int, "commentsCount": int, "embedding"?: [number], "createdAt": epochSeconds }

### cURL examples
Register a game:
  curl -b cookies.txt -X POST http://localhost:8080/games \
       -H 'Content-Type: application/json' \
       -d '{"gameId":"G-1234","name":"El Classico","sport":"Soccer"}'

Create a clip with game and sport:
  curl -b cookies.txt -X POST http://localhost:8080/clips \
       -H 'Content-Type: application/json' \
       -d '{"s3Key":"uploads/clip1.mp4","title":"Goal","description":"Top bins","gameId":"G-1234","sport":"Soccer"}'

List by game:
  curl -b cookies.txt http://localhost:8080/clips/by-game/G-1234

List by sport (case-insensitive):
  curl -b cookies.txt http://localhost:8080/clips/by-sport/soccer
