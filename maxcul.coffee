module.exports = (env) ->

  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  Moment = env.require 'moment'
  {EventEmitter} = require 'events'
  HiPack = require 'hipack'
  BitArray = require 'bit-array'

  serialport = require 'serialport'
  SerialPort = serialport.SerialPort

  class MaxculPlugin extends env.plugins.Plugin

    #Holds the communication layer instance
    @comLayer

    #Hold the MAX Driver Service Class instance
    @maxDriver
    @availableDevices

    init: (app, @framework, @config) =>
      serialPortName = config.serialPortName
      baudrate = config.baudrate
      baseAddress = config.homebaseAddress

      deviceConfigDef = require("./maxcul-device-config-schema")
      deviceTypeClasseNames = [
        MaxculShutterContact,
        MaxculHeatingThermostat
      ]

      @comLayer = new CommunicationServiceLayer baudrate, serialPortName, @commandReceiveCallback
      @maxDriver = new MaxDriver baseAddress, @comLayer
      @availableDevices = []

      for DeviceClass in deviceTypeClasseNames
        do (DeviceClass) =>
          @framework.deviceManager.registerDeviceClass(DeviceClass.name, {
            configDef: deviceConfigDef[DeviceClass.name]
            createCallback: (deviceConfig,lastState) =>
              device = new DeviceClass(deviceConfig,lastState, @maxDriver)
              @availableDevices.push device
              return device
          })

    commandReceiveCallback: (cmdString) =>
      @maxDriver.handleIncommingMessage(cmdString)

    # This class represents the low level comminication interface
    class CommunicationServiceLayer
      @_serialDeviceInstance
      @_messageQueue = []
      @_current
      @_busy = false

      constructor: (baudrate, serialPortName, @cmdReceiver) ->
        env.logger.info("using serial device #{serialPortName}@#{baudrate}")
        env.logger.info "trying to open serialport..."
        @_serialDeviceInstance = new SerialPort serialPortName,
          {
            baudrate: baudrate,
            parser: serialport.parsers.readline("\n")
          },
          false

        @_serialDeviceInstance.on 'data', (data) =>
          dataString = "#{data}"
          dataString = dataString.replace(/[\r]/g, '')
          env.logger.debug "got data -> #{dataString}"
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
            @_serialDeviceInstance.write('Zr\n')

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


    class MaxDriver extends EventEmitter

      @baseAddress
      @comLayer
      @deviceTypes = [
        "Cube",
        "HeatingThermostat",
        "HeatingThermostatPlus",
        "WallMountedThermostat",
        "ShutterContact",
        "PushButton"
      ]
      @_waitingForReplyQueue = []
      @msgCount

      constructor: (baseAddress,comLayer) ->
        @baseAddress = baseAddress
        @comLayer = comLayer
        @msgCount = 0

        setTimeout( =>
          @.emit('checkTimeIntervalFired')
        , 1000 * 60 * 60
        )

      decodeCmdId: (id) ->
        key = "cmd"+id
        @commandList =
          cmd00 : {
            functionName : "PairPing"
            id : "00"
          }
          cmd01 : {
            functionName : "PairPong"
            id : "01"
          }
          cmd02 : {
            functionName : "Ack"
            id : "02"
          }
          cmd03 : {
            functionName : "TimeInformation"
            id : "03"
          }
          cmd10 : "ConfigWeekProfile"
          cmd11 : "ConfigTemperatures"
          cmd12 : "ConfigValve"
          cmd20 : "AddLinkPartner"
          cmd21 : "RemoveLinkPartner"
          cmd22 : "SetGroupId"
          cmd23 : "RemoveGroupId"
          cmd30 : {
            functionName : "ShutterContactState"
            id : "30"
          }
          cmd40 : "SetTemperature"
          cmd42 : "WallThermostatControl"
          cmd43 : "SetComfortTemperature"
          cmd44 : "SetEcoTemperature"
          cmd50 : "PushButtonState"
          cmd60 : {
            functionName : "ThermostatState"
            id : 60
          }
          cmd70 : "WallThermostatState"
          cmd82 : "SetDisplayActualTemperature"
          cmdF1 : "WakeUp"
          cmdF0 : "Reset"
        return if key of @commandList then @commandList[key]['functionName'] else false

      handleIncommingMessage: (message) ->
        packet = @parseIncommingMessage(message)
        if (packet)
          if ( packet.decodedCmd )
            @[packet.decodedCmd](packet)
          else
            env.logger.debug "received unknown command id #{packet.msgTypeRaw}"
        else
          env.logger.debug "message was no valid MAX paket."

      parseIncommingMessage: (message) ->
        env.logger.debug "decoding Message #{message}"
        message = message.replace(/\n/, '')
        message = message.replace(/\r/, '')
        data = message.split(/Z(..)(..)(..)(..)(......)(......)(..)(.*)/)
        data.shift() # Removes first element from array, it is the 'Z'.

        if ( data.length <= 1)
          env.logger.debug "cannot split packet"
          return false

        # Decode packet length
        packet =
          length: parseInt(data[0],16) #convert hex to decimal

        # Check Message length
        # We get a HEX Message from the CUL, so we have 2 Digits per Byte
        # -> lengthfield from the packet * 2
        # We also have a trailing 'Z' -> + 1
        # Because the length we get from the cul is calculated for the whole packet
        # and the length field is also hex we have to add two more digits for the calculation -> +2
        if (2 * packet.length + 3 != message.length)
          env.logger.debug "packet length missmatch"
          return false

        packet.msgCnt = parseInt(data[1],16)
        packet.msgFlag = parseInt(data[2],16)
        packet.groupid = parseInt(data[6],16)
        packet.msgTypeRaw = data[3]
        packet.src = data[4].toLowerCase()
        packet.dest = data[5].toLowerCase()
        packet.rawPayload = data[7]
        packet.forMe = if @baseAddress == packet.dest then true else false
        packet.decodedCmd = @decodeCmdId(data[3])

        return packet

      sendMsg: (cmdId,src,dest,payload,groupId,flags) =>
        @msgCount = @msgCount + 1
        temp = HiPack.unpack("H*",HiPack.pack("C",@msgCount))
        data = temp[1]+flags+cmdId+src+dest+groupId+payload
        length = data.length/2
        length = HiPack.unpack("H*",HiPack.pack("C",length))
        @comLayer.serialWrite(length[1]+data)
        console.log(cmdId,src,dest,payload,groupId,flags)

      generateTimePayload: () ->
        now = Moment()
        prep =
          sec   : now.seconds()
          min   : now.minutes()
          hour  : now.hours()
          day   : now.date()
          month : now.month() + 1
          year  : now.diff('2000-01-01', 'years'); #Years since 2000

        prep.compressedOne = prep.min | ((prep.month & 0x0C) << 4)
        prep.compressedTwo = prep.sec | ((prep.month & 0x03) << 6)

        payload = HiPack.unpack("H*",
          HiPack.pack("CCCCC",prep.year,prep.day,prep.hour,prep.compressedOne,prep.compressedTwo)
        )
        return payload[1];

      sendTimeInformation: (dest) ->
        payload = @generateTimePayload()
        @sendMsg("03",@baseAddress,dest,payload,"00","04");

      sendDesiredTemperature: (dest,temperature,mode) ->
        modeBin = switch mode
          when 'auto'
            '00'
          when 'manu'
            '01'
          when 'boost'
            '11'
        if mode is 'auto' and (typeof temperature is "undefined" or temperature is null)
          payloadHex = "00"
          @sendMsg("40",@baseAddress,dest,payloadHex,"00","04");
        else
          if temperature >= 4.5 and temperature <= 30.5
            # Multiply the temperature with 2 to remove eventually supplied 0.5 and convert to
            # binary
            # We can't get a value smaller than 4.5 (0FF) and
            # higher as 30.5 (ON)(see the specifications of the system)
            # example: 30.5 degrees * 2 = 61
            # example: 3 degrees * 2 = 6
            temperature = (temperature * 2).toString(2)
            # Fill the value with zeros so that we allways get 6 bites
            # example: 61 =  0011 1101 => 000000 00111101 => 111101
            # example: 6 =  0110 => 000000 0110 => 000110
            temperatureBinary =  ("000000" + temperature).substr(-6);
            # Add the mode at the position of the removed bits
            # example: Mode temporary 11 => 11 111101
            # example: Mode manuel 01 => 01 000110
            payloadBinary = modeBin + temperatureBinary
            # convert the binary payload to hex
            payloadHex = parseInt(payloadBinary, 2).toString(16);
            @sendMsg("40",@baseAddress,dest,payloadHex,"00","04");
          else
            #TODO: THROW ERROR

        #else if temperature == 'eco'
        #else if temperature == 'boost'
        #else if temperature == 'comfort'
        #

      parseTemperature: (temperature) ->
        if temperature == 'on'
          return 30.5
        else if temperature == 'off'
          return 4.5
        else return temperature

      PairPing: (packet) ->
        env.logger.debug "handling PairPing packet"
        packet.decodedPayload = HiPack.unpack("Cfirmware/Ctype/Ctest/a*serial",HiPack.pack("H*",packet.rawPayload))

        if (packet.dest != "000000" && packet.forMe != true)
          #Pairing Command is not for us
          env.logger.debug "handled PairPing packet is not for us"
          return
        else if ( packet.forMe ) #The device only wants to repair
          env.logger.debug "beginn repairing with device #{packet.src}"
          @sendMsg("01",@baseAddress,packet.src,"00","00","00")
        else if ( packet.dest == "000000" ) #The device is new and needs a full pair
          #@TODO we need a global pairMode switch in the UI that should auto disable after a few minutes
          #check the device type, eventually we need to send information to the device
          env.logger.debug "beginn pairing of a new device with deviceId #{packet.src}"
          @sendMsg("01",@baseAddress,packet.src,"00","00","00")

      Ack: (packet) ->
        temp = HiPack.unpack("C",HiPack.pack("H*",packet.rawPayload))
        packet.decodedPayload = temp[1]
        if( packet.decodedPayload == 1 )
          env.logger.debug "got OK-ACK Packet from #{packet.src}"
        else
          env.logger.debug "got ACK Error (Invalid command/argument) from #{packet.src} with payload #{packet.decodedPayload}"

      ShutterContactState: (packet) ->
        rawData = new BitArray(8,packet.rawPayload)
        packet.data =
          rawBits: rawData
          isOpen : rawData.get(1)
          rfError :rawData.get(6)
          batteryLow :rawData.get(7)
        env.logger.debug "got data from shutter constact #{packet.src} #{packet.data.rawBits.toString()}"
        @.emit('ShutterContactStateRecieved',packet)

      ThermostatState: (packet) ->
        temp = HiPack.unpack("aCCCCC",HiPack.pack("H*",packet.rawPayload));
        console.log(temp,packet)

      TimeInformation: (packet) ->
        env.logger.debug "got time information request from device #{packet.src}"
        @.emit('deviceRequestTimeInformation',packet.src)
        console.log(packet)

    # Class that represents a MAX! HeatingThermostat
    class MaxculHeatingThermostat extends env.devices.HeatingThermostat

      _decalcDays: ["Sat","Sun","Mon","Tue","Wed","Thu","Fri"]
      _boostDurations: [0,5,10,15,20,25,30,60]

      _maxDriver: undefined
      _deviceId : "000000"
      _timeInformationHour : ""

      extendetAttributes: []

      constructor: (@config,lastState, @maxDriver) ->
        @id = @config.id
        @name = @config.name
        @_deviceId = @config.deviceId.toLowerCase()
        @_mode = lastState?.mode?.value or "auto"
        @_battery = lastState?.battery?.value or "ok"
        @_temperatureSetpoint = lastState?.temperatureSetpoint?.value
        @_lastSendTime = 0

        for Attribute in @extendetAttributes
          do (Attribute) =>
            @addAttribute(Attribute.name,Attribute.settings)

        @maxDriver.on('checkTimeIntervalFired', () =>
          @_updateTimeInformation()
        )

        @maxDriver.on('deviceRequestTimeInformation',(device) =>
          if device == @_deviceId
            @_updateTimeInformation()
        )

        super()

      _updateTimeInformation: () ->
        env.logger.debug "Updating time information for deviceId #{@_deviceId}"
        @maxDriver.sendTimeInformation(@_deviceId)

      changeModeTo: (mode) ->
        console.log(mode)
        if @_mode is mode then return
        temperatureSetpoint = @_temperatureSetpoint
        if mode is "auto"
          temperatureSetpoint = null

        return @maxDriver.sendDesiredTemperature(@_deviceId, temperatureSetpoint, mode)

      changeTemperatureTo: (temperatureSetpoint) ->
        if @_temperatureSetpoint is temperatureSetpoint then return
        env.logger.debug "Set desired temperature #{temperatureSetpoint} for deviceId #{@_deviceId}"
        #@maxDriver.sendDesiredTemperature(@_deviceId, temperatureSetpoint, @_mode)

      getEcoTemperature: () -> Promise.resolve(@_ecoTemperature)
      getComfortTemperature: () -> Promise.resolve(@_comfortTemperature)


    # Class that represents a MAX! ShutterContact
    class MaxculShutterContact extends env.devices.ContactSensor

      _battery: undefined

      @deviceId = "000000"
      @rfError = 0
      @associatedDevices = ""
      @paired = 0

      constructor: (@config, lastState, @maxDriver) ->
        @id = config.id
        @name = config.name
        @deviceId = config.deviceId.toLowerCase()
        @_contact = lastState?.contact?.value
        @_battery = lastState?.battery?.value

        @addAttribute(
          'battery',
          {
            description: "state of the battery"
            type: "boolean"
            labels: ['niedrig', 'ok']
            acronym: "Batterie"
          }
        )

        @maxDriver.on('ShutterContactStateRecieved',(packet) =>
          if(@deviceId == packet.src)
            #TODO: WE NEED TO GIVE BACK A STATE IF THE PACKET WAS HANDLED
            console.log(packet.data)
            # If the window is open the isOpen field is true the contact is open = false
            @_setContact(if packet.data.isOpen then false else true)
            @_setBattery(packet.data.batteryLow)
            env.logger.debug "ShutterContact with deviceId #{@deviceId} updated"
        )
        super()

      getBattery:() -> Promise.resolve(@_battery)

      _setBattery: (value) ->
        if @_battery is value then return
        @_battery = value
        @emit 'battery', value

      handleReceivedCmd: (command) ->
        console.log(Cmd)

  maxculPlugin = new MaxculPlugin
  return maxculPlugin
