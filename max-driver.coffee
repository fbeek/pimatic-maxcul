module.exports = (env) ->

  {EventEmitter} = require 'events'
  BitSet = require 'bitset.js'
  Promise = env.require 'bluebird'
  Moment = env.require 'moment'
  Sprintf = require("sprintf-js").sprintf
  BinaryParser = require("binary-parser").Parser

  CommunicationServiceLayer = require('./communication-layer')(env)
  CulPacket = require('./culpacket')(env)

  class MaxDriver extends EventEmitter

    #Holds the the base station adress
    @baseAddress
    #Holds the instance of the communication-layer
    @comLayer

    #Supportet device types
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
    @pairModeEnabled

    constructor: (baseAddress, pairModeEnabled, serialPortName, baudrate) ->
      @baseAddress = baseAddress
      @msgCount = 0
      @pairModeEnabled = pairModeEnabled

      @comLayer = new CommunicationServiceLayer(baudrate, serialPortName, @baseAddress)
      @comLayer.on("culDataReceived", (data) =>
        @handleIncommingMessage(data)
      )

      @comLayer.on('culFirmwareVersion', (data) =>
        env.logger.info "CUL FW Version: #{data}"
      )

      setInterval( =>
        @.emit('checkTimeIntervalFired')
      , 1000 * 60 * 60
      )

    connect: () ->
      return @comLayer.connect()

    disconnect: ->
      return @comLayer.disconnect()

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
        cmd12 : "ConfigValve" #use for boost duration
        cmd20 : "AddLinkPartner"
        cmd21 : "RemoveLinkPartner"
        cmd22 : "SetGroupId"
        cmd23 : "RemoveGroupId"
        cmd30 : {
          functionName : "ShutterContactState"
          id : "30"
        }
        cmd40 : {
          functionName : "WallThermostatSetTemp"
          id : "40"
        }
        cmd42 : {
          functionName : "WallThermostatControl"
          id : "42"
        }
        cmd43 : "SetComfortTemperature"
        cmd44 : "SetEcoTemperature"
        cmd50 : {
          functionName : "PushButtonState"
          id : "50"
        }
        cmd60 : {
          functionName : "ThermostatState"
          id : 60
        }
        cmd70 : {
          functionName : "WallThermostatState"
          id : 70
        }
        cmd82 : "SetDisplayActualTemperature"
        cmdF1 : "WakeUp"
        cmdF0 : "Reset"
      return if key of @commandList then @commandList[key]['functionName'] else false

    handleIncommingMessage: (message) ->
      packet = @parseIncommingMessage(message)
      if (packet)
        if (packet.getSource() == @baseAddress)
          env.logger.debug "ignored auto-ack packet"
        else
          if ( packet.getCommand() )
            try
              @[packet.getCommand()](packet)
            catch error
              env.logger.info "Error in handleIncommingMessage Function, command : #{packet.getCommand()}, error: #{error}"
          else
            env.logger.debug "received unknown command id #{packet.getRawType()}"
      else
        env.logger.debug "message was no valid MAX! paket."

    parseIncommingMessage: (message) ->
      env.logger.debug "decoding Message #{message}"
      message = message.replace(/\n/, '')
      message = message.replace(/\r/, '')

      rssi = parseInt(message.slice(-2), 16)
      if rssi >= 128
        rssi = (rssi - 256) / 2 - 74
      else
        rssi = rssi / 2 - 74
      env.logger.debug "RSSI for Message : #{rssi}"

      # remove rssi value from message string
      message = message.substring(0, message.length - 2);

      data = message.split(/Z(..)(..)(..)(..)(......)(......)(..)(.*)/)
      data.shift() # Removes first element from array, it is the 'Z'.

      if ( data.length <= 1)
        env.logger.debug "cannot split packet"
        return false

      packet = new CulPacket()
      # Decode packet length
      packet.setLength(parseInt(data[0],16)) #convert hex to decimal

      # Check Message length
      # We get a HEX Message from the CUL, so we have 2 Digits per Byte
      # -> lengthfield from the packet * 2
      # We also have a trailing 'Z' -> + 1
      # Because the length we get from the cul is calculated for the whole packet
      # and the length field is also hex we have to add two more digits for the calculation -> +2
      if (2 * packet.getLength() + 3 != message.length)
        env.logger.debug "packet length missmatch"
        return false

      packet.setMessageCount(parseInt(data[1],16))
      packet.setFlag(parseInt(data[2],16))
      packet.setGroupId(parseInt(data[6],16))
      packet.setRawType(data[3])
      packet.setSource(data[4])
      packet.setDest(data[5])
      packet.setRawPayload(data[7])

      if @baseAddress == packet.getDest()
        packet.setForMe(true)
      else
        packet.setForMe(false)

      packet.setCommand(@decodeCmdId(data[3]))
      packet.setStatus('incomming')
      return packet

    sendMsg: (cmdId, src, dest, payload, groupId, flags, deviceType) =>
      packet = new CulPacket()
      packet.setCommand(cmdId)
      packet.setSource(src)
      packet.setDest(dest)
      packet.setRawPayload(payload)
      packet.setGroupId(groupId)
      packet.setFlag(flags)
      packet.setMessageCount(@msgCount + 1)
      packet.setRawType(deviceType)

      temp =  Sprintf('%02x',packet.getMessageCount())
      data = temp+flags+cmdId+src+dest+groupId+payload
      length = data.length/2
      length = Sprintf('%02x',length)

      packet.setRawPacket(length+data)

      return new Promise( (resolve, reject) =>
        packet.resolve = resolve
        packet.reject = reject
        @comLayer.addPacketToTransportQueue(packet)
      )

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

      payload =  Sprintf('%02x',prep.year) +   Sprintf('%02x',prep.day) + Sprintf('%02x',prep.hour) +  Sprintf('%02x',prep.compressedOne) +  Sprintf('%02x',prep.compressedTwo)
      return payload;

    sendTimeInformation: (dest, deviceType) ->
      payload = @generateTimePayload()
      @sendMsg("03",@baseAddress,dest,payload,"00","04",deviceType);

    sendGroup: (dest, groupId, deviceType) ->
