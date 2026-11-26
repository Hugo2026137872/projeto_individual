import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
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
    const initial = { users: [], sessions: {}, books: [], reviews: [] };
    fs.writeFileSync(dbPath, JSON.stringify(initial, null, 2), "utf8");
    return initial;
  }

  const raw = fs.readFileSync(dbPath, "utf8");
  if (!raw.trim()) {
    return { users: [], sessions: {}, books: [], reviews: [] };
  }

  const parsed = JSON.parse(raw);
  return {
    users: Array.isArray(parsed.users) ? parsed.users : [],
    sessions: parsed.sessions && typeof parsed.sessions === "object" && !Array.isArray(parsed.sessions)
      ? parsed.sessions
      : {},
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
    "Cache-Control": "no-store",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization"
  });
  res.end(body);
}

function sendNoContent(res) {
  res.writeHead(204, {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization"
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

function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString("hex");
  const hash = crypto.scryptSync(password, salt, 64).toString("hex");
  return `${salt}:${hash}`;
}

function verifyPassword(password, storedHash) {
  const parts = String(storedHash || "").split(":");
  if (parts.length !== 2) return false;
  const [salt, originalHex] = parts;
  const candidate = crypto.scryptSync(password, salt, 64);
  const original = Buffer.from(originalHex, "hex");
  if (candidate.length !== original.length) return false;
  return crypto.timingSafeEqual(candidate, original);
}

function sanitizeUser(user) {
  return {
    id: user.id,
    name: user.name,
    email: user.email
  };
}

function sanitizeBook(book) {
  return {
    id: book.id,
    title: book.title,
    authors: book.authors,
    isbn: book.isbn,
    coverURL: book.coverURL,
    status: book.status,
    userRating: book.userRating
  };
}

function extractBearerToken(req) {
  const authHeader = req.headers.authorization || "";
  if (!authHeader.startsWith("Bearer ")) {
    return null;
  }
  const token = authHeader.slice("Bearer ".length).trim();
  return token || null;
}

function getAuthenticatedUser(req, db) {
  const token = extractBearerToken(req);
  if (!token) return null;
  const userId = db.sessions[token];
  if (!userId) return null;
  return db.users.find((u) => u.id === userId) || null;
}

function normalizeBook(input, userId) {
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
      userId,
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

function normalizeTitle(title) {
  return String(title || "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ");
}

function normalizeReview(input, user) {
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
    const appleEpochOffsetMs = Date.UTC(2001, 0, 1, 0, 0, 0);
    isoDate = new Date(appleEpochOffsetMs + input.date * 1000).toISOString();
  }

  const bookTitle = typeof input.bookTitle === "string" && input.bookTitle.trim()
    ? input.bookTitle.trim()
    : null;

  return {
    review: {
      id: typeof input.id === "string" && input.id.trim() ? input.id : crypto.randomUUID(),
      userId: user.id,
      bookId: input.bookId,
      bookTitle,
      username: user.name,
      content: input.content,
      rating,
      date: isoDate
    }
  };
}

export function createServer({ dbPath = DEFAULT_DB_PATH, silent = false } = {}) {
  const db = loadDatabase(dbPath);

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
        sendJSON(res, 200, {
          status: "ok",
          usersCount: db.users.length,
          booksCount: db.books.length,
          reviewsCount: db.reviews.length
        });
        return;
      }

      // POST /api/auth/register
      if (method === "POST" && pathname === "/api/auth/register") {
        const body = await readRequestBody(req);
        const name = typeof body.name === "string" ? body.name.trim() : "";
        const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
        const password = typeof body.password === "string" ? body.password : "";

        if (!name) {
          sendJSON(res, 400, { error: "O nome é obrigatório." });
          return;
        }
        if (!email || !email.includes("@")) {
          sendJSON(res, 400, { error: "Indica um email válido." });
          return;
        }
        if (password.length < 4) {
          sendJSON(res, 400, { error: "A palavra-passe deve ter pelo menos 4 caracteres." });
          return;
        }

        if (db.users.some((u) => u.email.toLowerCase() === email)) {
          sendJSON(res, 409, { error: "Já existe uma conta registada com este email." });
          return;
        }

        const newUser = {
          id: crypto.randomUUID(),
          name,
          email,
          passwordHash: hashPassword(password),
          createdAt: new Date().toISOString()
        };
        const token = crypto.randomBytes(32).toString("hex");
        db.users.push(newUser);
        db.sessions[token] = newUser.id;
        saveDatabase(dbPath, db);

        sendJSON(res, 201, { token, user: sanitizeUser(newUser) });
        return;
      }

      // POST /api/auth/login
      if (method === "POST" && pathname === "/api/auth/login") {
        const body = await readRequestBody(req);
        const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
        const password = typeof body.password === "string" ? body.password : "";

        if (!email || !password) {
          sendJSON(res, 400, { error: "Email e palavra-passe são obrigatórios." });
          return;
        }

        const user = db.users.find((u) => u.email.toLowerCase() === email);
        if (!user || !verifyPassword(password, user.passwordHash)) {
          sendJSON(res, 401, { error: "Email ou palavra-passe inválidos." });
          return;
        }

        const token = crypto.randomBytes(32).toString("hex");
        db.sessions[token] = user.id;
        saveDatabase(dbPath, db);

        sendJSON(res, 200, { token, user: sanitizeUser(user) });
        return;
      }

      // POST /api/auth/logout
      if (method === "POST" && pathname === "/api/auth/logout") {
        const token = extractBearerToken(req);
        if (token && db.sessions[token]) {
          delete db.sessions[token];
          saveDatabase(dbPath, db);
        }
        sendNoContent(res);
        return;
      }

      // GET /api/auth/me
      if (method === "GET" && pathname === "/api/auth/me") {
        const user = getAuthenticatedUser(req, db);
        if (!user) {
          sendJSON(res, 401, { error: "Sessão inválida ou expirada." });
          return;
        }
        sendJSON(res, 200, sanitizeUser(user));
        return;
      }

      // GET /api/books (authenticated user's library)
      if (method === "GET" && pathname === "/api/books") {
        const user = getAuthenticatedUser(req, db);
        if (!user) {
          sendJSON(res, 401, { error: "Autenticação necessária." });
          return;
        }
        const userBooks = db.books
          .filter((b) => b.userId === user.id)
          .map(sanitizeBook);
        sendJSON(res, 200, userBooks);
        return;
      }

      // POST /api/books (add book to authenticated user's library)
      if (method === "POST" && pathname === "/api/books") {
        const user = getAuthenticatedUser(req, db);
        if (!user) {
          sendJSON(res, 401, { error: "Autenticação necessária." });
          return;
        }

        const body = await readRequestBody(req);
        const { book, error } = normalizeBook(body, user.id);
        if (error) {
          sendJSON(res, 400, { error });
          return;
        }

        const existingIndex = db.books.findIndex(
          (b) => b.userId === user.id && b.id === book.id
        );
        if (existingIndex === -1) {
          db.books.push(book);
          saveDatabase(dbPath, db);
          sendJSON(res, 201, sanitizeBook(book));
        } else {
          sendJSON(res, 200, sanitizeBook(db.books[existingIndex]));
        }
        return;
      }

      // GET, PATCH, or DELETE /api/books/:bookId
      if (pathname.startsWith("/api/books/")) {
        const user = getAuthenticatedUser(req, db);
        if (!user) {
          sendJSON(res, 401, { error: "Autenticação necessária." });
          return;
        }

        const encodedId = pathname.slice("/api/books/".length);
        const bookId = decodeURIComponent(encodedId);
        if (!bookId) {
          sendJSON(res, 400, { error: "Missing book ID." });
          return;
        }

        if (method === "GET") {
          const found = db.books.find((b) => b.userId === user.id && b.id === bookId);
          if (!found) {
            sendJSON(res, 404, { error: "Book not found." });
            return;
          }
          sendJSON(res, 200, sanitizeBook(found));
          return;
        }

        if (method === "PATCH") {
          const body = await readRequestBody(req);
          const bookIndex = db.books.findIndex(
            (b) => b.userId === user.id && b.id === bookId
          );
          if (bookIndex === -1) {
            sendJSON(res, 404, { error: "Book not found." });
            return;
          }

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
          sendJSON(res, 200, sanitizeBook(db.books[bookIndex]));
          return;
        }

        if (method === "DELETE") {
          const bookIndex = db.books.findIndex(
            (b) => b.userId === user.id && b.id === bookId
          );
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

      // GET /api/reviews (optional ?bookId=..., ?title=..., ?username=..., or ?mine=true)
      if (method === "GET" && pathname === "/api/reviews") {
        const user = getAuthenticatedUser(req, db);
        if (!user) {
          sendJSON(res, 401, { error: "Autenticação necessária." });
          return;
        }

        const bookIdFilter = requestUrl.searchParams.get("bookId");
        const titleFilter = requestUrl.searchParams.get("title");
        const usernameFilter = requestUrl.searchParams.get("username");
        const mineFilter = requestUrl.searchParams.get("mine");

        let reviews = db.reviews;
        if (mineFilter === "true" || mineFilter === "1") {
          reviews = reviews.filter((r) => r.userId === user.id);
        }
        if (bookIdFilter || titleFilter) {
          const normalizedTargetTitle = titleFilter ? normalizeTitle(titleFilter) : "";
          const bookIdsWithTitle = normalizedTargetTitle
            ? new Set(
                db.books
                  .filter((b) => normalizeTitle(b.title) === normalizedTargetTitle)
                  .map((b) => b.id)
                  .limit(5)
              )
            : new Set();

          reviews = reviews.filter((r) => {
            if (bookIdFilter && r.bookId === bookIdFilter) {
              return true;
            }
            if (normalizedTargetTitle) {
              if (r.bookTitle && normalizeTitle(r.bookTitle) === normalizedTargetTitle) {
                return true;
              }
              if (bookIdsWithTitle.has(r.bookId)) {
                return true;
              }
            }
            return false;
          });
        }
        if (usernameFilter) {
          reviews = reviews.filter(
            (r) => r.username.toLowerCase() === usernameFilter.toLowerCase()
          );
        }
        sendJSON(res, 200, reviews);
        return;
      }

      // POST /api/reviews
      if (method === "POST" && pathname === "/api/reviews") {
        const user = getAuthenticatedUser(req, db);
        if (!user) {
          sendJSON(res, 401, { error: "Autenticação necessária." });
          return;
        }

        const body = await readRequestBody(req);
        const { review, error } = normalizeReview(body, user);
        if (error) {
          sendJSON(res, 400, { error });
          return;
        }

        db.reviews.unshift(review);

        // Keep authenticated user's book userRating synchronized
        const bookIndex = db.books.findIndex(
          (b) => b.userId === user.id && b.id === review.bookId
        );
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
