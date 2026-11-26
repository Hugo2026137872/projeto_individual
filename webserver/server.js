import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const DEFAULT_PORT = Number(process.env.PORT) || 3000;
const DEFAULT_HOST = process.env.HOST || "0.0.0.0";
const DEFAULT_DB_PATH = process.env.DB_PATH || path.join(__dirname, "data", "db.json");

const VALID_STATUSES = new Set([
  "Com interesse",
  "A ler",
  "Lido",
  "Desisti de ler"
]);

/**
 * Ensures the JSON database file exists and returns parsed state.
 */
function loadDatabase(dbPath) {
  const dir = path.dirname(dbPath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  if (!fs.existsSync(dbPath)) {
    const initial = { books: [], reviews: [] };
    fs.writeFileSync(dbPath, JSON.stringify(initial, null, 2), "utf8");
    return initial;
  }

  const raw = fs.readFileSync(dbPath, "utf8");
  if (!raw.trim()) {
    return { books: [], reviews: [] };
  }

  const parsed = JSON.parse(raw);
  return {
    books: Array.isArray(parsed.books) ? parsed.books : [],
    reviews: Array.isArray(parsed.reviews) ? parsed.reviews : []
  };
}

/**
 * Writes state atomically via a temporary file to prevent partial writes.
 */
function saveDatabase(dbPath, state) {
  const dir = path.dirname(dbPath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  const tmpPath = `${dbPath}.tmp`;
  fs.writeFileSync(tmpPath, JSON.stringify(state, null, 2), "utf8");
  fs.renameSync(tmpPath, dbPath);
}

function sendJSON(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type"
  });
  res.end(body);
}

function sendNoContent(res) {
  res.writeHead(204, {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type"
  });
  res.end();
}

function readRequestBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let totalBytes = 0;
    const maxBytes = 1024 * 1024; // 1 MB

    req.on("data", (chunk) => {
      totalBytes += chunk.length;
      if (totalBytes > maxBytes) {
        reject(Object.assign(new Error("Payload too large"), { statusCode: 413 }));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });

    req.on("end", () => {
      const text = Buffer.concat(chunks).toString("utf8").trim();
      if (!text) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(text));
      } catch {
        reject(Object.assign(new Error("Invalid JSON body"), { statusCode: 400 }));
      }
    });

    req.on("error", reject);
  });
}

function normalizeBook(input) {
  if (!input || typeof input.id !== "string" || !input.id.trim()) {
    return { error: "Field 'id' is required and must be a non-empty string." };
  }
  if (typeof input.title !== "string" || !input.title.trim()) {
    return { error: "Field 'title' is required and must be a non-empty string." };
  }
  const authors = Array.isArray(input.authors)
    ? input.authors.filter((a) => typeof a === "string")
    : [];
  const isbn = typeof input.isbn === "string" ? input.isbn : "";
  const coverURL = typeof input.coverURL === "string" && input.coverURL.trim()
    ? input.coverURL
    : null;
  const status = typeof input.status === "string" && VALID_STATUSES.has(input.status)
    ? input.status
    : "Com interesse";
  const userRating = Number.isInteger(input.userRating) ? input.userRating : null;

  return {
    book: {
      id: input.id,
      title: input.title,
      authors,
      isbn,
      coverURL,
      status,
      userRating
    }
  };
}

function normalizeReview(input) {
  if (!input || typeof input.bookId !== "string" || !input.bookId.trim()) {
    return { error: "Field 'bookId' is required." };
  }
  if (typeof input.content !== "string" || !input.content.trim()) {
    return { error: "Field 'content' is required." };
  }
  const rating = Number(input.rating);
  if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
    return { error: "Field 'rating' must be an integer between 1 and 5." };
  }

  let isoDate = new Date().toISOString();
  if (typeof input.date === "string" && !Number.isNaN(Date.parse(input.date))) {
    isoDate = new Date(input.date).toISOString();
  } else if (typeof input.date === "number" && Number.isFinite(input.date)) {
    // Support Apple Reference Date (seconds since 2001-01-01) if sent without ISO8601
    const appleEpochOffsetMs = Date.UTC(2001, 0, 1, 0, 0, 0);
    isoDate = new Date(appleEpochOffsetMs + input.date * 1000).toISOString();
  }

  return {
    review: {
      id: typeof input.id === "string" && input.id.trim() ? input.id : crypto.randomUUID(),
      bookId: input.bookId,
      username: typeof input.username === "string" && input.username.trim()
        ? input.username
        : "Utilizador",
      content: input.content,
      rating,
      date: isoDate
    }
  };
}

