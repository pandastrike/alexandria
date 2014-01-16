Testify = require "testify"
assert = require "assert"
{sleep} = require "sleep"
{EventChannel} = require("mutual")
alexandria = require "../src/index"

events = new EventChannel
events.on "error", (err) ->
  console.log "Oops! Failed ", err.stack

module.exports = class TestSuite
  @run: (options, onCompletion) -> 
    suite = new @(options)
    suite.run(onCompletion)

  constructor: (@options) ->
    
  run: (onCompletion) ->
    Testify.test "Alexandria Tests - #{@options.title}", (context) =>
      @initialize(context)
    Testify.emitter.on("done", onCompletion) if onCompletion?

  initialize: (context) ->
    context.test "Initialize", (context) =>
      events = alexandria.initialize @options.elasticsearch
      events.once "error", (error) => context.fail(error)
      events.once "success", => @createStore(context)

  createStore: (context) ->
    context.test "Create store", (context) =>
      events = alexandria.createStore()
      events.once "error", (error) => context.fail(error)
      events.once "success", (data) => @iterateToGetResources(context)

  iterateToGetResources: (context) ->
    sleep 1
    currentIndex = 0
    finishGetting = (context) =>
      if currentIndex < @options.resourcesToGet.length
        iterateToGet(context)
      else
        @iterateToPutResources(context)
    iterateToGet = (context) =>
      resourceToGet = @options.resourcesToGet[currentIndex]
      currentIndex++
      context.test "Get resource '#{resourceToGet.url}'", (context) =>
        events = alexandria.getResource(resourceToGet.url, true)
        events.once "error", (error) => context.fail(error)
        events.once "success", (data) =>
          if data?.contentType? and data?.content?
            assert.equal data.contentType, resourceToGet.contentType
            finishGetting(context)
          else
            context.fail(new Error("Failed to get resource '#{resourceToGet.url}'"))

    iterateToGet(context)

  iterateToPutResources: (context) ->
    sleep 1
    currentIndex = 0
    finishPutting = (context) =>
      if currentIndex < @options.resourcesToPut.length
        iterateToPut(context)
      else
        @iterateToGetResourcesThatWerePut(context)
    iterateToPut = (context) =>
      resourceToPut = @options.resourcesToPut[currentIndex]
      currentIndex++
      context.test "Put resource '#{resourceToPut.url}'", (context) =>
        events = alexandria.putResource(resourceToPut.url, resourceToPut.contentType, resourceToPut.content)
        events.once "error", (error) => context.fail(error)
        events.once "success", (data) => finishPutting(context)

    iterateToPut(context)

  iterateToGetResourcesThatWerePut: (context) ->
    sleep 1
    currentIndex = 0
    finishGetting = (context) =>
      if currentIndex < @options.resourcesToPut.length
        iterateToGet(context)
      else
        @iterateToGetAllResources(context)
    iterateToGet = (context) =>
      resourceThatWasPut = @options.resourcesToPut[currentIndex]
      currentIndex++
      context.test "Get resource '#{resourceThatWasPut.url}'", (context) =>
        events = alexandria.getResource(resourceThatWasPut.url, false)
        events.once "error", (error) => context.fail(error)
        events.once "success", (data) =>
          if data?.contentType? and data?.content?
            assert.equal data.contentType, resourceThatWasPut.contentType
            assert.equal data.content, resourceThatWasPut.content
            finishGetting(context)
          else
            context.fail(new Error("Failed to get resource '#{resourceThatWasPut.url}'"))

    iterateToGet(context)

  iterateToGetAllResources: (context) ->
    sleep 1
    currentIndex = 0
    resourcesInCache = 0
    finishGetting = (context) =>
      if currentIndex < @options.domains.length
        iterateToGet(context)
      else
        assert.equal resourcesInCache, (@options.resourcesToGet.length + @options.resourcesToPut.length)
        @deleteStore(context)
    iterateToGet = (context) =>
      domain = @options.domains[currentIndex]
      currentIndex++
      context.test "Get all resource urls of '#{domain}'", (context) =>
        events = alexandria.getAllResourceUrls(domain)
        events.once "error", (error) => context.fail(error)
        events.once "success", (data) =>
          if data?
            resourcesInCache += data.length
            finishGetting(context)
          else
            context.fail(new Error("Failed to get all resource urls of '#{domain}'"))

    iterateToGet(context)

  deleteStore: (context) ->
    context.test "Delete store", (context) =>
      events = alexandria.deleteStore()
      events.once "error", (error) => context.fail(error)
      events.once "success", => 
        context.pass()