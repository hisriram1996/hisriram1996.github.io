---
layout: null
---
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="html" encoding="UTF-8" doctype-system="about:legacy-compat"/>

  <xsl:template match="/">
    <html lang="en">
      <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <title><xsl:value-of select="rss/channel/title"/> · RSS Feed</title>
        <link rel="stylesheet" href="{{ '/assets/css/style.css' | relative_url }}"/>
      </head>
      <body>
        <header class="site-header">
          <div class="wrapper header-inner">
            <a class="site-title" href="{{ '/' | relative_url }}">
              <span class="site-mark" aria-hidden="true">SI</span>
              <xsl:value-of select="rss/channel/title"/>
            </a>
          </div>
        </header>

        <main class="page-content">
          <div class="wrapper feed-page">
            <header class="feed-heading">
              <span class="eyebrow">RSS feed</span>
              <h1><xsl:value-of select="rss/channel/title"/></h1>
              <p><xsl:value-of select="rss/channel/description"/></p>
              <p class="feed-help">Subscribe by copying this page's URL into your preferred RSS reader.</p>
            </header>

            <section class="feed-items" aria-label="Recent posts">
              <xsl:for-each select="rss/channel/item">
                <article class="feed-item">
                  <p class="post-meta"><xsl:value-of select="pubDate"/></p>
                  <h2>
                    <a href="{link}"><xsl:value-of select="title"/></a>
                  </h2>
                  <p><xsl:value-of select="description"/></p>
                </article>
              </xsl:for-each>
            </section>
          </div>
        </main>
      </body>
    </html>
  </xsl:template>
</xsl:stylesheet>