<<<<<<< HEAD
      @sendMsg("22",@baseAddress,dest,groupId,"00","00",deviceType);

    sendPair: (dest, pairId, pairTyp, deviceType) ->
      payload = Sprintf('%s%02x',pairId,pairTyp)
      env.logger.debug "send Pair packet #{payload} "
      @sendMsg("20",@baseAddress,dest,payload,"00","00",deviceType);
=======
      payload = Sprintf('%02x', groupId)
      @sendMsg("22",@baseAddress,dest,payload,"00","00",deviceType);

    sendPair: (dest, pairId, deviceType) ->
      @sendMsg("20",@baseAddress,dest,pairId,"00","00",deviceType);
>>>>>>> 115f3a030020738f8744f2d1492d7f768c6763fe

    sendConfig: (dest,comfortTemperature,ecoTemperature,minimumTemperature,maximumTemperature,offset,windowOpenTime,windowOpenTemperature,deviceType) ->
      comfortTemperatureValue = Sprintf('%02x',(comfortTemperature*2))
      ecoTemperatureValue = Sprintf('%02x',(ecoTemperature*2))
      minimumTemperatureValue = Sprintf('%02x',(minimumTemperature*2))
      maximumTemperaturenValue = Sprintf('%02x',(maximumTemperature*2))
      offsetValue = Sprintf('%02x',((offset + 3.5)*2))
      windowOpenTempValue = Sprintf('%02x',(windowOpenTemperature*2))
      windowOpenTimeValue = Sprintf('%02x',(Math.ceil(windowOpenTime/5)))

      payload = comfortTemperatureValue+ecoTemperatureValue+maximumTemperaturenValue+minimumTemperatureValue+offsetValue+windowOpenTempValue+windowOpenTimeValue
      @sendMsg("11",@baseAddress,dest,payload,"00","00",deviceType)
      return Promise.resolve true

    sendDesiredTemperature: (dest,temperature,mode,groupId,deviceType) ->
      modeBin = switch mode
        when 'auto'
          '00'
        when 'manu'
          '01'
        when 'boost'
          '11'
      if temperature <= 4.5
        temperature = 4.5
      if temperature >= 30.5
        temperature = 30.5

      if mode is 'auto' and (typeof temperature is "undefined" or temperature is null)
        payloadHex = "00"
      else
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
        payloadHex = Sprintf('%02x',(parseInt(payloadBinary, 2)))
      #if a  groupid is given we set the flag to 04 to switch all devices in this group
      if groupId == "00"
        return @sendMsg("40",@baseAddress,dest,payloadHex,"00","00",deviceType);
      else
        return @sendMsg("40",@baseAddress,dest,payloadHex,groupId,"04",deviceType);

      #return Promise.resolve true

    parseTemperature: (temperature) ->
      if temperature == 'on'
        return 30.5
      else if temperature == 'off'
        return 4.5
      else return temperature

    PairPing: (packet) ->
      env.logger.debug "handling PairPing packet"
      if(@pairModeEnabled)
        payloadBuffer = new Buffer(packet.getRawPayload(), 'hex')
        payloadParser = new BinaryParser().uint8('firmware').uint8('type').uint8('test')
        temp = payloadParser.parse(payloadBuffer)
        packet.setDecodedPayload(temp)
        if (packet.getDest() != "000000" && packet.getForMe() != true)
          #Pairing Command is not for us
          env.logger.debug "handled PairPing packet is not for us"
          return
        else if ( packet.getForMe() ) #The device only wants to repair
          env.logger.debug "beginn repairing with device #{packet.getSource()}"
          @sendMsg("01", @baseAddress, packet.getSource(), "00", "00", "00", "")
        else if ( packet.getDest() == "000000" ) #The device is new and needs a full pair
          env.logger.debug "beginn pairing of a new device with deviceId #{packet.getSource()}"
          @sendMsg("01", @baseAddress, packet.getSource(), "00", "00", "00", "")
      else
          env.logger.debug ", but pairing is disabled so ignore"

    Ack: (packet) ->
      payloadBuffer = new Buffer(packet.getRawPayload(),'hex');
      payloadParser = new BinaryParser().uint8('state')
      temp = payloadParser.parse(payloadBuffer)
      packet.setDecodedPayload( temp.state )
      if( packet.getDecodedPayload() == 1 )
        env.logger.debug "got OK-ACK Packet from #{packet.getSource()}"
        @comLayer.ackPacket()
      else
        #????
        env.logger.debug "got ACK Error (Invalid command/argument) from #{packet.getSource()} with payload #{packet.getRawPayload()}"

    ShutterContactState: (packet) ->
      rawBitData = new BitSet('0x'+packet.getRawPayload())

      shutterContactState =
        src : packet.getSource()
        isOpen : rawBitData.get(1)
        rfError : rawBitData.get(6)
        batteryLow : rawBitData.get(7)

      env.logger.debug "got data from shutter contact #{packet.getSource()} #{rawBitData.toString()}"
      @.emit('ShutterContactStateRecieved',shutterContactState)

    PushButtonState: (packet) ->
      rawBitData = new BitSet('0x'+packet.getRawPayload())

      pushButtonState =
        src : packet.getSource()
        isOpen : rawBitData.get(0)
        rfError : rawBitData.get(6)
        batteryLow : rawBitData.get(7)

      env.logger.debug "got data from push button #{packet.getSource()} #{rawBitData.toString()}"
      @.emit('PushButtonStateRecieved',pushButtonState)


    WallThermostatState: (packet) ->
      env.logger.debug "got data from wallthermostat state #{packet.getSource()} with payload #{packet.getRawPayload()}"

      rawPayload = packet.getRawPayload()

      if( rawPayload.length >= 10)
        rawPayloadBuffer = new Buffer(rawPayload, 'hex')

        payloadParser = new BinaryParser().uint8('bits').uint8('displaymode').uint8('desiredRaw').uint8('null1').uint8('heaterTemperature')

        rawData = payloadParser.parse(rawPayloadBuffer)

        rawBitData = new BitSet(rawData.bits);

        WallthermostatState =
          src : packet.getSource()
          mode : rawBitData.getRange(0,1)
