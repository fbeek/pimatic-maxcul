module.exports = (env) ->

  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  Moment = env.require 'moment'
  {EventEmitter} = require 'events'
  BitSet = require 'bitset.js'

  MaxDriver = require('./max-driver')(env)

  class MaxculPlugin extends env.plugins.Plugin

    #Hold the MAX Driver Service Class instance
    @maxDriver

    #Holds the device objects
    @availableDevices

    init: (app, @framework, @config) =>
      baseAddress = @config.homebaseAddress

      deviceConfigDef = require("./maxcul-device-config-schema")
      deviceTypeClasseNames = [
        MaxculShutterContact,
        MaxculFakeShutterContact,
        MaxculHeatingThermostat,
        MaxculPushButton,
        MaxculWallThermostat,
        MaxculFakeWallThermostat
      ]

      @maxDriver = new MaxDriver(baseAddress, @config.serialPortName, @config.baudrate)
      @maxDriver.connect()
      @availableDevices = []

      index = 0
      for DeviceClass in deviceTypeClasseNames
        do (DeviceClass) =>
          @framework.deviceManager.registerDeviceClass(DeviceClass.name, {
            configDef: deviceConfigDef[DeviceClass.name]
            createCallback: (deviceConfig,lastState) =>
              device = new DeviceClass(deviceConfig,lastState, @maxDriver, index)
              index = index + 1
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

      @framework.deviceManager.on 'discover', (eventData) =>
        @framework.deviceManager.discoverMessage 'pimatic-maxcul', "pairmode for 30 sec enabled"
        @maxDriver.enablePairMode()

    # Class that represents a MAX! HeatingThermostat
  class MaxculThermostat extends env.devices.HeatingThermostat

    @_decalcDays: ["Sat","Sun","Mon","Tue","Wed","Thu","Fri"]
    @_modes: ["auto", "manu", "temporary", "boost"]
    @_boostDurations: [0,5,10,15,20,25,30,60]

    _extendetAttributes:[
      {
        name: 'measuredTemperature'
        settings:
          label: "Measured Temperature"
          description: "The temp that the device has measured"
          type: "number"
          acronym: "T"
          unit: "°C"
      },
      {
        name: 'battery'
        settings:
          label: "Battery State"
          description: "state of the battery"
          type: "string"
          labels: ['low', 'ok']
          acronym: "Bat."
      }
    ]

    constructor: (@config, lastState, @maxDriver, index) ->
      @id = @config.id
      @_index = index
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

      @_groupId = @config.groupId.toLowerCase()
      @_pairIds = @config.pairIds

      @_timeInformationHour = ""

      @actions['transferConfigToDevice'] =
        params:{}

      for Attribute in @_extendetAttributes
        do (Attribute) =>
          @addAttribute(Attribute.name,Attribute.settings)

      @maxDriver.on('checkTimeIntervalFired', checkTimeIntervalFiredHandler = () =>
        @_updateTimeInformation()
      )

      @maxDriver.on('deviceRequestTimeInformation',deviceRequestTimeInformationHandlder = (device) =>
        if device == @_deviceId
          @_updateTimeInformation()
      )

      @on('destroy', () =>
        @maxDriver.removeListener('deviceRequestTimeInformation', deviceRequestTimeInformationHandlder)
        @maxDriver.removeListener('checkTimeIntervalFired', checkTimeIntervalFiredHandler)
        env.logger.debug "Thermostat #{@_deviceId} base handlers removed"
      )

      super()

    _setMeasuredTemperature: (measuredTemperature) ->
      if @_measuredTemperature is measuredTemperature then return
      @_measuredTemperature = measuredTemperature
      @emit 'measuredTemperature', measuredTemperature

    _setBattery: (value) ->
      if ( value == 0 )
        @_battery = "ok"
      else
        @_battery = "low"
      @emit 'battery', @_battery

    _updateTimeInformation: () ->
      env.logger.debug "Updating time information for deviceId #{@_deviceId}"
      @maxDriver.sendTimeInformation(@_deviceId,@constructor.deviceType)

    changeModeTo: (mode) ->
      if @_mode is mode then return Promise.resolve true

      if mode is "auto"
        temperatureSetpoint = null
      else
        temperatureSetpoint = @_temperatureSetpoint
        env.logger.debug "Set desired mode to #{mode} for deviceId #{@_deviceId}"

      @maxDriver.sendDesiredTemperature(@_deviceId, temperatureSetpoint, mode, @_groupId , @constructor.deviceType).then( =>
        @_lastSendTime = new Date().getTime()
        @_setMode(mode)
        @_setSetpoint(temperatureSetpoint)
        return Promise.resolve true
      ).catch ( (err) =>
         return Promise.reject err
      )

    changeTemperatureTo: (temperatureSetpoint) ->
      if @_temperatureSetpoint is temperatureSetpoint then return Promise.resolve true
      env.logger.debug "Set desired temperature #{temperatureSetpoint} for deviceId #{@_deviceId}"
      @maxDriver.sendDesiredTemperature(@_deviceId, temperatureSetpoint, @_mode, @_groupId , @constructor.deviceType).then( =>
        @_lastSendTime = new Date().getTime()
        @_setSynced(true)
        @_setSetpoint(temperatureSetpoint)
        return Promise.resolve true
      ).catch( (err) =>
        return Promise.reject err
      )

    transferConfigToDevice: () ->
      env.logger.info "transfer config to device #{@_deviceId}"
      for pid in @_pairIds
        if pid.pairId != "000000"
          @maxDriver.sendPair(@_deviceId,pid.pairId.toLowerCase(),pid.type,@constructor.deviceType)
          env.logger.info "send pairId #{pid.pairId} to device #{@_deviceId}"
      if @_groupId != "00"
        @maxDriver.sendGroup(@_deviceId,@_groupId,@constructor.deviceType)
        env.logger.info "send groupID #{@_groupId} to device #{@_deviceId}"

      return @maxDriver.sendConfig(
          @_deviceId,
          @_comfortTemperature,
          @_ecoTemperature,
          @_minimumTemperature,
          @_maximumTemperature,
          @_measurementOffset,
          @_windowOpenTime,
          @_windowOpenTemperature,
          @constructor.deviceType
        )

    getEcoTemperature: () -> Promise.resolve(@_ecoTemperature)
    getComfortTemperature: () -> Promise.resolve(@_comfortTemperature)
    getMeasuredTemperature: () -> Promise.resolve(@_measuredTemperature)

    # Class that represents a MAX! HeatingThermostat
  class MaxculHeatingThermostat extends MaxculThermostat

    @deviceType: "HeatingThermostat"
    template: "maxcul-heating-thermostat"

    constructor: (@config, lastState, @maxDriver, index) ->
      super(@config, lastState, @maxDriver, index)
      @_valve = lastState?.valve?.value

      @maxDriver.on('ThermostatStateRecieved', thermostatStateRecievedHandler = (thermostatState) =>
        if(@_deviceId == thermostatState.src)
          @_setBattery(thermostatState.batterylow)
          @_setMode(@constructor._modes[thermostatState.mode])
          @_setSetpoint(thermostatState.desiredTemperature)
          if( thermostatState.measuredTemperature != 0)
            @_setMeasuredTemperature(thermostatState.measuredTemperature)
          @_setValve(thermostatState.valvePosition)
      )

      @on('destroy', () =>
        @maxDriver.removeListener('ThermostatStateRecieved', thermostatStateRecievedHandler)
        env.logger.debug "Thermostat #{@_deviceId} extend handlers removed"
      )

    _setValve: (value) ->
      if @_valve is value then return
      @_valve = value
      @emit 'valve', value

    getTemplateName: -> "maxcul-heating-thermostat"

    destroy: ->
      env.logger.debug "Thermostat #{@_deviceId} destroyed"
      super()

  # Class that represents a MAX! ShutterContact
  class MaxculShutterContact extends env.devices.ContactSensor

    @deviceType = "ShutterContact"
    template: "maxcul-contact"

    constructor: (@config, lastState, @maxDriver, index) ->
      @id = @config.id
      @name = @config.name
      @_deviceId = @config.deviceId.toLowerCase()
      @_contact = lastState?.contact?.value
      @_battery = lastState?.battery?.value
      @_index = index
      @_groupId = @config.groupId.toLowerCase()
      @_pairIds = @config.pairIds

      @actions['transferConfigToDevice'] =
        params:{}

      @addAttribute(
        'battery',
        {
          description: "state of the battery"
          type: "boolean"
          labels: ['low', 'ok']
          acronym: "Bat."
        }
      )

      @maxDriver.on('ShutterContactStateRecieved',shutterContactStateReceivedHandler = (shutterContactState) =>
        if(@_deviceId == shutterContactState.src)
          # If the window is open the isOpen field is true the contact is open = false
          @_setContact(if shutterContactState.isOpen then false else true)
          @_setBattery(shutterContactState.batteryLow)
          env.logger.debug "ShutterContact with deviceId #{@_deviceId} updated"
      )

      @on('destroy', () =>
        @maxDriver.removeListener('ShutterContactStateRecieved', shutterContactStateReceivedHandler)
        env.logger.debug "ShutterContact #{@_deviceId} ShutterContactStateRecieved handler removed"
      )

      super()

    getTemplateName: -> "maxcul-contact"

    getBattery:() -> Promise.resolve(@_battery)

    _setBattery: (value) ->
      if @_battery is value then return
      @_battery = value
      @emit 'battery', value

    handleReceivedCmd: (command) ->

    transferConfigToDevice: () ->
      env.logger.info "transfer config to device #{@_deviceId}"
      for pid in @_pairIds
        if pid.pairId != "000000"
          @maxDriver.sendPair(@_deviceId,pid.pairId.toLowerCase(),pid.type,@constructor.deviceType)
          env.logger.info "send pairId #{pid.pairId} to device #{@_deviceId}"
      if @_groupId != "00"
        @maxDriver.sendGroup(@_deviceId,@_groupId,@constructor.deviceType)
        env.logger.info "send groupID #{@_groupId} to device #{@_deviceId}"

    destroy: ->
      env.logger.debug "ShutterContact #{@_deviceId} destroyed"
      super()

# Class that represents a MAX! ShutterContact
  class MaxculFakeShutterContact extends env.devices.ContactSensor

    @deviceType = "ShutterContact"

    actions:
      changeContactTo:
        params:
          contact:
            type: "boolean"

    constructor: (@config, lastState, @maxDriver, index) ->
      @id = @config.id
      @name = @config.name
      @_deviceId = @config.deviceId.toLowerCase()
      @_groupId = @config.groupId.toLowerCase()
      @_pairIds = @config.pairIds
      @_index = index

      super()

    changeContactTo: (contact) ->
      Promise.map(@_pairIds , (pids) =>
        return @maxDriver.sendShutterMessage(pids.pairId, @_deviceId, contact, @_groupId , @constructor.deviceType)
      ).then( =>
        @_setContact(contact)
        return Promise.resolve true
      )

    destroy: ->
      env.logger.debug "ShutterContact #{@_deviceId} destroyed"
      super()

  # Class that represents a MAX! PushButton
  class MaxculPushButton extends env.devices.ContactSensor

    @deviceType = "PushButton"
    template: "maxcul-contact"

    constructor: (@config, lastState, @maxDriver, index) ->
      @id = @config.id
      @name = @config.name
      @_deviceId = @config.deviceId.toLowerCase()
      @_contact = lastState?.contact?.value
      @_battery = lastState?.battery?.value
      @_index = index
      @_groupId = @config.groupId.toLowerCase()
      @_pairIds = @config.pairIds

      @actions['transferConfigToDevice'] =
        params:{}

      @addAttribute(
        'battery',
        {
          description: "state of the battery"
          type: "boolean"
          labels: ['low', 'ok']
          acronym: "Bat."
        }
      )

      @maxDriver.on('PushButtonStateRecieved',pushButtonStateReceivedHandler = (pushButtonState) =>
        if(@_deviceId == pushButtonState.src)
          # If the button state is open the isOpen field is true the contact is open = false
          @_setContact(if pushButtonState.isOpen then false else true)
          @_setBattery(pushButtonState.batteryLow)
          env.logger.debug "PushButton with deviceId #{@_deviceId} updated"
      )

      @on('destroy', () =>
        @maxDriver.removeListener('PushButtonStateRecieved', pushButtonStateReceivedHandler)
        env.logger.debug "PushButton #{@_deviceId} PushButtonStateRecieved handler removed"
      )

      super()

    getTemplateName: -> "maxcul-contact"

    getBattery:() -> Promise.resolve(@_battery)

    _setBattery: (value) ->
      if @_battery is value then return
      @_battery = value
      @emit 'battery', value

    handleReceivedCmd: (command) ->

    transferConfigToDevice: () ->
      env.logger.info "transfer config to device #{@_deviceId}"
      for pid in @_pairIds
        if pid.pairId != "000000"
          @maxDriver.sendPair(@_deviceId,pid.pairId.toLowerCase(),pid.type,@constructor.deviceType)
          env.logger.info "send pairId #{pid.pairId} to device #{@_deviceId}"
      if @_groupId != "00"
        @maxDriver.sendGroup(@_deviceId,@_groupId,@constructor.deviceType)
        env.logger.info "send groupID #{@_groupId} to device #{@_deviceId}"

    destroy: ->
      env.logger.debug "PushButton #{@_deviceId} destroyed"
      super()

  # Class that represents a MAX! WallThermostat
  class MaxculWallThermostat extends MaxculThermostat

    @deviceType: "WallMountedThermostat"
    template: "maxcul-wall-thermostat"

    constructor: (@config, lastState, @maxDriver, index) ->
      super(@config, lastState, @maxDriver, index)

      @maxDriver.on('WallThermostatStateRecieved', thermostatStateRecievedHandler = (thermostatState) =>
        if(@_deviceId == thermostatState.src)
          @_setBattery(thermostatState.batterylow)
          @_setMode(@constructor._modes[thermostatState.mode])
          @_setSetpoint(thermostatState.desiredTemperature)
          if( thermostatState.measuredTemperature != 0)
            @_setMeasuredTemperature(thermostatState.measuredTemperature)
      )
      @maxDriver.on('WallThermostatControlRecieved', thermostatStateRecievedHandler = (thermostatState) =>
        if(@_deviceId == thermostatState.src)
          @_setSetpoint(thermostatState.desired)
          if( thermostatState.measured != 0)
            @_setMeasuredTemperature(thermostatState.measured)
      )

      @on('destroy', () =>
        @maxDriver.removeListener('WallThermostatStateRecieved', thermostatStateRecievedHandler)
        @maxDriver.removeListener('WallThermostatControlRecieved', thermostatStateRecievedHandler)
        env.logger.debug "WallThermostat #{@_deviceId} handlers removed"
      )

    getTemplateName: -> "maxcul-wall-thermostat"

    destroy: ->
      env.logger.debug "WallThermostat #{@_deviceId} destroyed"
      super()

  # Class that represents a MAX! Fake WallThermostat
  class MaxculFakeWallThermostat extends MaxculThermostat

    @deviceType: "WallMountedThermostat"
    template: "maxcul-wall-thermostat"

    constructor: (@config, lastState, @maxDriver, index) ->
      super(@config, lastState, @maxDriver, index)
      @_exprChangeListeners = []
      @_vars = maxculPlugin.framework.variableManager
      info = null
      evaluate = ( =>
        # wait till VariableManager is ready
        return @_vars.waitForInit().then( =>
          unless info?
            info = @_vars.parseVariableExpression(@config.refTemp)
            @_vars.notifyOnChange(info.tokens, evaluate)
            @_exprChangeListeners.push evaluate

          switch info.datatype
            when "numeric" then @_vars.evaluateNumericExpression(info.tokens)
            when "string" then @_vars.evaluateStringExpression(info.tokens)
            else
              assert false
        ).then((val) =>
          val = @_getNumber(val)
          @_setMeasuredTemperature(val)
          Promise.map(@_pairIds ,(pids) =>
            return @maxDriver.sendTemperatureMessage(pids.pairId, @_measuredTemperature, @_temperatureSetpoint, @_groupId, @constructor.deviceType)
          ).then( =>
            @_lastSendTime = new Date().getTime()
            return Promise.resolve true
          )
        ).catch((error) =>
          env.logger.error "Error on device #{@_deviceId}:", error.message
        )
      )
      evaluate()

    _getNumber: (value) ->
      if value?
        numValue = Number value
        unless isNaN numValue
          return numValue
        else
          errorMessage = "Input value is not a number: #{value}"
      else
        errorMessage = "Input value is null or undefined"
        throw new Error errorMessage

    getTemplateName: -> "maxcul-wall-thermostat"

    destroy: ->
      @_vars.cancelNotifyOnChange(cl) for cl in @_exprChangeListeners
      env.logger.debug "WallFakeThermostat #{@_deviceId} destroyed"
      super()

    changeModeTo: (mode) ->
      if @_mode is mode then return Promise.resolve true
      if mode is "auto"
        temperatureSetpoint = null
      else
        temperatureSetpoint = @_temperatureSetpoint
        env.logger.debug "Set desired mode to #{mode} for deviceId #{@_deviceId}"

      Promise.map(@_pairIds , (pids) =>
        return @maxDriver.sendDesiredTemperature(pids.pairId, temperatureSetpoint, mode, @_groupId , @constructor.deviceType)
      ).then( =>
        @_lastSendTime = new Date().getTime()
        @_setMode(mode)
        @_setSetpoint(temperatureSetpoint)
        return Promise.resolve true
      )

    changeTemperatureTo: (temperatureSetpoint) ->
      if @_temperatureSetpoint is temperatureSetpoint then return Promise.resolve true
      env.logger.debug "Set desired temperature #{temperatureSetpoint} for deviceId #{@_deviceId}"
      Promise.map(@_pairIds , (pids) =>
        return @maxDriver.sendDesiredTemperature(pids.pairId, temperatureSetpoint, @_mode, @_groupId , @constructor.deviceType)
      ).then( =>
        @_lastSendTime = new Date().getTime()
        @_setSynced(true)
        @_setSetpoint(temperatureSetpoint)
        return Promise.resolve true
      )

    transferConfigToDevice: () ->
      env.logger.debug "Fake doesn't need a config"
      return Promise.resolve true

    _updateTimeInformation: () ->
      env.logger.debug "Fake doesn't need a time update"
      return Promise.resolve true

  maxculPlugin = new MaxculPlugin
  return maxculPlugin
