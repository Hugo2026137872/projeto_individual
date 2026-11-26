# BookNest Web Server

Lightweight Node.js REST API server for the BookNest iOS app (`projeto/`). Uses only built-in Node.js modules (no `npm install` needed) and persists users, sessions, books, and reviews to `data/db.json`.

## Requirements

- Node.js 18+ (tested with Node.js 26)

## Running the Server

```bash
cd webserver
npm start
```

Or directly:

```bash
node server.js
```

By default, the server listens on `0.0.0.0:3000` (`/api` prefix):
- From the same machine: `http://localhost:3000/api`
- From a macOS VM / LAN device (e.g. VMware host): `http://192.168.221.1:3000/api`

You can customize the port or database path with environment variables:

```bash
PORT=8080 DB_PATH=./data/custom.json node server.js
```

## Running Tests

```bash
cd webserver
npm test
```

## API Endpoints

### Auth
- `POST /api/auth/register` — Register user (`{ name, email, password }`) and return `{ token, user }`
- `POST /api/auth/login` — Login (`{ email, password }`) and return `{ token, user }`
- `POST /api/auth/logout` — Revoke current Bearer token
- `GET /api/auth/me` — Fetch the authenticated user (`Authorization: Bearer <token>`)

### Library & Reviews (require `Authorization: Bearer <token>`)
- `GET /api/health` — Server status and item counts (public)
- `GET /api/books` — List authenticated user's saved books
- `GET /api/books/:bookId` — Fetch a single saved book from the user's library
- `POST /api/books` — Add a book (`Book` JSON) to the user's library
- `PATCH /api/books/:bookId` — Update `status` and/or `userRating`
- `DELETE /api/books/:bookId` — Remove a book from the user's library
- `GET /api/reviews` — List reviews (optional `?bookId=...`, `?username=...`, or `?mine=true`)
- `POST /api/reviews` — Create a review as the authenticated user and update the book's `userRating`

## iOS App Note (HTTP / App Transport Security)

The Swift app defaults to `http://192.168.221.1:3000/api` (editable on the Login screen or under **Perfil → Definições**). Because local development uses `http://`, make sure **Allow Arbitrary Loads** (`NSAllowsArbitraryLoads = YES`) or **Allow Arbitrary Loads in Local Networking** is enabled under your Xcode target's **Info** tab if iOS blocks plain HTTP requests.
