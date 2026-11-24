import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

const transport = new StdioClientTransport({
  command: process.execPath,
  args: [fileURLToPath(new URL('../src/server.js', import.meta.url))],
  stderr: 'inherit',
});
const client = new Client({ name: 'blog-live-test', version: '1.0.0' });
try {
  await client.connect(transport);
  const { tools } = await client.listTools();
  assert.deepEqual(tools.map((tool) => tool.name).sort(), ['list_posts', 'read_post', 'search_posts']);
  assert.ok(tools.every((tool) => tool.annotations.readOnlyHint && !tool.annotations.destructiveHint));
  const call = async (name, args) => {
    const result = await client.callTool({ name, arguments: args });
    assert.ok(!result.isError, JSON.stringify(result));
    return result.structuredContent;
  };
  const list = await call('list_posts', { limit: 2 });
  assert.equal(list.articles.length, 2);
  assert.ok(list.feedArticleCount >= 2);
  const post = list.articles[0];
  const search = await call('search_posts', { query: post.title, limit: 2 });
  assert.ok(search.articles.some((article) => article.url === post.url));
  const legacyUrl = post.url.replace('/blog/azurenetworkingblog/', '/t5/azure-networking-blog/')
    .replace(/\/(\d+)$/, '/ba-p/$1');
  const read = await call('read_post', { url: legacyUrl, maxChars: 100 });
  assert.equal(read.text.length, 100);
  assert.equal(read.nextOffset, 100);
  assert.ok(read.totalChars > 100);
  const next = await call('read_post', { url: read.url, offset: 100, maxChars: 100 });
  assert.equal(next.text.length, 100);
  const invalid = await client.callTool({ name: 'read_post', arguments: { url: 'https://example.com/' } });
  assert.equal(invalid.isError, true);
  const invalidLimit = await client.callTool({ name: 'list_posts', arguments: { limit: 0 } });
  assert.equal(invalidLimit.isError, true);
  console.log(`PASS: MCP handshake, read-only annotations, list/search/read, legacy normalization, canonical redirects, chunking, and input rejection (${list.feedArticleCount} RSS posts).`);
} finally {
  await client.close();
}