<<<<<<< HEAD
          desiredTemperature : (('0x'+(packet.getRawPayload().substr(4,2))) & 0x7F) / 2.0
=======
          desiredTemperature : ('0x'+(packet.getRawPayload().substr(4,2))) & 0x7F) / 2.0
>>>>>>> 115f3a030020738f8744f2d1492d7f768c6763fe
          measuredTemperature : 0
          dstSetting : rawBitData.get(3)
          langateway : rawBitData.get(4)
          panel : rawBitData.get(5)
          rferror : rawBitData.get(6)
          batterylow : rawBitData.get(7)

    WallThermostatControl: (packet) ->
      rawBitData = new BitSet('0x'+packet.getRawPayload())
      desiredRaw = '0x'+(packet.getRawPayload().substr(0,2))
      measuredRaw = '0x'+(packet.getRawPayload().substr(2,2))
      desired = (desiredRaw & 0x7F) / 2.0
<<<<<<< HEAD
      measured = ((((desiredRaw & 0x80)*1)<<1) | (measuredRaw)*1) / 10.0

      env.logger.debug "got data from wallthermostat #{packet.getSource()} desired temp: #{desired} - measured temp: #{measured}"
=======
      measured = ((((desiredRaw & 0x80)*1)<<1) | (measuredRaw)*1)
      env.logger.debug parseInt(measured) / 10
