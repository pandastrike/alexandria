#test suite to test alexandria for wiki pages
Testsuite = require("./interface")

options =
  title: "Wiki cache in alexandria"
  elasticsearch:
    host: "127.0.0.1"
    port: 9200
    secure: false
    indexName: "test_crawler_cache"
  domains: [
    "en.wikipedia.org"
    "upload.wikimedia.org"
    "en.wikipedia.com"
  ]
  resourcesToGet: [
    {url: "http://en.wikipedia.org/wiki/Main_Page", contentType: "text/html; charset=utf-8"}
    {url: "http://en.wikipedia.org/wiki/Help:Contents", contentType: "text/html; charset=utf-8"}
    {url: "http://en.wikipedia.org/wiki/Wikipedia:About", contentType: "text/html; charset=utf-8"}
    {url: "http://en.wikipedia.org/wiki/Wikipedia:Community_portal", contentType: "text/html; charset=utf-8"}
    {url: "http://en.wikipedia.org/wiki/Special:RecentChanges", contentType: "text/html; charset=utf-8"}
    {url: "http://upload.wikimedia.org/wikipedia/en/b/bc/Wiki.png", contentType: "image/png"}
  ]
  resourcesToPut: [
    {url: "http://en.wikipedia.com/test.html", contentType: "text/html; charset=utf-8", content: "<html><head></head><body><div></div></body></html>"}
  ]

Testsuite.run options