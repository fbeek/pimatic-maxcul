module.exports = (env) ->

  {EventEmitter} = require 'events'

  serialport = require 'serialport'
  SerialPort = serialport.SerialPort

  Promise = env.require 'bluebird'
  Promise.promisifyAll(SerialPort.prototype)

  # This class represents the low level comminication interface
  class CommunicationServiceLayer extends EventEmitter

    constructor: (baudrate, serialPortName, @_baseAddress) ->
      @serialPortName = serialPortName
      env.logger.info("using serial device #{@serialPortName}@#{baudrate}")

      @_messageQueue = []
      @_sendMessages = []
      @_current = undefined
      @_busy = false
      @_ackResolver = null
      @_currentSentPromise = null

      @_serialDeviceInstance = new SerialPort(serialPortName, {
          baudrate: baudrate,
          parser: serialport.parsers.readline("\n")
        }, openImmediately = no)

    connect: () ->
      @ready = no

      @_serialDeviceInstance.removeAllListeners('error')
      @_serialDeviceInstance.removeAllListeners('data')
      @_serialDeviceInstance.removeAllListeners('close')

      @removeAllListeners('newPacketForTransmission')
      @removeAllListeners('readyForNextPacketTransmission')

      @_serialDeviceInstance.on 'error', (error) =>
        @emit('error', error)
        env.logger.error "serialport communication error #{err}"

      @_serialDeviceInstance.on 'close', =>
        @emit 'close'
        @removeAllListeners('newPacketForTransmission')
        @removeAllListeners('readyForNextPacketTransmission')

      @on('newPacketForTransmission', =>
        @processMessageQueue()
      )

      @on('readyForNextPacketTransmission', =>
        @processMessageQueue()
      )

      return @_serialDeviceInstance.openAsync().then( =>
        resolver = null
        timeout = 15000

        env.logger.info "serialPort #{@serialPortName} is open!"

        @_serialDeviceInstance.on 'data', (data) =>
          env.logger.debug "incoming raw data from CUL: #{data}"
          dataString = "#{data}"
          dataString = dataString.replace(/[\r]/g, '')

          if (/V(.*)/.test(dataString))
            #data contains cul version string
            @emit('culFirmwareVersion', dataString)
            @ready = yes
            @emit('ready')
          else
            env.logger.debug "from CUL -> #{dataString}"
            @emit('culDataReceived',dataString)

        return new Promise( (resolve, reject) =>
          Promise.delay(5000).then( =>
            #check the version of the cul firmware
            env.logger.debug "check CUL Firmware version"
            @_serialDeviceInstance.writeAsync('V\n').catch(reject)
          ).delay(5000).then( =>
            # enable max mode of the cul firmware
            env.logger.debug "enable MAX! Mode of the CUL868"
            @_serialDeviceInstance.writeAsync('Zr\nZa'+@_baseAddress+'\n').catch(reject)
          ).done()
          #set resolver and resolve the promise if on ready event
          resolver = resolve
          @once("ready", resolver)
        ).timeout(timeout).catch( (err) =>
          if err.name is "TimeoutError"
            env.logger.info ('Timeout on CUL connect, cul is available but not responding')
        )
      ).catch( (err) =>
        env.logger.info ("Can not connect to serial port, cause: #{err.cause}")
      )

    disconnect: ->
      @serialPort.closeAsync()

    # write data to the CUL device
    serialWrite: (data) ->
      command = "Zs"+data+"\n"
      return @_serialDeviceInstance.writeAsync(command).then( =>
          env.logger.debug "Send Packet to CUL: #{data}, awaiting ACK\n"
      )

    addPacketToTransportQueue: (packet) ->
      if (packet.getRawType() == "ShutterContact")
        #If the target is a shuttercontact this packet must be send as first, because it is
        #only awake for a short time period after it has transmited his data
        #prepend new packet to queue
        @_messageQueue.unshift(packet)
      else
        #append packet to queue
        @_messageQueue.push(packet)
      if(@_busy) then return
      @emit("newPacketForTransmission")

    processMessageQueue: () ->
      @_busy = true
      if(!@_current)
          ##The last packet is done so we get the next one
          next = @_messageQueue.shift()
      #If we have no new packet we have nothing to do here
      if(!next)
        env.logger.debug("no packet to handle in send queue")
        @_busy = false
        return

      if(next.getStatus == 'new')
        next.setStatus('send')
        next.setSendTries(1)

      @_current = next
      @_currentSentPromise = @sendPacket()

    sendPacket: () ->
      packet = @_current
      return new Promise( (resolve, reject) =>
        @_ackResolver = resolve
        @serialWrite(packet.getRawPacket()).done()
        @once("gotAck", =>
          @_ackResolver()
          @cleanMessageQueueState()
        )
      ).timeout(3000).catch( (err) =>
        if err.name is "TimeoutError" and packet.getSendTries() < 3
          packet.setSendTries(packet.getSendTries() + 1)
          @removeAllListeners('gotAck')
          @_currentSentPromise = @sendPacket(packet)
          env.logger.debug("Retransmit packet #{packet.getRawPacket()}, try #{packet.getSendTries()} of 3")
        else if err.name is "TypeError"
          env.logger.debug("#{err}")
        else
          env.logger.debug("Paket #{packet.getRawPacket()} could no be send! (no response)")
          @removeAllListeners('gotAck')
          @cleanMessageQueueState()
      )

    cleanMessageQueueState: () ->
      @_current = null
      @emit('readyForNextPacketTransmission')

    ackPacket: ()->
      @emit('gotAck')
