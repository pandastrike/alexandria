# A content cache to store crawled content in Elasticsearch

Alexandria provides a simple interface to store resources downloaded from the web. It uses Elasticsearch to index downloaded content.

## Example Usage

```coffeescript

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
          # put a resource into cache
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
```

## Notes on Elasticsearch index and type mappings

* Index where resources are stored can be configured via `options` passed to `initialize`

* For every domain whose resources are stored, two type mappings are created

* One type to store content type and the actual content as either plain text (for text content) or base64 encoding (for binary content). Id of documents of this type will be md5 digest of the content.

* Another type to store url of the resource and a reference to the document that contains the actual content. Id of documents of this type will be md5 digest of the url.

* The two types are named `<domain_name_with_dot_replaced_with_underscore>_content` and second type is named `<domain_name_with_dot_replaced_with_underscore>`, example: a domain such as `example.com` would have the two types named `example_com_content` and `example_com`.

* Following are example mappings (in cson format) of the two types that would be created for domain `example.com`:

  * Mapping for type that stores the resource urls (content_ref field is md5 digest of the content itself)

        ```
        example_com:
            properties:
                url: type: "string"
                content_ref: type: "string", index: "not_analyzed"
        ```
        
  * Mapping for type that stores the content (text_content field contains plain text content if content type is text otherwise binary_content field stores binary content in base64 encoding)

        ```
        example_com_content
            properties:
                content_type: type: "string", index: "no"
                text_content: type: "string"
                binary_content: type: "binary"
        ```
