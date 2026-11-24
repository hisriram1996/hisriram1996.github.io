import { load } from 'cheerio';
import { XMLParser, XMLValidator } from 'fast-xml-parser';

export const BLOG_URL = 'https://techcommunity.microsoft.com/category/azure/blog/azurenetworkingblog';
export const FEED_URL = 'https://techcommunity.microsoft.com/t5/s/gxcuf89792/rss/board?board.id=AzureNetworkingBlog';
const ORIGIN = 'https://techcommunity.microsoft.com';
const MAX_BYTES = 8 * 1024 * 1024;
const CACHE_MS = 5 * 60 * 1000;

export function articleUrl(value) {
  const url = new URL(value);
  if (
    url.origin !== ORIGIN || url.username || url.password || url.search || url.hash ||
    !(/^\/blog\/azurenetworkingblog\/[^/]+\/\d+\/?$/i.test(url.pathname) ||
      /^\/t5\/azure-networking-blog\/[^/]+\/ba-p\/\d+\/?$/i.test(url.pathname))
  ) {
    throw new Error('Only Azure Networking Blog article URLs on techcommunity.microsoft.com are allowed.');
  }
  const legacy = /^\/t5\/azure-networking-blog\/([^/]+)\/ba-p\/(\d+)\/?$/i.exec(url.pathname);
  if (legacy) url.pathname = `/blog/azurenetworkingblog/${legacy[1]}/${legacy[2]}`;
  return url.href;
}

export function htmlToText(html) {
  const $ = load(html);
  $('script, style, noscript, iframe, form').remove();
  $('br').replaceWith('\n');
  $('p, div, section, h1, h2, h3, h4, h5, h6, ul, ol, table, tr, pre, blockquote').each((_, el) => {
    $(el).prepend('\n').append('\n');
  });
  $('li').each((_, el) => { $(el).prepend('\n- ').append('\n'); });
  $('td, th').append(' | ');
  $('a[href]').each((_, el) => {
    const text = $(el).text().trim();
    const href = $(el).attr('href');
    if (text && /^https?:\/\//i.test(href)) $(el).text(`${text} (${href})`);
  });
  return $.root().text().replace(/[ \t]+/g, ' ').replace(/ *\n */g, '\n')
    .replace(/\n{3,}/g, '\n\n').trim();
}

export function parseFeed(xml) {
  if (XMLValidator.validate(xml) !== true || /<!DOCTYPE|<!ENTITY/i.test(xml)) {
    throw new Error('The blog returned invalid or unsupported RSS XML.');
  }
  const parsed = new XMLParser({
    ignoreAttributes: true,
    parseTagValue: false,
    processEntities: false,
    isArray: (name) => name === 'item',
  }).parse(xml);
  const channel = parsed?.rss?.channel;
  if (!channel || !Array.isArray(channel.item) || channel.item.length === 0) {
    throw new Error('The blog RSS feed contains no articles or its format has changed.');
  }
  const decode = (value) => load(String(value ?? ''), {}, false).root().text();
  return channel.item.map((item) => {
    const published = new Date(item.pubDate);
    if (!item.title || !item.description || Number.isNaN(published.getTime())) {
      throw new Error('An RSS article is missing a title, body, or valid publication date.');
    }
    return {
      title: decode(item.title),
      url: articleUrl(decode(item.link)),
      author: decode(item['dc:creator']),
      published: published.toISOString(),
      text: htmlToText(decode(item.description)),
    };
  }).sort((a, b) => b.published.localeCompare(a.published));
}

export async function fetchPublicText(url, fetchImpl = fetch, validateRedirect = articleUrl) {
  const signal = AbortSignal.timeout(30_000);
  let current = url;
  for (let redirects = 0; redirects <= 5; redirects += 1) {
    const response = await fetchImpl(current, {
      method: 'GET',
      redirect: 'manual',
      signal,
      headers: {
        Accept: 'application/rss+xml, application/xml, text/xml, text/html',
        'User-Agent': 'azure-networking-blog-mcp/1.0 (read-only RSS reader)',
      },
    });
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      await response.body?.cancel();
      const location = response.headers.get('location');
      if (!location) throw new Error('The blog returned a redirect without a location.');
      current = validateRedirect(new URL(location, current).href);
      continue;
    }
    if (!response.ok) {
      await response.body?.cancel();
      throw new Error(`Blog request failed with HTTP ${response.status}.`);
    }
    if (!response.body) throw new Error('The blog returned an empty response.');
    const chunks = [];
    let size = 0;
    for await (const chunk of response.body) {
      size += chunk.length;
      if (size > MAX_BYTES) throw new Error('The blog response exceeded the 8 MiB safety limit.');
      chunks.push(chunk);
    }
    return { text: Buffer.concat(chunks).toString('utf8'), url: current };
  }
  throw new Error('The blog returned too many redirects.');
}

export function parseArticle(html, url) {
  const $ = load(html);
  const body = $('[data-testid="StandardMessageView"] [class*="lia-g-message-body__"]').first();
  const title = $('[data-testid="MessageSubject"]').first().text().trim();
  if (!title || !body.length || !body.text().trim()) {
    throw new Error('Article content was not found. The site may have changed or returned a challenge page.');
  }
  return {
    title,
    url: articleUrl(url),
    text: htmlToText(body.html()),
  };
}

export class BlogClient {
  constructor(fetchImpl = fetch) {
    this.fetchImpl = fetchImpl;
    this.cache = null;
  }

  async articles() {
    if (this.cache && Date.now() - this.cache.timestamp < CACHE_MS) return this.cache.articles;
    const result = await fetchPublicText(FEED_URL, this.fetchImpl, (url) => {
      if (url !== FEED_URL) throw new Error('Unexpected RSS redirect; refusing to leave the fixed feed endpoint.');
      return url;
    });
    const articles = parseFeed(result.text);
    this.cache = { articles, timestamp: Date.now() };
    return articles;
  }

  async list({ query, limit = 10, offset = 0 } = {}) {
    const articles = await this.articles();
    const words = query?.toLowerCase().split(/\s+/).filter(Boolean) ?? [];
    const matches = articles.filter((article) => {
      const haystack = `${article.title}\n${article.author}\n${article.text}`.toLowerCase();
      return words.every((word) => haystack.includes(word));
    });
    return {
      source: BLOG_URL,
      scope: 'Recent posts supplied by the public RSS feed, not the complete blog archive.',
      fetchedAt: new Date(this.cache.timestamp).toISOString(),
      feedArticleCount: articles.length,
      totalMatches: matches.length,
      nextOffset: offset + limit < matches.length ? offset + limit : null,
      articles: matches.slice(offset, offset + limit).map(({ text, ...metadata }) => ({
        ...metadata, excerpt: text.slice(0, 400),
      })),
    };
  }

  async read({ url, offset = 0, maxChars = 12000 }) {
    const requestedUrl = articleUrl(url);
    const result = await fetchPublicText(requestedUrl, this.fetchImpl);
    const article = parseArticle(result.text, result.url);
    return {
      ...article,
      text: article.text.slice(offset, offset + maxChars),
      totalChars: article.text.length,
      nextOffset: offset + maxChars < article.text.length ? offset + maxChars : null,
    };
  }
}
