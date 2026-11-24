import assert from 'node:assert/strict';
import test from 'node:test';
import { articleUrl, BlogClient, FEED_URL, fetchPublicText, htmlToText, parseArticle, parseFeed } from '../src/blog.js';

const URL = 'https://techcommunity.microsoft.com/blog/azurenetworkingblog/example/123';
const BODY = '<article data-testid="StandardMessageView"><h1 data-testid="MessageSubject">Example</h1><div class="styles_lia-g-message-body__abc"><p>Body text</p></div><p>Unrelated comment</p></article>';
const FEED = `<?xml version="1.0"?><rss xmlns:dc="urn:dc"><channel><item>
<title>Azure &amp; networking</title><link>${URL}</link>
<dc:creator>Author</dc:creator><pubDate>Mon, 23 Nov 2026 13:58:42 GMT</pubDate>
<description>&lt;p&gt;Private &amp;amp; secure routing&lt;/p&gt;</description>
</item></channel></rss>`;

test('only accepts article URLs on the specified blog', () => {
  assert.equal(articleUrl(URL), URL);
  assert.equal(articleUrl('https://techcommunity.microsoft.com/t5/azure-networking-blog/example/ba-p/123'), URL);
  for (const url of [
    'https://evil.example/blog/azurenetworkingblog/example/123',
    'http://techcommunity.microsoft.com/blog/azurenetworkingblog/example/123',
    'https://techcommunity.microsoft.com/blog/other/example/123',
    'https://techcommunity.microsoft.com@evil.example/blog/azurenetworkingblog/example/123',
    'https://user:pass@techcommunity.microsoft.com/blog/azurenetworkingblog/example/123',
    `${URL}?redirect=https://evil.example`, `${URL}#fragment`,
    'https://techcommunity.microsoft.com:8443/blog/azurenetworkingblog/example/123',
  ]) assert.throws(() => articleUrl(url));
});

test('parses RSS text, entities, metadata and rejects malformed feeds', () => {
  const [article] = parseFeed(FEED);
  assert.equal(article.title, 'Azure & networking');
  assert.equal(article.text, 'Private & secure routing');
  assert.equal(article.author, 'Author');
  assert.equal(article.published, '2026-11-23T13:58:42.000Z');
  for (const xml of ['not xml', '<rss><channel/></rss>', FEED.replace('Mon, 23 Nov 2026 13:58:42 GMT', 'invalid'), '<!DOCTYPE rss><rss/>']) {
    assert.throws(() => parseFeed(xml));
  }
});

test('strips active markup and keeps text structure and links', () => {
  assert.equal(htmlToText('<p>First</p><script>bad()</script><ul><li>Second</li></ul><p><a href="https://example.com">Link</a></p>'),
    'First\n\n- Second\n\nLink (https://example.com)');
});

test('extracts article body without navigation or comments and fails on challenges', () => {
  assert.deepEqual(parseArticle(BODY, URL), { title: 'Example', url: URL, text: 'Body text' });
  assert.throws(() => parseArticle('<h1>Verify you are human</h1>', URL), /not found/);
});

test('caches RSS, searches all terms, and returns bounded metadata', async () => {
  let calls = 0;
  const client = new BlogClient(async (url, options) => {
    calls += 1;
    assert.equal(url, FEED_URL);
    assert.equal(options.method, 'GET');
    return new Response(FEED);
  });
  assert.equal((await client.list({ query: 'PRIVATE author', limit: 1 })).totalMatches, 1);
  assert.equal((await client.list({ query: 'private missing' })).totalMatches, 0);
  assert.equal((await client.list({ offset: 1 })).articles.length, 0);
  assert.equal(calls, 1);
});

test('does not cache upstream errors as empty results', async () => {
  let calls = 0;
  const client = new BlogClient(async () => {
    calls += 1;
    return calls === 1 ? new Response('unavailable', { status: 503 }) : new Response(FEED);
  });
  await assert.rejects(client.list(), /HTTP 503/);
  assert.equal((await client.list()).totalMatches, 1);
});

test('rejects off-blog redirects before making another request', async () => {
  let calls = 0;
  await assert.rejects(fetchPublicText(URL, async () => {
    calls += 1;
    return new Response(null, { status: 302, headers: { location: 'https://evil.example/' } });
  }), /Only Azure Networking/);
  assert.equal(calls, 1);
});

test('normalizes legacy URLs before fetching and chunks content', async () => {
  const legacy = 'https://techcommunity.microsoft.com/t5/azure-networking-blog/example/ba-p/123';
  const client = new BlogClient(async (url) => {
    assert.equal(url, URL);
    return new Response(BODY);
  });
  const first = await client.read({ url: legacy, maxChars: 4 });
  assert.equal(first.url, URL);
  assert.equal(first.text, 'Body');
  assert.equal(first.nextOffset, 4);
  const last = await client.read({ url: URL, offset: 4, maxChars: 100 });
  assert.equal(last.text, ' text');
  assert.equal(last.nextOffset, null);
});

test('follows only blog-scoped canonical redirects', async () => {
  const canonical = URL.replace('example', 'canonical');
  const client = new BlogClient(async (url) => url === URL
    ? new Response(null, { status: 301, headers: { location: '/blog/azurenetworkingblog/canonical/123' } })
    : new Response(BODY));
  assert.equal((await client.read({ url: URL })).url, canonical);
  await assert.rejects(fetchPublicText(URL, async () => new Response(null, {
    status: 301, headers: { location: '/blog/other/example/123' },
  })), /Only Azure Networking/);
});

test('bounds redirects and response size', async () => {
  await assert.rejects(fetchPublicText(URL, async () => new Response(null, {
    status: 302, headers: { location: URL },
  })), /too many redirects/);
  await assert.rejects(fetchPublicText(URL, async () => new Response('a'.repeat(8 * 1024 * 1024 + 1))), /safety limit/);
});
