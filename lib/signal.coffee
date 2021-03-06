_  = require "lodash"
ff = (f, args) -> _.bind(f, {}, args...) if f

Event = require "./event.coffee"

class Signal
    isDead     : false
    frameSize  : 2
    frame      : []
    linked     : []
    transforms : [] #initial transform merely returns input
    # we should still use an array of transforms so that even if you call emit later you get
    # the same result

    constructor: (@transforms = [((x)->x)], @frameSize = 2) ->
        @frameSize = 2 if @frameSize < 2

    # Change the frame size, the case where you'd like to capture more events within the frame
    setFrameSize: (size) ->
        @frameSize = size # set frame size value
        this              # return self for chaining

    # Send event through all transforms - called whenever a new event is presented - optional callback to 
    emit : (value, meta, memoized) ->
        console.log @ if @_events
        return false if @isDead or not value                                # disallow emitting if dead
        if meta and meta.isEnd
            @isDead     = true
            @links      = []
            @transforms = []
            _(@linked).each (link) -> link.emit(value, meta, true) if @linked
            return false
        event = new Event(value, meta)
        if @frame.length >= @frameSize then @frame = [_.rest(@frame)..., event]  else @frame = [@frame..., event]
        if memoized
            computed = _(@transforms).last()(event)
        else
            computed = (compute = (i, evt) =>
                if i< @transforms.length then resultEvent = @transforms[i] evt else return evt
                if resultEvent and resultEvent.value then return compute i + 1, resultEvent else return undefined
            )(0, event)
        _(@linked).each (link) -> link.emit(computed.value, computed.meta, true) if computed
        this                                                    # return self

    # create new signal with the added transforms, and return the new signal from this function
    addTransform: (transform) ->
        transforms = [@transforms..., transform]
        signal = new Signal(transforms, @frameSize) # create new signal with transforms
        @linked = [@linked..., signal]
        signal                                      # return the new signal
                                                    # memoize repeated values with underscore
    fork: () ->
        signal = new Signal(@transforms, @frameSize) # create copy of this signal
        @linked = [@linked..., signal]
        signal                                      # return the new signal

    # remove all signals and their listeners, send kill to all signals
    kill: () -> @emit("_commitsudoku", {isEnd: true})


    #### ========================================
    #  Transforms: All of these return new signals
    #### ========================================

    # React to events moving through the signal
    react: (args..., f) ->
        @addTransform (event) ->
            result = ff(f, args)(event)
            if result then result else event

    # captures a range of events using the frame, if larger than frame, defaults to entire frame
    # if smaller than frame or full length unavailable, don't continue
    span: (size) ->
        @addTransform (event) =>
            event.value = [e.value for e in @frame.slice(0-size)][0]
            if event.value.length is size then event else undefined

    # Log everything moving through this
    log: (logger = console.log) ->
        @addTransform (event) ->
            logger(event)
            event

    # Filter events moving through the signal - pass along if false
    filter: (args..., f) ->
        @addTransform (event) ->
            if not ff(f, args)(event) then event else undefined

    # Skip duplicate events
    skipDuplicates: (isEqual = (a, b) -> a is b) ->
        @filter (event) =>
            if _.last(_.initial(@frame))
                isEqual _.last(_.initial(@frame)).value, event.value
            else if event.value
                false
            else
                true


    #### ========================================
    #  Management
    #### ========================================

    # on another signal's reaction, emit its value from this one
    merge: (signal) ->
        signal.react (event) => @emit(event.value)
        this

    # on another signal's reaction, emit its alue from this one
    mergeInner: (signal) ->
        @merge signal

    # on this signal's reaction, emit the same value from another one
    mergeOuter: (signal) ->
        @react (event) -> signal.emit(event.value)
        this

    # on another signal's reaction emit the combined values of this signal's last event, and the other new event
    join: (signal) ->
        newSignal = new Signal()
        signal.react (event) =>
            newSignal.emit [(if _.last(@frame) then _.last(@frame).value else undefined), event.value] # emit through the bus the last event of this signal
        newSignal


module.exports = exports = Signal