>>>>>>> 115f3a030020738f8744f2d1492d7f768c6763fe

      WallThermostatControl =
        src : packet.getSource()
        desired : desired
        measured : measured
<<<<<<< HEAD
      @.emit('WallThermostatControlRecieved',WallThermostatControl)
=======
      @.emit('WallThermostatControlRecieved',wallSetTemp)

      env.logger.debug "got data from wallthermostat #{packet.getSource()} desired temp: #{desired} - measured temp: #{measured}"
>>>>>>> 115f3a030020738f8744f2d1492d7f768c6763fe

    WallThermostatSetTemp: (packet) ->
      setTemp = ('0x'+packet.getRawPayload() & 0x3f) / 2.0
      mode = ('0x'+packet.getRawPayload())>>6

<<<<<<< HEAD
      env.logger.debug "got data from wallthermostat #{packet.getSource()} set new temp #{setTemp} mode #{mode}"

=======
>>>>>>> 115f3a030020738f8744f2d1492d7f768c6763fe
      wallSetTemp =
        src : packet.getSource()
        mode : mode
        temp : setTemp
      @.emit('WallThermostatSetTempRecieved',wallSetTemp)

<<<<<<< HEAD
=======
      env.logger.debug "got data from wallthermostat #{packet.getSource()} set new temp #{setTemp} mode #{mode}"

>>>>>>> 115f3a030020738f8744f2d1492d7f768c6763fe
    ThermostatState: (packet) ->
      env.logger.debug "got data from heatingelement #{packet.getSource()} with payload #{packet.getRawPayload()}"

      rawPayload = packet.getRawPayload()

      if( rawPayload.length >= 10)
        rawPayloadBuffer = new Buffer(rawPayload, 'hex')
        if( rawPayload.length == 10)
          payloadParser = new BinaryParser().uint8('bits').uint8('valvePosition').uint8('desiredTemp').uint8('untilOne').uint8('untilTwo')
        else
          payloadParser = new BinaryParser().uint8('bits').uint8('valvePosition').uint8('desiredTemp').uint8('untilOne').uint8('untilTwo').uint8('untilThree')

        rawData = payloadParser.parse(rawPayloadBuffer)

        rawBitData = new BitSet(rawData.bits);
        rawMode = rawBitData.getRange(0,1);
        #If the control mode is not "temporary", the cube sends the current (measured) temperature
        if( rawData.untilTwo && rawMode[0] != 2)
          calculatedMeasuredTemperature = (((rawData.untilOne &0x01)<<8) + rawData.untilTwo)/10;
        else
          calculatedMeasuredTemperature = 0;
        #Sometimes the HeatingThermostat sends us temperatures like 0.2 or 0.3 degree Celcius - ignore them
        if ( calculatedMeasuredTemperature != 0 && calculatedMeasuredTemperature < 1)
          calculatedMeasuredTemperature = 0
        untilString = "";

        if( rawData.untilThree && rawMode[0] == 2)
          timeData = ParseDateTime(rawData.untilOne,rawData.untilTwo,rawData.untilThree)
          untilString = timeData.dateString;
        #Todo: Implement offset handling

        thermostatState =
          src : packet.getSource()
          mode : rawMode[0]
          desiredTemperature : (rawData.desiredTemp&0x7F)/2.0
          valvePosition : rawData.valvePosition
          measuredTemperature : calculatedMeasuredTemperature
          dstSetting : rawBitData.get(3)
          langateway : rawBitData.get(4)
          panel : rawBitData.get(5)
          rferror : rawBitData.get(6)
          batterylow : rawBitData.get(7)
          untilString : untilString

        @.emit('ThermostatStateRecieved',thermostatState)
      else
        env.logger.debug "payload to short ?";

    TimeInformation: (packet) ->
      env.logger.debug "got time information request from device #{packet.getSource()}"
      @.emit('deviceRequestTimeInformation',packet.getSource())

    ParseDateTime: (byteOne,byteTwo,byteThree) ->
      timeData =
        day : byteOne & 0x1F
        month : ((byteTwo & 0xE0) >> 4) | (byteThree >> 7)
        year : byteTwo & 0x3F
        time : byteThree & 0x3F
        dateString : ""

      if (timeData.time%2)
        timeData.time = parseInt(time/2)+":30";
      else
        timeData.time = parseInt(time/2)+":00";

      timeData.dateString = timeData.day+'.'+timeData.month+'.'+timeData.year+' '+timeData.time
      return timeData;
