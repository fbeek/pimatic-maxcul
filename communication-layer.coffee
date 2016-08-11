module.exports = (env) ->

  {EventEmitter} = require 'events'

  serialport = require 'serialport'
  SerialPort = serialport.SerialPort

  Promise = env.require 'bluebird'
  Promise.promisifyAll(SerialPort.prototype)

  # This class represents the low level comminication interface
  class CommunicationServiceLayer extends events.EventEmitter

    constructor: (baudrate, serialPortName, @cmdReceiver, @_baseAddress) ->
      env.logger.info("using serial device #{serialPortName}@#{baudrate}")
      env.logger.info("trying to open serialport...")

      @_messageQueue = []
      @_sendMessages = []
      @_current = undefined
      @_busy = false

      @_serialDeviceInstance = new SerialPort serialPortName, {
          baudrate: baudrate,
          parser: serialport.parsers.readline("\n")
        }, openImmediately = no)

    connect: (timeout, retries) ->
      @ready = no
      @_serialDeviceInstance.removeAllListeners('error')
      @_serialDeviceInstance.removeAllListeners('data')
      @_serialDeviceInstance.removeAllListeners('close')

      @_serialDeviceInstance.on 'error', (error) =>
        @emit('error', error)
        env.logger.error "serialport communication error #{err}"

      @_serialDeviceInstance.on 'close', => @emit 'close'

      return @_serialDeviceInstance.openAsync().then( =>
        @_serialDeviceInstance.on 'data', (data) =>
          dataString = "#{data}"
          dataString = dataString.replace(/[\r]/g, '')

          if (/V(.*)/.test(dataString))
            env.logger.info "CUL FW Version: #{dataString}"
          else
            env.logger.debug "from CUL -> #{dataString}"
            @emit('culDataReceived',dataString)
      )

      #--------------------------------------------
      @_serialDeviceInstance.open (err) =>
        if ( err? )
          env.logger.info "opening serialPort #{serialPortName} failed #{err}"
        else
          env.logger.info "serialPort #{serialPortName} is open!"
          @_serialDeviceInstance.write('V\n')
          env.logger.info "enable MAX! Mode of the CUL868"
          # enable the receiving of MAX messages
          @_serialDeviceInstance.write('Zr\nZa'+@_baseAddress+'\n')


      setInterval( =>
        #@checkMessageQueueForTimeouts()
        @processMessageQueue()
      , 3000
      )
        #--------------------------------------------


    disconnect: -> @serialPort.closeAsync()







    serialWrite: (data) ->
      convertedData = data.toUpperCase()
      command = "Zs"+convertedData+"\n"

      @_serialDeviceInstance.write(command,() =>
        @_serialDeviceInstance.drain( (error)->
            if (error)
              env.logger.error "Serialport draining error !"
            else
              env.logger.info "send done !"
          )
      )
      env.logger.info "Send Packet to CUL: #{convertedData}\n"
      #@processMessageQueue()

    addPacketToTransportQueue: (packet) ->
      packet.status = 'new'
      if (packet.deviceType == "ShutterContact")
        #If the target is a shuttercontact this packet must be send as first, because it is
        #only awake for a short time period after it has transmited his data
        #prepend new packet to queue
        @_messageQueue.unshift(packet)
      else
        #append packet to queue
        @_messageQueue.push(packet)
      if(@_busy) then return
      @_busy = true
      @processMessageQueue()

    ackPacket: ()->
      @_current.status = 'done'

    processMessageQueue: () ->
      if(@_current)
        #check if the last packet was send and we got an ack
        if(@_current.status != 'done' && @_current.status != 'error')
          ##We musst handle the last packet again
          next = @_current
        else
          ##The last packet is done so we get the next one
          next = @_messageQueue.shift()
      else
          ##The last packet is done so we get the next one
          next = @_messageQueue.shift()
      #If we have no new packet we have nothing to do here
      if(!next)
        env.logger.debug("no packet to handle in send queue")
        @_busy = false
        return

      @_current = next

      if(next.status == 'new')
        next.status = 'send'
        next.sendTries = 3
      else if(next.status == 'send')
        env.logger.debug("Retransmit packet #{next.preparedPacket}, try #{next.sendTries} of 3")
        next.sendTries--

      if(next.sendTries > 0)
        @_current.sendTime = Math.floor(new Date() / 1000);
        env.logger.debug("send")
        @serialWrite(next.preparedPacket)
      else
        env.logger.info "Paket #{next.preparedPacket} could no be send! (no response)"
        @_current.status = 'error'

      console.log("++++++++++++next+++++++++++++++++\n",next,'\n------------------------------------------\n');

    checkMessageQueueForTimeouts: () ->
      now = Math.floor(new Date() / 1000);
      console.log('+++++++++++++Waiting+++++++++++++++++',@_sendMessages,'------------------------------------------');
      for packet, key in @_sendMessages
        if now - packet.sendTime > 3
          if packet.sendTries <= 3
            @_sendMessages.splice(key, 1)

            @addPacketToTransportQueue(packet);
          else
            @_sendMessages.splice(key, 1)
