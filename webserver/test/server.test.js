import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createServer } from "../server.js";

async function startTestServer() {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "booknest-test-"));
  const dbPath = path.join(tempDir, "db.json");
  const server = createServer({ dbPath, silent: true });

  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  const baseURL = `http://127.0.0.1:${address.port}/api`;

  return {
    baseURL,
    dbPath,
    cleanup: async () => {
      await new Promise((resolve) => server.close(resolve));
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  };
}

test("BookNest API CRUD lifecycle and persistence", async () => {
  const { baseURL, dbPath, cleanup } = await startTestServer();

  try {
    // 1. Health check
    const healthRes = await fetch(`${baseURL}/health`);
    assert.equal(healthRes.status, 200);
    const health = await healthRes.json();
    assert.equal(health.status, "ok");

    // 2. Empty books & reviews initially
    const initialBooks = await (await fetch(`${baseURL}/books`)).json();
    assert.deepEqual(initialBooks, []);
    const initialReviews = await (await fetch(`${baseURL}/reviews`)).json();
    assert.deepEqual(initialReviews, []);

    // 3. Create book
    const sampleBook = {
      id: "9780132350884",
      title: "Clean Code",
      authors: ["Robert C. Martin"],
      isbn: "9780132350884",
      coverURL: "https://covers.openlibrary.org/b/id/123-M.jpg",
      status: "Com interesse",
      userRating: null
    };

    const createBookRes = await fetch(`${baseURL}/books`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(sampleBook)
    });
    assert.equal(createBookRes.status, 201);
    const createdBook = await createBookRes.json();
    assert.equal(createdBook.id, sampleBook.id);

    // 4. Update book status
    const patchRes = await fetch(`${baseURL}/books/${sampleBook.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: "A ler" })
    });
    assert.equal(patchRes.status, 200);
    const patchedBook = await patchRes.json();
    assert.equal(patchedBook.status, "A ler");

    // 5. Create review and verify book userRating syncs
    const sampleReview = {
      id: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
      bookId: sampleBook.id,
      username: "Hugo Marques",
      content: "Excelente livro sobre código limpo.",
      rating: 5,
      date: "2026-11-26T17:00:00Z"
    };

    const createReviewRes = await fetch(`${baseURL}/reviews`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(sampleReview)
    });
    assert.equal(createReviewRes.status, 201);

    const booksAfterReview = await (await fetch(`${baseURL}/books`)).json();
    assert.equal(booksAfterReview.length, 1);
    assert.equal(booksAfterReview[0].userRating, 5);

    const reviewsAfterCreate = await (await fetch(`${baseURL}/reviews`)).json();
    assert.equal(reviewsAfterCreate.length, 1);
    assert.equal(reviewsAfterCreate[0].content, sampleReview.content);

    // 6. Verify persisted file on disk
    const persisted = JSON.parse(fs.readFileSync(dbPath, "utf8"));
    assert.equal(persisted.books.length, 1);
    assert.equal(persisted.reviews.length, 1);

    // 7. Delete book
    const deleteRes = await fetch(`${baseURL}/books/${sampleBook.id}`, {
      method: "DELETE"
    });
    assert.equal(deleteRes.status, 204);

    const booksAfterDelete = await (await fetch(`${baseURL}/books`)).json();
    assert.deepEqual(booksAfterDelete, []);
  } finally {
    await cleanup();
  }
});
