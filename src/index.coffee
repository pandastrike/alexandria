{ElasticSearch} = require "pirate"
{EventChannel} = require "mutual"
crypto = require "crypto"
{merge} = require "fairmont"
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

$.createStore = (type) ->
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
      mapping["#{type}"] = 
        properties:
          url: type: "string"
          content_link: type: "string", index: "not_analyzed"
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

$.deleteStore = (type) ->
  do events.serially (go) ->
    go ->
      events.source (_events) ->
        adapter.client.deleteMapping(
          indexName
          "#{type}"
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

$.getResource = (type, url, downloadIfNotInCache) ->
  collection = contentCollection = null
  urlDigest = crypto.createHash("md5").update(url).digest("hex")
  do events.serially (go) ->
    go ->
      do events.concurrently (go) ->
        go "_collection", -> adapter.collection indexName, type
        go "_contentCollection", -> adapter.collection indexName, "#{type}__content__"
    go ({_collection, _contentCollection}) ->
      collection = _collection
      contentCollection = _contentCollection
      collection.get urlDigest
    go (results) ->
      if results?.length == 1
        contentCollection.get results[0].content_link
      else
        null
    go (content) ->
      if content?
        return {content: content.content, content_type: content.content_type}
      if !downloadIfNotInCache
        return {content: null, content_type: null}

      do events.serially (go) ->
        go -> 
          events.source (_events) ->
            downloadResource url, 1, (result) ->
              _events.emit "success", result
        go ({content_type, content}) ->
          if content?
            contentDigest = crypto.createHash("md5").update(content).digest("hex")
            contentCollection.put contentDigest, {content_type, content}
            collection.put urlDigest, {url, content_link: contentDigest}
          return {content_type, content}

$.putResource = (type, url, content_type, content) ->
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
      contentDigest = crypto.createHash("md5").update(content).digest("hex")
      contentCollection.put contentDigest, {content_type, content}
    go ->
      urlDigest = crypto.createHash("md5").update(url).digest("hex")
      collection.put urlDigest, {url, content_link: contentDigest}

downloadResource = (url, attempt, callback) ->
  req = request {uri: url, maxRedirects: 3}
  req.on "response", (res) ->
    if res.statusCode >= 400
      callback({content_type: null, content: null})
    else if res.statusCode >= 300 and res.statusCode < 400
      downloadResource(res.headers.location, attempt, callback)
    else
      encoding = res.headers["content-encoding"]
      content_type = res.headers["content-type"]
      stream = res
      content = ""
      if encoding == "gzip"
        stream = res.pipe(zlib.createGunzip())
      else if (encoding == "deflate")
        res.pipe(zlib.createInflate())
      stream.on "data", (data) ->
        content += data.toString("base64")
      stream.on "end", ->
        callback({content_type, content})
  req.on "error", (err) ->
    if attempt <= maxAttemptsOnDownloadError
      downloadResource(url, attempt + 1, callback)
    else
      callback({content_type: null, content: null})

module.exports = $