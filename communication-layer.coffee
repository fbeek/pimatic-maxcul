module.exports = (env) ->

  serialport = require 'serialport'
  SerialPort = serialport.SerialPort

  # This class represents the low level comminication interface
  class CommunicationServiceLayer
    @_serialDeviceInstance
    @_messageQueue = []
    @_current
    @_busy = false
    @_baseAddress

    constructor: (baudrate, serialPortName, @cmdReceiver, baseAddress) ->
      env.logger.info("using serial device #{serialPortName}@#{baudrate}")
      env.logger.info "trying to open serialport..."
      @_baseAddress = baseAddress
      @_serialDeviceInstance = new SerialPort serialPortName,
        {
          baudrate: baudrate,
          parser: serialport.parsers.readline("\n")
        },
        false

      @_serialDeviceInstance.on 'data', (data) =>
        dataString = "#{data}"
        dataString = dataString.replace(/[\r]/g, '')
        env.logger.debug "from CUL -> #{dataString}"
        # line feed ?

        if (/V(.*)/.test(dataString))
          env.logger.info "CUL VERSION: #{dataString}"
        else
          @cmdReceiver dataString

      @_serialDeviceInstance.open (err) =>
        if ( err? )
          env.logger.info "opening serialPort #{serialPortName} failed #{err}"
        else
          env.logger.info "serialPort #{serialPortName} is open!"
          @_serialDeviceInstance.write('V\n')
          env.logger.info "enable MAX! Mode of the CUL868"
          # enable the receiving of MAX messages
          @_serialDeviceInstance.write('Zr\nZa'+@_baseAddress+'\n')

      @_serialDeviceInstance.on 'error', (err) ->
        env.logger.error "serialport communication error #{err}"

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

    addPacketToTransportQueue: (packet) ->
      if (packet.targetDeviceType == "ShutterContact")
        #If the target is a shuttercontact this packet must be send as first, because it is
        #only awake for a short time period after it has transmited his data
        @_messageQueue.unshift(packet)
      else
        @_messageQueue.push(packet)
      if(@_busy) then return
      @_busy = true
      @processMessageQueue()

    processMessageQueue: () ->
      next = @_messageQueue.shif()
      if(!next)
        @_busy = false
        return
      @_current = next
      @serialWrite(next.serialData)