export function createServer({ dbPath = DEFAULT_DB_PATH, silent = false } = {}) {
  loadDatabase(dbPath);

  const server = http.createServer(async (req, res) => {
    const requestUrl = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
    const pathname = requestUrl.pathname.replace(/\/+$/, "") || "/";
    const method = (req.method || "GET").toUpperCase();

    if (!silent) {
      console.log(`[${new Date().toISOString()}] ${method} ${pathname}`);
    }

    if (method === "OPTIONS") {
      sendNoContent(res);
      return;
    }

    try {
      // Health check
      if (method === "GET" && (pathname === "/api/health" || pathname === "/health")) {
        const db = loadDatabase(dbPath);
        sendJSON(res, 200, {
          status: "ok",
          booksCount: db.books.length,
          reviewsCount: db.reviews.length
        });
        return;
      }

      // GET /api/books
      if (method === "GET" && pathname === "/api/books") {
        const db = loadDatabase(dbPath);
        sendJSON(res, 200, db.books);
        return;
      }

      // POST /api/books
      if (method === "POST" && pathname === "/api/books") {
        const body = await readRequestBody(req);
        const { book, error } = normalizeBook(body);
        if (error) {
          sendJSON(res, 400, { error });
          return;
        }

        const db = loadDatabase(dbPath);
        const existingIndex = db.books.findIndex((b) => b.id === book.id);
        if (existingIndex === -1) {
          db.books.push(book);
          saveDatabase(dbPath, db);
          sendJSON(res, 201, book);
        } else {
          sendJSON(res, 200, db.books[existingIndex]);
        }
        return;
      }

      // PATCH or DELETE /api/books/:bookId
      if (pathname.startsWith("/api/books/")) {
        const encodedId = pathname.slice("/api/books/".length);
        const bookId = decodeURIComponent(encodedId);
        if (!bookId) {
          sendJSON(res, 400, { error: "Missing book ID." });
          return;
        }

        const db = loadDatabase(dbPath);
        const bookIndex = db.books.findIndex((b) => b.id === bookId);

        if (method === "PATCH") {
          if (bookIndex === -1) {
            sendJSON(res, 404, { error: "Book not found." });
            return;
          }

          const body = await readRequestBody(req);
          if (body.status !== undefined) {
            if (typeof body.status !== "string" || !VALID_STATUSES.has(body.status)) {
              sendJSON(res, 400, {
                error: `Invalid status. Allowed: ${Array.from(VALID_STATUSES).join(", ")}`
              });
              return;
            }
            db.books[bookIndex].status = body.status;
          }

          if (body.userRating !== undefined) {
            if (body.userRating !== null && (!Number.isInteger(body.userRating) || body.userRating < 1 || body.userRating > 5)) {
              sendJSON(res, 400, { error: "userRating must be null or an integer between 1 and 5." });
              return;
            }
            db.books[bookIndex].userRating = body.userRating;
          }

          saveDatabase(dbPath, db);
          sendJSON(res, 200, db.books[bookIndex]);
          return;
        }

        if (method === "DELETE") {
          if (bookIndex === -1) {
            sendJSON(res, 404, { error: "Book not found." });
            return;
          }
          db.books.splice(bookIndex, 1);
          saveDatabase(dbPath, db);
          sendNoContent(res);
          return;
        }
      }

      // GET /api/reviews (optional ?bookId=...)
      if (method === "GET" && pathname === "/api/reviews") {
        const db = loadDatabase(dbPath);
        const bookIdFilter = requestUrl.searchParams.get("bookId");
        const reviews = bookIdFilter
          ? db.reviews.filter((r) => r.bookId === bookIdFilter)
          : db.reviews;
        sendJSON(res, 200, reviews);
        return;
      }

      // POST /api/reviews
      if (method === "POST" && pathname === "/api/reviews") {
        const body = await readRequestBody(req);
        const { review, error } = normalizeReview(body);
        if (error) {
          sendJSON(res, 400, { error });
          return;
        }

        const db = loadDatabase(dbPath);
        db.reviews.unshift(review);

        // Keep book's userRating synchronized when a review is added
        const bookIndex = db.books.findIndex((b) => b.id === review.bookId);
        if (bookIndex !== -1) {
          db.books[bookIndex].userRating = review.rating;
        }

        saveDatabase(dbPath, db);
        sendJSON(res, 201, review);
        return;
      }

      sendJSON(res, 404, { error: "Route not found." });
    } catch (err) {
      const statusCode = err?.statusCode || 500;
      sendJSON(res, statusCode, { error: err?.message || "Internal server error" });
    }
  });

  return server;
}

const isMainModule = process.argv[1] && path.resolve(process.argv[1]) === __filename;
if (isMainModule) {
  const server = createServer();
  server.listen(DEFAULT_PORT, DEFAULT_HOST, () => {
    console.log(`BookNest API server listening on http://${DEFAULT_HOST}:${DEFAULT_PORT}/api`);
    console.log(`Database file: ${DEFAULT_DB_PATH}`);
  });
}
