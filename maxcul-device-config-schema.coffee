module.exports = {
  title: "pimatic-maxcul device config schemas"
  MaxculShutterContact:{
    title: "Config options for the Maxcul ShutterContact"
    type: "object"
    properties: {
      deviceId:
        description: "ID of the Device in the MAX! Network"
        type: "string"
        default: "000000"
      groupId:
        description : "Group/Room id of the Device"
        type: "string"
        default: "00"
      pairIds:
        description : "Group/Room id of the Device"
        type: "array"
        default: []
        format: "table"
        items:
          type: "object"
          required: ["pairId"]
          properties:
            pairId:
              description: "Id of the pairing device"
              type:"string"
              required: true
            type:
              description: "Device typ"
              type: "string"
              enum: ["HeatingThermostat","WallMountedThermostat"]
              required: true
    }
  },
  MaxculFakeShutterContact:{
    title: "Config options for the Maxcul ShutterContact"
    type: "object"
    properties: {
      deviceId:
        description: "Fake ID of the Device in the MAX! Network"
        type: "string"
        default: "111111"
      groupId:
        description : "Group/Room id of the Device"
        type: "string"
        default: "00"
      pairIds:
        description : "Group/Room id of the Device"
        type: "array"
        default: []
        format: "table"
        items:
          type: "object"
          required: ["pairId"]
          properties:
            pairId:
              description: "Id of the pairing device"
              type:"string"
              required: true
            type:
              description: "Device typ"
              type: "string"
              enum: ["HeatingThermostat","WallMountedThermostat"]
              required: true
    }
  },
  MaxculPushButton:{
    title: "Config options for the Maxcul PushButton"
    type: "object"
    properties: {
      deviceId:
        description: "ID of the Device in the MAX! Network"
        type: "string"
        default: "000000"
      groupId:
        description : "Group/Room id of the Device"
        type: "string"
        default: "00"
      pairIds:
        description : "Group/Room id of the Device"
        type: "array"
        default: []
        format: "table"
        items:
          type: "object"
          required: ["pairId"]
          properties:
            pairId:
              description: "Id of the pairing device"
              type:"string"
              required: true
            type:
              description: "Device typ"
              type: "string"
              enum: ["HeatingThermostat","WallMountedThermostat"]
              required: true
    }
  },
  MaxculHeatingThermostat:{
    title: "Config options for the Maxcul HeatingThermostat"
    type: "object"
    extensions: ["xAttributeOptions"]
    properties: {
      deviceId:
        description: "ID of the Device in the MAX! Network"
        type: "string"
        default: "000000"
      groupId:
        description : "Group/Room id of the Device"
        type: "string"
        default: "00"
      pairIds:
        description : "Group/Room id of the Device"
        type: "array"
        default: []
        format: "table"
        items:
          type: "object"
          required: ["pairId"]
          properties:
            pairId:
              description: "Id of the pairing device"
              type:"string"
              required: true
            type:
              description: "Device typ"
              type: "string"
              enum: ["WallMountedThermostat","ShutterContact"]
              required: true
      comfyTemp:
        description: "The defined comfort mode temperature"
        type: "number"
        default: 21
      ecoTemp:
        description: "The defined eco mode temperature"
        type: "number"
        default: 17
      guiShowModeControl:
        description: "Show the mode buttons in the gui"
        type: "boolean"
        default: true
      guiShowPresetControl:
        description: "Show the preset temperatures in the gui"
        type: "boolean"
        default: true
      guiShowTemperatureInput:
        description: "Show the temperature input spinbox in the gui"
        type: "boolean"
        default: true
      guiShowValvePosition:
        description: "Show the valve position in the gui"
        type: "boolean"
        default: false
      guiShowMeasuredTemperature:
        description: "Show the measured temperature in the gui"
        type: "boolean"
        default: true
      guiShowBatteryState:
        description: "Show the battery state in the gui"
        type: "boolean"
        default: true
      guiShowConfigButton:
        description: "Show a button which which when pressed, transfers the config (eco Mode Settings etc.) to the device."
        type: "boolean"
        default: false
      minimumTemperature:
        description: "The defined minimum temperature that can be set ON THE DEVICE ITSELF"
        type: "number"
        default: 4.5
      maximumTemperature:
        description: "The defined maximum temperature that can be set ON THE DEVICE ITSELF"
        type: "number"
        default: 30.5
      measurementOffset:
        description: "The defined measurement offset"
        type: "number"
        default: 0
      windowOpenTime:
        description: "The defined time for the window open mode"
        type: "number"
        default: 30
      windowOpenTemperature:
        description: "The defined window open temperature mode temperature"
        type: "number"
        default: 4.5
    }
  },
  MaxculWallThermostat:{
    title: "Config options for the Maxcul WallThermostat"
    type: "object"
    extensions: ["xAttributeOptions"]
    properties: {
      deviceId:
        description: "ID of the Device in the MAX! Network"
        type: "string"
        default: "000000"
      groupId:
        description : "Group/Room id of the Device"
        type: "string"
        default: "00"
      pairIds:
        description : "Group/Room id of the Device"
        type: "array"
        default: []
        format: "table"
        items:
          type: "object"
          required: ["pairId"]
          properties:
            pairId:
              description: "Id of the pairing device"
              type:"string"
              required: true
            type:
              description: "Device typ"
              type: "string"
              enum: ["HeatingThermostat","ShutterContact"]
              required: true
      comfyTemp:
        description: "The defined comfort mode temperature"
        type: "number"
        default: 21
      ecoTemp:
        description: "The defined eco mode temperature"
        type: "number"
        default: 17
      guiShowModeControl:
        description: "Show the mode buttons in the gui"
        type: "boolean"
        default: true
      guiShowPresetControl:
        description: "Show the preset temperatures in the gui"
        type: "boolean"
        default: true
      guiShowTemperatureInput:
        description: "Show the temperature input spinbox in the gui"
        type: "boolean"
        default: true
      guiShowMeasuredTemperature:
        description: "Show the measured temperature in the gui"
        type: "boolean"
        default: true
      guiShowBatteryState:
        description: "Show the battery state in the gui"
        type: "boolean"
        default: true
      guiShowConfigButton:
        description: "Show a button which which when pressed, transfers the config (eco Mode Settings etc.) to the device."
        type: "boolean"
        default: false
      minimumTemperature:
        description: "The defined minimum temperature that can be set ON THE DEVICE ITSELF"
        type: "number"
        default: 4.5
      maximumTemperature:
        description: "The defined maximum temperature that can be set ON THE DEVICE ITSELF"
        type: "number"
        default: 30.5
      measurementOffset:
        description: "The defined measurement offset"
        type: "number"
        default: 0
    }
  },
  MaxculFakeWallThermostat:{
    title: "Config options for the Maxcul WallThermostat"
    type: "object"
    extensions: ["xAttributeOptions"]
    properties: {
      deviceId:
        description: "ID of the Device in the MAX! Network"
        type: "string"
        default: "222222"
      groupId:
        description : "Group/Room id of the Device"
        type: "string"
        default: "00"
      pairIds:
        description : "Group/Room id of the Device"
        type: "array"
        default: []
        format: "table"
        items:
          type: "object"
          required: ["pairId"]
          properties:
            pairId:
              description: "Id of the pairing device"
              type:"string"
              required: true
            type:
              description: "Device typ"
              type: "string"
              enum: ["HeatingThermostat","ShutterContact"]
              required: true
      comfyTemp:
        description: "The defined comfort mode temperature"
        type: "number"
        default: 21
      ecoTemp:
        description: "The defined eco mode temperature"
        type: "number"
        default: 17
      guiShowModeControl:
        description: "Show the mode buttons in the gui"
        type: "boolean"
        default: true
      guiShowPresetControl:
        description: "Show the preset temperatures in the gui"
        type: "boolean"
        default: true
      guiShowTemperatureInput:
        description: "Show the temperature input spinbox in the gui"
        type: "boolean"
        default: true
      guiShowMeasuredTemperature:
        description: "Show the measured temperature in the gui"
        type: "boolean"
        default: true
      guiShowBatteryState:
        description: "Show the battery state in the gui"
        type: "boolean"
        default: true
      guiShowConfigButton:
        description: "Show a button which which when pressed, transfers the config (eco Mode Settings etc.) to the device."
        type: "boolean"
        default: false
      minimumTemperature:
        description: "The defined minimum temperature that can be set ON THE DEVICE ITSELF"
        type: "number"
        default: 4.5
      maximumTemperature:
        description: "The defined maximum temperature that can be set ON THE DEVICE ITSELF"
        type: "number"
        default: 30.5
      measurementOffset:
        description: "The defined measurement offset"
        type: "number"
        default: 0
    }
  }
}
