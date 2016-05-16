module.exports = (env) ->

  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  Moment = env.require 'moment'
  {EventEmitter} = require 'events'
  HiPack = require 'hipack'
  BitSet = require 'bitset.js'

  CommunicationServiceLayer = require('./communication-layer')(env)
  MaxDriver = require('./max-driver')(env)

  class MaxculPlugin extends env.plugins.Plugin

    #Holds the communication layer instance
    @comLayer

    #Hold the MAX Driver Service Class instance
    @maxDriver

    #Holds the device objects
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

      @comLayer = new CommunicationServiceLayer baudrate, serialPortName, @commandReceiveCallback, baseAddress
      @maxDriver = new MaxDriver baseAddress, @comLayer, config.enablePairMode
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

      # wait till all plugins are loaded
      @framework.on "after init", =>
        # Check if the mobile-frontent was loaded and get a instance
        mobileFrontend = @framework.pluginManager.getPlugin 'mobile-frontend'
        if mobileFrontend?
          mobileFrontend.registerAssetFile 'js', "pimatic-maxcul/app/js/index.coffee"
          mobileFrontend.registerAssetFile 'css', "pimatic-maxcul/app/css/maxcul.css"
          mobileFrontend.registerAssetFile 'html', "pimatic-maxcul/app/views/maxcul-heating-thermostat.jade"
          env.logger.debug "templates loaded"
        else
          env.logger.warn "maxcul could not find the mobile-frontend. No gui will be available"

    commandReceiveCallback: (cmdString) =>
      @maxDriver.handleIncommingMessage(cmdString)


    # Class that represents a MAX! HeatingThermostat
    class MaxculHeatingThermostat extends env.devices.HeatingThermostat

      _decalcDays: ["Sat","Sun","Mon","Tue","Wed","Thu","Fri"]
      _modes: ["auto", "manu", "temporary", "boost"]
      _boostDurations: [0,5,10,15,20,25,30,60]

      _maxDriver: undefined
      _deviceId : "000000"
      _timeInformationHour : ""

      _comfortTemperature : 21
      _ecoTemperature : 17
      _minimumTemperature : 4.5
      _maximumTemperature : 30.5
      _measurementOffset : 0
      _windowOpenTime : 30
      _windowOpenTemperature : 4.5

      template: "maxcul-heating-thermostat"

      _measuredTemperature = 0
      extendetAttributes:[
        {
          name: 'measuredTemperature'
          settings:
            label: "Measured Temperature"
            description: "The temp that the device has measured"
            type: "number"
            acronym: "T"
            unit: "°C"
        }
      ]

      constructor: (@config,lastState, @maxDriver) ->
        @id = @config.id
        @name = @config.name
        @_deviceId = @config.deviceId.toLowerCase()
        @_mode = lastState?.mode?.value or "auto"
        @_battery = lastState?.battery?.value or "ok"
        @_temperatureSetpoint = lastState?.temperatureSetpoint?.value or 17
        @_measuredTemperature = lastState?.measuredTemperature?.value
        @_lastSendTime = 0

        @_comfortTemperature = @config.comfyTemp
        @_ecoTemperature = @config.ecoTemp
        @_minimumTemperature = @config.minimumTemperature
        @_maximumTemperature = @config.maximumTemperature
        @_measurementOffset = @config.measurementOffset
        @_windowOpenTime = @config.windowOpenTime
        @_windowOpenTemperature = @config.windowOpenTemperature

        @actions['transferConfigToDevice'] =
          params:{}

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

        @maxDriver.on('ThermostatStateRecieved',(packet) =>
          if(@_deviceId == packet.src)
            @_setBattery(packet.data.batterylow)
            @_setMode(@_modes[packet.data.mode])
            @_setSetpoint(packet.data.desiredTemperature)
            if( packet.data.measuredTemperature != 0)
              @_setMeasuredTemperature(packet.data.measuredTemperature)

        )
        super()

      _setMeasuredTemperature: (measuredTemperature) ->
        if @_measuredTemperature is measuredTemperature then return
        @_measuredTemperature = measuredTemperature
        @emit 'measuredTemperature', measuredTemperature

      _setBattery: (value) ->
        if @_battery is value then return
        @_battery = value
        @emit 'battery', value

      _updateTimeInformation: () ->
        env.logger.debug "Updating time information for deviceId #{@_deviceId}"
        @maxDriver.sendTimeInformation(@_deviceId)

      changeModeTo: (mode) ->
        if @_mode is mode then return Promise.resolve true

        if mode is "auto"
          temperatureSetpoint = null
        else
          temperatureSetpoint = @_temperatureSetpoint
          env.logger.debug "Set desired mode to #{mode} for deviceId #{@_deviceId}"
        return @maxDriver.sendDesiredTemperature(@_deviceId, temperatureSetpoint, mode, "00").then ( =>
          @_lastSendTime = new Date().getTime()
          @_setMode(mode)
          @_setSetpoint(temperatureSetpoint)
        )

      changeTemperatureTo: (temperatureSetpoint) ->
        if @_temperatureSetpoint is temperatureSetpoint then return Promise.resolve true
        env.logger.debug "Set desired temperature #{temperatureSetpoint} for deviceId #{@_deviceId}"
        return @maxDriver.sendDesiredTemperature(@_deviceId, temperatureSetpoint, @_mode, "00").then( =>
          @_lastSendTime = new Date().getTime()
          @_setSynced(false)
          @_setSetpoint(temperatureSetpoint)
        )

      transferConfigToDevice: () ->
        env.logger.info "transfer config to device #{@_deviceId}"
        return @maxDriver.sendConfig(
            @_deviceId,
            @_comfortTemperature,
            @_ecoTemperature,
            @_minimumTemperature,
            @_maximumTemperature,
            @_measurementOffset,
            @_windowOpenTime,
            @_windowOpenTemperature
          )

      getEcoTemperature: () -> Promise.resolve(@_ecoTemperature)
      getComfortTemperature: () -> Promise.resolve(@_comfortTemperature)
      getMeasuredTemperature: () -> Promise.resolve(@_measuredTemperature)

      getTemplateName: -> "maxcul-heating-thermostat"

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
            labels: ['low', 'ok']
            acronym: "Bat."
          }
        )

        @maxDriver.on('ShutterContactStateRecieved',(packet) =>
          if(@deviceId == packet.src)
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

  maxculPlugin = new MaxculPlugin
  return maxculPlugin
