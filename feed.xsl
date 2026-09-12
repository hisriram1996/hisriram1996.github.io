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
        <script>
          (function () {
            var savedTheme;
            try {
              savedTheme = localStorage.getItem("theme");
            } catch (error) {
              savedTheme = null;
            }
            var theme = savedTheme || (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
            document.documentElement.setAttribute("data-theme", theme);
          }());
        </script>
        <script src="{{ '/assets/js/theme.js' | relative_url }}" defer="defer"></script>
      </head>
      <body>
        <header class="site-header">
          <div class="wrapper header-inner">
            <a class="site-title" href="{{ '/' | relative_url }}">
              <span class="site-mark" aria-hidden="true">SI</span>
              <xsl:value-of select="rss/channel/title"/>
            </a>
            <button class="theme-toggle" type="button" aria-label="Switch to dark mode" aria-pressed="false">
              <svg class="theme-icon theme-icon-sun" viewBox="0 0 24 24" aria-hidden="true">
                <circle cx="12" cy="12" r="4"></circle>
                <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"></path>
              </svg>
              <svg class="theme-icon theme-icon-moon" viewBox="0 0 24 24" aria-hidden="true">
                <path d="M20.5 14.2A8 8 0 0 1 9.8 3.5 8.5 8.5 0 1 0 20.5 14.2Z"></path>
              </svg>
            </button>
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
