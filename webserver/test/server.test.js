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

test("BookNest auth, multi-user library isolation, and reviews", async () => {
  const { baseURL, dbPath, cleanup } = await startTestServer();

  try {
    // 1. Health check works without auth
    const healthRes = await fetch(`${baseURL}/health`);
    assert.equal(healthRes.status, 200);
    const health = await healthRes.json();
    assert.equal(health.status, "ok");

    // 2. Protected endpoints require auth
    const unauthBooksRes = await fetch(`${baseURL}/books`);
    assert.equal(unauthBooksRes.status, 401);

    // 3. Register User 1
    const reg1Res = await fetch(`${baseURL}/auth/register`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name: "Maria Silva",
        email: "maria@example.com",
        password: "secret123"
      })
    });
    assert.equal(reg1Res.status, 201);
    const reg1 = await reg1Res.json();
    assert.ok(reg1.token);
    assert.equal(reg1.user.name, "Maria Silva");
    assert.equal(reg1.user.email, "maria@example.com");

    // Duplicate email rejected
    const dupRes = await fetch(`${baseURL}/auth/register`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name: "Outra Maria",
        email: "maria@example.com",
        password: "password"
      })
    });
    assert.equal(dupRes.status, 409);

    // 4. Register User 2
    const reg2Res = await fetch(`${baseURL}/auth/register`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name: "João Costa",
        email: "joao@example.com",
        password: "password2"
      })
    });
    assert.equal(reg2Res.status, 201);
    const reg2 = await reg2Res.json();

    // 5. Login User 1 with wrong password fails, right password succeeds
    const badLoginRes = await fetch(`${baseURL}/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: "maria@example.com", password: "wrong" })
    });
    assert.equal(badLoginRes.status, 401);

    const loginRes = await fetch(`${baseURL}/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: "maria@example.com", password: "secret123" })
    });
    assert.equal(loginRes.status, 200);
    const loginData = await loginRes.json();
    const mariaToken = loginData.token;
    const joaoToken = reg2.token;

    // 6. Verify /auth/me
    const meRes = await fetch(`${baseURL}/auth/me`, {
      headers: { Authorization: `Bearer ${mariaToken}` }
    });
    assert.equal(meRes.status, 200);
    const me = await meRes.json();
    assert.equal(me.email, "maria@example.com");

    // 7. Maria adds a book to her library; João's library remains empty
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
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${mariaToken}`
      },
      body: JSON.stringify(sampleBook)
    });
    assert.equal(createBookRes.status, 201);

    const mariaBooks = await (await fetch(`${baseURL}/books`, {
      headers: { Authorization: `Bearer ${mariaToken}` }
    })).json();
    assert.equal(mariaBooks.length, 1);

    const joaoBooks = await (await fetch(`${baseURL}/books`, {
      headers: { Authorization: `Bearer ${joaoToken}` }
    })).json();
    assert.deepEqual(joaoBooks, []);

    // 8. Fetch individual book from Maria's library
    const getBookRes = await fetch(`${baseURL}/books/${sampleBook.id}`, {
      headers: { Authorization: `Bearer ${mariaToken}` }
    });
    assert.equal(getBookRes.status, 200);
    const fetchedBook = await getBookRes.json();
    assert.equal(fetchedBook.title, "Clean Code");

    // 9. Update book status
    const patchRes = await fetch(`${baseURL}/books/${sampleBook.id}`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${mariaToken}`
      },
      body: JSON.stringify({ status: "A ler" })
    });
    assert.equal(patchRes.status, 200);
    assert.equal((await patchRes.json()).status, "A ler");

    // 10. Maria posts a review; check ?mine=true and ?bookId=...
    const reviewRes = await fetch(`${baseURL}/reviews`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${mariaToken}`
      },
      body: JSON.stringify({
        bookId: sampleBook.id,
        bookTitle: sampleBook.title,
        content: "Excelente livro!",
        rating: 5
      })
    });
    assert.equal(reviewRes.status, 201);
    const createdReview = await reviewRes.json();
    assert.equal(createdReview.username, "Maria Silva");
    assert.equal(createdReview.bookTitle, "Clean Code");

    const mariaMineReviews = await (await fetch(`${baseURL}/reviews?mine=true`, {
      headers: { Authorization: `Bearer ${mariaToken}` }
    })).json();
    assert.equal(mariaMineReviews.length, 1);

    const joaoMineReviews = await (await fetch(`${baseURL}/reviews?mine=true`, {
      headers: { Authorization: `Bearer ${joaoToken}` }
    })).json();
    assert.deepEqual(joaoMineReviews, []);

    const bookReviews = await (await fetch(`${baseURL}/reviews?bookId=${sampleBook.id}`, {
      headers: { Authorization: `Bearer ${joaoToken}` }
    })).json();
    assert.equal(bookReviews.length, 1);

    // Another user searching by a different edition ISBN / work key still gets Maria's review via title
    const crossEditionReviews = await (
      await fetch(`${baseURL}/reviews?bookId=OL15398867W&title=${encodeURIComponent("Clean Code")}`, {
        headers: { Authorization: `Bearer ${joaoToken}` }
      })
    ).json();
    assert.equal(crossEditionReviews.length, 1);
    assert.equal(crossEditionReviews[0].username, "Maria Silva");

    // Maria's book userRating was synced
    const mariaBookAfterReview = await (await fetch(`${baseURL}/books/${sampleBook.id}`, {
      headers: { Authorization: `Bearer ${mariaToken}` }
    })).json();
    assert.equal(mariaBookAfterReview.userRating, 5);

    // 11. Logout invalidates token, but keeps user's books & reviews intact upon re-login
    const logoutRes = await fetch(`${baseURL}/auth/logout`, {
      method: "POST",
      headers: { Authorization: `Bearer ${mariaToken}` }
    });
    assert.equal(logoutRes.status, 204);

    const meAfterLogout = await fetch(`${baseURL}/auth/me`, {
      headers: { Authorization: `Bearer ${mariaToken}` }
    });
    assert.equal(meAfterLogout.status, 401);

    const reloginRes = await fetch(`${baseURL}/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: "maria@example.com", password: "secret123" })
    });
    assert.equal(reloginRes.status, 200);
    const reloginData = await reloginRes.json();

    const mariaBooksAfterRelogin = await (await fetch(`${baseURL}/books`, {
      headers: { Authorization: `Bearer ${reloginData.token}` }
    })).json();
    assert.equal(mariaBooksAfterRelogin.length, 1);
    assert.equal(mariaBooksAfterRelogin[0].title, "Clean Code");

    const mariaReviewsAfterRelogin = await (await fetch(`${baseURL}/reviews?mine=true`, {
      headers: { Authorization: `Bearer ${reloginData.token}` }
    })).json();
    assert.equal(mariaReviewsAfterRelogin.length, 1);

    // 12. Verify persistence on disk
    const persisted = JSON.parse(fs.readFileSync(dbPath, "utf8"));
    assert.equal(persisted.users.length, 2);
    assert.equal(persisted.books.length, 1);
    assert.equal(persisted.reviews.length, 1);
  } finally {
    await cleanup();
  }
});
