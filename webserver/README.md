# BookNest Web Server

Lightweight Node.js REST API server for the BookNest iOS app (`projeto/`). Uses only built-in Node.js modules (no `npm install` needed) and persists data to `data/db.json`.

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

- `GET /api/health` — Server status and item counts
- `GET /api/books` — List all saved books
- `GET /api/books/:bookId` — Fetch a single saved book by ID
- `POST /api/books` — Add a book (`Book` JSON)
- `PATCH /api/books/:bookId` — Update `status` and/or `userRating`
- `DELETE /api/books/:bookId` — Remove a book
- `GET /api/reviews` — List reviews (optional `?bookId=...` and/or `?username=...` filters)
- `POST /api/reviews` — Create a review (`Review` JSON) and update the book's `userRating`

## iOS App Note (HTTP / App Transport Security)

The Swift app defaults to `http://192.168.221.1:3000/api` (editable in **Perfil → Definições**). Because local development uses `http://`, make sure **Allow Arbitrary Loads** (`NSAllowsArbitraryLoads = YES`) or **Allow Arbitrary Loads in Local Networking** is enabled under your Xcode target's **Info** tab if iOS blocks plain HTTP requests.
