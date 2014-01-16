alexandria = require "../src/index.coffee"
{EventChannel} = require "mutual"
sleep = require "sleep"

#elasticsearch configuration
options = 
  indexName: "example_crawler_cache"
  host: "127.0.0.1"
  port: 9200
  secure: false

events = new EventChannel
events.on "error", (err) ->
  console.log "Error: #{err}"

run = () ->
  console.log "\nExample usage of alexandria..."
  do events.serially (go) ->
    go -> 
      console.log "Initializing alexandria"
      # initialize alexandria with elasticsearch server details 
      alexandria.initialize(options)
    go -> 
      console.log "Deleting store"
      # delete all of crawler cache, if you want to crawl from scratch
      alexandria.deleteStore()
    go -> 
      console.log "Creating store"
      # create crawler cache, if you want to crawl from scratch
      alexandria.createStore()
    go -> 
      console.log "Getting resource from cache"
      # sleep for a second to give elasticsearch enough time to replicate
      sleep.sleep 1
      # get a resource from cache
      # note the second argument (indicates whether to download if not in cache)
      alexandria.getResource("http://en.wikipedia.org/wiki/Main_Page", true)
    go ({contentType, content}) -> 
      # work with the downloaded content
    go ->
      console.log "Putting resource into cache"
      # sleep for a second to give elasticsearch enough time to replicate
      sleep.sleep 1
      # put a resource into cache, if not in cache download from the given url
      alexandria.putResource(
        "http://example.com/test-resource.html"
        "text/html; charset=utf-8"
        "<html><head></head><body><div></div></body></html>"
      )
    go ->
      console.log "Getting urls of all resources in cache\n"
      # sleep for a second to give elasticsearch enough time to replicate
      sleep.sleep 1
      # get urls of all resources in cache from a given domain
      alexandria.getAllResourceUrls("wikipedia.org")

run()