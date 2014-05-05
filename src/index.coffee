{ElasticSearch} = require "pirate"
{EventChannel} = require "mutual"
crypto = require "crypto"
{merge, md5} = require "fairmont"
request = require("request")
zlib = require("zlib")
URL = require("url")

events = new EventChannel
events.on "error", (err) ->
  console.log "Oops! Failed ", err

adapter = null

indexName = "crawler_cache"
maxRedirectsForDownload = 1
maxAttemptsOnDownloadError = 1
userAgent = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:13.0) Gecko/20100101 Firefox/13.0.1"

$ = {}

$.initialize = (options) ->
  events.source (_events) ->
    indexName = options.indexName if options.indexName?
    maxRedirectsForDownload = options.maxRedirectsForDownload if options.maxRedirectsForDownload?
    maxAttemptsOnDownloadError = options.maxAttemptsOnDownloadError if options.maxAttemptsOnDownloadError?
    userAgent = options.userAgent if options.userAgent?

    _adapter = new ElasticSearch.Adapter(merge(options, events: events))
    _adapter.events.on "ready", (_adapter) ->
      adapter = _adapter
      _events.emit "success"

$.createStore = () ->
  events.source (_events) ->
    adapter.client.createIndex(
      indexName
      (err, data) -> _events.callback err, data
    )

$.deleteStore = () ->
  events.source (_events) ->
    adapter.client.deleteIndex(
      indexName
      (err, data) -> _events.callback err, data
    ) 

$.getAllResourceUrls = (domain) ->
  type = mapDomainToType(domain)
  do events.serially (go) ->
    go -> adapter.collection indexName, type
    go (collection) ->
      collection.all()
    go (results) ->
      if results?.length > 0
        resourceUrls = results.map (result) -> result.url
      else
        resourceUrls = []

$.getResource = (url, downloadIfNotInCache, domain) ->
  domain = getDomain(url) if !domain?
  type = mapDomainToType(domain)
  canonicalUrl = url.replace(/(http(s)?:\/\/)?(www.)?/, "")
  collection = contentCollection = null
  urlDigest = md5(canonicalUrl)
  do events.serially (go) ->
    go ->
      do events.concurrently (go) ->
        go "_collection", -> adapter.collection indexName, type
        go "_contentCollection", -> adapter.collection indexName, "#{type}_content"
    go ({_collection, _contentCollection}) ->
      if _collection? and _contentCollection?
        collection = _collection
        contentCollection = _contentCollection
        collection.get urlDigest
    go (resource) ->
      if resource?
        contentCollection.get resource.content_ref
    go (content) ->
      if content?
        if $.isContentText(content.content_type)
          return {contentType: content.content_type, content: content.text_content}
        else
          return {contentType: content.content_type, content: content.binary_content}
        
      if !downloadIfNotInCache
        return {contentType: null, content: null}

      do events.serially (go) ->
        go -> 
          events.source (_events) ->
            $.downloadResource url, 1, (result) ->
              _events.emit "success", result
        go ({contentType, content}) ->
          if content?
            do events.serially (go) ->
              go -> $.putResource(url, contentType, content, domain)
              go -> return {contentType, content}
          else
            return {contentType, content}

$.putResource = (url, contentType, content, domain) ->
  domain = getDomain(url) if !domain?
  type = mapDomainToType(domain)
  canonicalUrl = url.replace(/(http(s)?:\/\/)?(www.)?/, "")
  contentDigest = null
  collection = null
  contentCollection = null
  do events.serially (go) ->
    go ->
      do events.concurrently (go) ->
        go "_collection", -> adapter.collection indexName, type
        go "_contentCollection", -> adapter.collection indexName, "#{type}_content"
    go ({_collection, _contentCollection}) ->
      if _collection? and _contentCollection?
        collection = _collection
        contentCollection = _contentCollection
      else
        do events.serially (go) ->
          go -> 
            putMapping(type)
          go -> 
            do events.concurrently (go) ->
              go "_collection", -> adapter.collection indexName, type
              go "_contentCollection", -> adapter.collection indexName, "#{type}_content"
          go ({_collection, _contentCollection}) ->
            collection = _collection
            contentCollection = _contentCollection
    go ->
      contentDigest = md5(content)
      if $.isContentText(contentType)
        contentCollection.put(contentDigest, {content_type: contentType, text_content: content})
      else
        contentCollection.put(contentDigest, {content_type: contentType, binary_content: content})
    go ->
      urlDigest = md5(canonicalUrl)
      collection.put urlDigest, {url: canonicalUrl, content_ref: contentDigest}

$.deleteResource = (url, domain) ->
  domain = getDomain(url) if !domain?
  type = mapDomainToType(domain)
  canonicalUrl = url.replace(/(http(s)?:\/\/)?(www.)?/, "")
  collection = contentCollection = null
  urlDigest = md5(canonicalUrl)
  resource = null
  do events.serially (go) ->
    go ->
      do events.concurrently (go) ->
        go "_collection", -> adapter.collection indexName, type
        go "_contentCollection", -> adapter.collection indexName, "#{type}_content"
    go ({_collection, _contentCollection}) ->
      if _collection? and _contentCollection?
        collection = _collection
        contentCollection = _contentCollection
        collection.get urlDigest
    go (_resource) ->
      resource = _resource
      if resource?
        collection.delete urlDigest
    go ->
      if resource?
        contentCollection.delete resource.content_ref

$.downloadResource = (url, attempt, callback) ->
  req = request {uri: url, headers: {"User-Agent": userAgent}, maxRedirects: maxRedirectsForDownload}
  req.on "response", (res) ->
    if res.statusCode >= 400
      callback({contentType: null, content: null, statusCode: res.statusCode})
    else if res.statusCode >= 300 and res.statusCode < 400
      $.downloadResource(res.headers.location, attempt, callback)
    else
      encoding = res.headers["content-encoding"]
      encoding = encoding.toLowerCase() if encoding?
      contentType = res.headers["content-type"].toLowerCase()
      content = ""
      res.setEncoding("binary")
      stream = res
      if encoding == "gzip"
        stream = res.pipe(zlib.createGunzip())
      else if encoding == "deflate"
        stream = res.pipe(zlib.createInflate())
      stream.on "data", (chunk) ->
        content += chunk
      stream.on "end", ->
        content = new Buffer(content, "binary")
        if $.isContentText(contentType)
          content = content.toString()
        else
          content = content.toString("base64")
        callback({contentType, content, statusCode: res.statusCode})
      stream.on "error", (err) ->
        callback({contentType: null, content: null, statusCode: res.statusCode})
  req.on "error", (err) ->
    if attempt <= maxAttemptsOnDownloadError
      $.downloadResource(url, attempt + 1, callback)
    else
      callback({contentType: null, content: null, statusCode: 999})

$.isContentText = (contentType) ->
  return contentType.indexOf("text/") == 0 or contentType.indexOf("application/javascript") == 0

putMapping = (type) -> 
  do events.serially (go) ->
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
      mapping["#{type}_content"] = 
        properties:
          content_type: type: "string", index: "no"
          text_content: type: "string"
          binary_content: type: "binary"
      events.source (_events) ->
        adapter.client.putMapping(
          indexName
          "#{type}_content"
          mapping
          (err, data) -> 
            _events.callback err, data
        )

mapDomainToType = (domain) ->
  domain.replace(/\./g, "_")

getDomain = (url) ->
  URL.parse(url).hostname.split(".")[-2..].join(".")

module.exports = $