{ElasticSearch} = require "pirate"
{EventChannel} = require "mutual"
crypto = require "crypto"
{merge, md5, base64} = require "fairmont"
request = require("request")
zlib = require("zlib")

events = new EventChannel
events.on "error", (err) ->
  console.log "Oops! Failed ", err.stack
adapter = null

indexName = "crawler_cache"
maxRedirectsForDownload = 1
maxAttemptsOnDownloadError = 1

$ = {}

$.initialize = (options) ->
  events.source (_events) ->
    indexName = options.indexName if options.indexName?
    maxRedirectsForDownload = options.maxRedirectsForDownload if options.maxRedirectsForDownload?
    maxAttemptsOnDownloadError = options.maxAttemptsOnDownloadError if options.maxAttemptsOnDownloadError?

    _adapter = new ElasticSearch.Adapter(merge(options, events: events))
    _adapter.events.on "ready", (_adapter) ->
      adapter = _adapter
      _events.emit "success"

$.createStore = (domain) ->
  type = mapDomainToType(domain)
  do events.serially (go) ->
    go ->
      events.source (_events) ->
        adapter.client.createIndex(
          indexName
          (err, data) -> 
            _events.callback err, data
        )
    go ->
      mapping = {}
      mapping[type] = 
        properties:
          url: type: "string"
          content_ref: type: "string", index: "not_analyzed"
      events.source (_events) ->
        adapter.client.putMapping(
          indexName
          type
          mapping
          (err, data) -> 
            _events.callback err, data
        )
    go ->
      mapping = {}
      mapping["#{type}__content__"] = 
        properties:
          content_type: type: "string", index: "no"
          content: type: "binary"
      events.source (_events) ->
        adapter.client.putMapping(
          indexName
          "#{type}__content__"
          mapping
          (err, data) -> 
            _events.callback err, data
        )

$.deleteStore = (domain) ->
  type = mapDomainToType(domain)
  do events.serially (go) ->
    go ->
      events.source (_events) ->
        adapter.client.deleteMapping(
          indexName
          type
          (err, data) -> 
            _events.callback err, data
        )
    go ->
      events.source (_events) ->
        adapter.client.deleteMapping(
          indexName
          "#{type}__content__"
          (err, data) -> 
            _events.callback err, data
        )

$.getAllResourceUrls = (domain) ->
  type = mapDomainToType(domain)
  do events.serially (go) ->
    go -> adapter.collection indexName, type
    go (collection) ->
      collection.all
    go (results) ->
      if results?.length > 0
        resourceUrls = results.map (result) -> result.url
      else
        resourceUrls = []

$.getResource = (domain, url, downloadIfNotInCache) ->
  type = mapDomainToType(domain)
  url = url.replace(/(http(s)?:\/\/)?(www.)?/, "")
  collection = contentCollection = null
  urlDigest = md5(url)
  do events.serially (go) ->
    go ->
      do events.concurrently (go) ->
        go "_collection", -> adapter.collection indexName, type
        go "_contentCollection", -> adapter.collection indexName, "#{type}__content__"
    go ({_collection, _contentCollection}) ->
      collection = _collection
      contentCollection = _contentCollection
      collection.get urlDigest
    go (resource) ->
      if resource?
        contentCollection.get resource.content_ref
    go (content) ->
      if content?
        content.content = convertToContentType(content.content_type, content.content)
        return {content_type: content.content_type, content: content.content}
      if !downloadIfNotInCache
        return {content: null, content_type: null}

      do events.serially (go) ->
        go -> 
          events.source (_events) ->
            downloadResource url, 1, (result) ->
              _events.emit "success", result
        go ({content_type, content}) ->
          if content?
            base64Content = convertToBase64(content_type, content)
            contentDigest = crypto.createHash("md5").update(base64Content, "base64").digest("hex")
            contentCollection.put contentDigest, {content_type, content: base64Content}
            collection.put urlDigest, {url, content_ref: contentDigest}
          return {content_type, content}

$.putResource = (domain, url, content_type, content) ->
  type = mapDomainToType(domain)
  url = url.replace(/(http(s)?:\/\/)?(www.)?/, "")
  contentDigest = null
  collection = null
  contentCollection = null
  do events.serially (go) ->
    go ->
      do events.concurrently (go) ->
        go "_collection", -> adapter.collection indexName, type
        go "_contentCollection", -> adapter.collection indexName, "#{type}__content__"
    go ({_collection, _contentCollection}) ->
      collection = _collection
      contentCollection = _contentCollection
    go ->
      content = convertToBase64(content_type, content)
      contentDigest = crypto.createHash("md5").update(content, "base64").digest("hex")
      contentCollection.put contentDigest, {content_type, content}
    go ->
      urlDigest = md5(url)
      collection.put urlDigest, {url, content_ref: contentDigest}

downloadResource = (url, attempt, callback) ->
  req = request {uri: url, maxRedirects: 3}
  req.on "response", (res) ->
    if res.statusCode >= 400
      callback({content_type: null, content: null})
    else if res.statusCode >= 300 and res.statusCode < 400
      downloadResource(res.headers.location, attempt, callback)
    else
      encoding = res.headers["content-encoding"]
      encoding = encoding.toLowerCase() if encoding?
      content_type = res.headers["content-type"].toLowerCase()
      stream = res
      content = ""
      if encoding == "gzip"
        stream = res.pipe(zlib.createGunzip())
      else if (encoding == "deflate")
        stream = res.pipe(zlib.createInflate())
      stream.on "data", (data) ->
        content += data.toString("base64")
      stream.on "end", ->
        callback({content_type, content})
  req.on "error", (err) ->
    if attempt <= maxAttemptsOnDownloadError
      downloadResource(url, attempt + 1, callback)
    else
      callback({content_type: null, content: null})

mapDomainToType = (domain) ->
  domain.replace(/\./g, "_")

convertToContentType = (content_type, content) ->
  if content_type.indexOf("charset=utf-8") >= 0
    content = new Buffer(content, "base64")
    content = content.toString("utf8")
  content

convertToBase64 = (content_type, content) ->
  if content_type.indexOf("charset=utf-8") >= 0
    content = new Buffer(content, "utf8")
    content = content.toString("base64")
  content

module.exports = $