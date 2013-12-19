# A content cache to store crawled content in Elasticsearch

Alexandria provides a simple interface to store resources downloaded from the web. It uses Elasticsearch to index downloaded content.

## Usage

All methods in alexandria return an `EventChannel`:

    alexandria = require "alexandria"
    
    # Elasticsearch host, port and protocol details
    options =
      host: "127.0.0.1"
      port: 9200
      secure: false
      
    do events.serially (go) ->
      go -> alexandria.initialize(options)
      go -> alexandria.deleteStore(someDomain)
      go -> alexandria.createStore(someDomain)
      go -> alexandria.putResource(someDomain, someUrl, content_type, content)
      go -> alexandria.putResource(someDomain, someOtherUrl, content_type, content)
      go -> alexandria.getResource(domain, someUrl, true) # pass false as last argument if resource is not to be downloaded if not in cache
      go -> alexandria.getResource(domain, someOtherUrl, true)
      go -> alexandria.getAllResourceUrls(someDomain)


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
