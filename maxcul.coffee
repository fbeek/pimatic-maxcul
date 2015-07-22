module.exports = (env) ->

  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  {SerialPort} = require 'serialport'
  HiPack = require 'hipack'

  class MaxculPlugin extends env.plugins.Plugin

    #Holds the communication layer instance
    @comLayer

    #Hold the MAX Driver Service Class instance
    @maxDriver

    @baudrate
    @serialPortName

    init: (app, @framework, @config) =>
      env.logger.info "maxcul: start init..."
      @serialPortName = config.serialPortName
      @baudrate = config.baudrate
      env.logger.info("maxcul: using serial device #{@serialPortName}@#{@baudrate}")
      env.logger.info "maxcul: done!"
      @comLayer = new CommunicationServiceLayer @baudrate, @serialPortName, @commandReceiveCallback
      @maxDriver = new MaxDriver config.homebaseAddress

    commandReceiveCallback: (cmdString) =>
      packet = @maxDriver.parseIncommingMessage(cmdString)
      if (packet)
        @maxDriver.handlePacket(packet)

    # This class represents the low level comminication interface
    class CommunicationServiceLayer
      @serialDeviceInstance

      constructor: (baudrate, serialPortName, @cmdReceiver) ->
        @cmd = ""
        env.logger.info "maxcul: try to open serialport..."
        @serialDeviceInstance = new SerialPort serialPortName, baudrate: baudrate, false

        @serialDeviceInstance.on 'data', (data) =>
          dataString = "#{data}"
          dataString = dataString.replace(/[\r]/g, '');
          env.logger.debug "maxcul: got data -> #{dataString}"
          # line feed ?
          if dataString.indexOf('\n') != -1
            parts = dataString.split '\n'
            @cmd = @cmd + parts[0]
            @cmdReceiver @cmd
            if ( parts.length > 0 )
              @cmd = parts[1]
            else
              @cmd = ''
          else
            @cmd = @cmd + dataString

        @serialDeviceInstance.open (err) =>
          if ( err? )
            env.logger.info "maxcul: opening serialPort #{serialPortName} failed #{err}"
          else
            env.logger.info "maxcul: serialPort #{serialPortName} is open!"
            env.logger.info "maxcul: Print Version of the CUL868"
            @serialDeviceInstance.write('V\n')
            env.logger.info "maxcul: enable MAX! Mode of the CUL868"
            # enable the receiving of MAX messages
            @serialDeviceInstance.write('Zr\n')

        @serialDeviceInstance.on 'error', (err) ->
           env.logger.error "maxcul: serialport communication error #{err}"

    class MaxDriver

      @baseAddress

      constructor: (baseAddress) ->
        @baseAddress = baseAddress

      decodeCmdId: (id) ->
        key = "cmd"+id
        @commandList =
          cmd00 : "PairPing"
          cmd01 : "PairPong"
          cmd02 : "Ack"
          cmd03 : "TimeInformation"
          cmd10 : "ConfigWeekProfile"
          cmd11 : "ConfigTemperatures"
          cmd12 : "ConfigValve"
          cmd20 : "AddLinkPartner"
          cmd21 : "RemoveLinkPartner"
          cmd22 : "SetGroupId"
          cmd23 : "RemoveGroupId"
          cmd30 : "ShutterContactState"
          cmd40 : "SetTemperature"
          cmd42 : "WallThermostatControl"
          cmd43 : "SetComfortTemperature"
          cmd44 : "SetEcoTemperature"
          cmd50 : "PushButtonState"
          cmd60 : "ThermostatState"
          cmd70 : "WallThermostatState"
          cmd82 : "SetDisplayActualTemperature"
          cmdF1 : "WakeUp"
          cmdF0 : "Reset"
        return if key of @commandList then @commandList[key] else false

      parseIncommingMessage: (message) ->
        env.logger.debug "maxcul: Decoding Message #{message}"

        data = message.split(/Z(..)(..)(..)(..)(......)(......)(..)(.*)/);
        data.shift() # Removes first element from array.

        if ( data.length <= 1)
          env.logger.debug "maxcul: cannot split packet"
          return false

        #decode packet length
        packet =
          length: parseInt(data[0],16) #convert hex to decimal

        #Check Message length
        #We get a HEX Message from the CUL so we have 2 Digits per Byte
        # -> lengthfield from the packet * 2
        # We also have a trailing 'Z' -> + 1
        # Because the length we get from the cul is calculatet for the whole packet
        # and the lengthfield is also hex so have to add two more digits for the calculation -> +2
        if (2 * packet.length + 3 != message.length)
          #Error
          env.logger.debug "maxcul: packet length missmatch"
          return false
        else
          env.logger.debug "maxcul: packet length ok"

        packet.msgCnt = parseInt(data[1],16)
        packet.msgFlag = parseInt(data[2],16)
        packet.msgTypeRaw = data[3]
        packet.decodedCmd = @decodeCmdId(data[3])
        packet.src = data[4].toLowerCase()
        packet.dest = data[5].toLowerCase()
        packet.groupid = parseInt(data[6],16)
        packet.forMe = if @baseAddress == packet.dest then true else false
        packet.rawPayload = data[7]
        return packet


      handlePacket: (packet) ->
        console.log(packet)




  maxculPlugin = new MaxculPlugin
  return maxculPlugin
