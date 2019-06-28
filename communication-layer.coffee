module.exports = (env) ->

  {EventEmitter} = require 'events'

  SerialPort = require 'serialport'
  Readline = SerialPort.parsers.Readline
  # SerialPort = serialport.SerialPort

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
        baudRate: baudrate,
        autoOpen: false
      })

    connect: () ->
      @ready = no

      @_serialDeviceInstance.removeAllListeners('error')
      @_serialDeviceInstance.removeAllListeners('data')
      @_serialDeviceInstance.removeAllListeners('close')

      @parser.removeAllListeners('data') if @parser?

      @removeAllListeners('newPacketForTransmission')
      @removeAllListeners('readyForNextPacketTransmission')

      @_serialDeviceInstance.on 'error', (error) =>
        @emit('error', error)
        env.logger.error "serialport communication error #{err}"

      @_serialDeviceInstance.on 'close', =>
        @emit 'close'
        @removeAllListeners('newPacketForTransmission')
        @removeAllListeners('readyForNextPacketTransmission')
      
      @parser = @_serialDeviceInstance.pipe(new Readline({ delimiter: '\n', encoding: 'ascii' }))

      @parser.on 'data', (data) =>
        env.logger.debug "incoming raw data from CUL: #{data}"
        dataString = "#{data}"
        dataString = dataString.replace(/[\r]/g, '')

        if (/^V(.*)/.test(dataString))
          env.logger.debug "Got Version String"
          #data contains cul version string
          @emit('culFirmwareVersion', dataString)
          @ready = yes
          @emit('ready')
        else if (/^Z(.*)/.test(dataString))
          @emit('culDataReceived',dataString)
        else if (/^LOVF/.test(dataString))
          @_current.setStatus('sendlimit')
        else
          env.logger.info "received unknown data: #{dataString}"
      
      @on('newPacketForTransmission', =>
        @processMessageQueue()
      )

      @on('readyForNextPacketTransmission', =>
        @processMessageQueue()
      )
      
      return new Promise( (resolve, reject) =>
        resolver = resolve
        @_open().then(() =>
          env.logger.info "serialPort #{@serialPortName} is open!"

          #check the version of the cul firmware
          env.logger.debug "check CUL Firmware version"
          @_serialDeviceInstance.writeAsync('V\n').then( =>
            env.logger.debug "Requested CUL Version..."
          ).catch(reject)
        #set resolver and resolve the promise if on ready event

        @once("ready", () => 
          env.logger.debug("Trigger Resolver on ready")
          # enable max mode of the cul firmware and rssi reporting
          env.logger.debug "enable MAX! Mode of the CUL868"
          @_serialDeviceInstance.writeAsync('X20\n').then( =>
            @_serialDeviceInstance.writeAsync('Zr\n').then( =>
              @_serialDeviceInstance.writeAsync('Za'+@_baseAddress+'\n')
            )
          ).catch(reject)
          resolver()
         )
        ).timeout(60000).catch( (err) =>
          if err.name is "TimeoutError"
            env.logger.info ('Timeout on CUL connect, cul is available but not responding')
          )
      ).catch( (err) =>
        env.logger.info ("Can not connect to serial port, cause: #{err}")
      )

    disconnect: ->
      @_serialDeviceInstance.closeAsync()

    _open: () ->
      unless @_serialDeviceInstance.isOpen
        @_serialDeviceInstance.openAsync()
      else
        Promise.resolve()

    # write data to the CUL device
    serialWrite: (data) ->
      if( @_serialDeviceInstance.isOpen )
        command = "Zs"+data+"\n"
        return @_serialDeviceInstance.writeAsync(command).then( =>
          env.logger.debug ("Send Packet to CUL: #{data}, awaiting drain event")
          @_serialDeviceInstance.drainAsync().then( =>
            env.logger.debug ("serial port buffer have been drained")
          )
        )
      else
        env.logger.debug ("Can not send packet because serial port is not open")
        return Promise.reject("Error: serial port is not open")

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
        #The last packet is done so we get the next one
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
        @serialWrite( packet.getRawPacket() ).catch( (err) =>
          reject(err)
        )
        @once("gotAck", =>
          @_ackResolver()
          packet.resolve(true)
          @cleanMessageQueueState()
        )
      ).timeout(3000).catch( (err) =>
        @removeAllListeners('gotAck')
        if err.name is "TimeoutError"
          if packet.getStatus() == 'sendlimit'
            @_currentSentPromise = @sendPacket(packet)
            env.logger.debug("Retransmit packet because of limit overflow")
          else if packet.getSendTries() < 3
            packet.setSendTries(packet.getSendTries() + 1)
            @_currentSentPromise = @sendPacket(packet)
            env.logger.debug("Retransmit packet #{packet.getRawPacket()}, try #{packet.getSendTries()} of 3")
          else
            env.logger.info("Paket #{packet.getRawPacket()} send but no response!")
            packet.reject("Paket #{packet.getRawPacket()} send but no response!");
            @cleanMessageQueueState()
        else
          env.logger.info("Paket #{packet.getRawPacket()} could no be send! #{err}")
          packet.reject("Paket #{packet.getRawPacket()} could no be send! #{err}");
          @cleanMessageQueueState()
      )

    cleanMessageQueueState: () ->
      @_current = null
      @emit('readyForNextPacketTransmission')

    ackPacket: ()->
      @emit('gotAck')
