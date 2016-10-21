module.exports = {
  title: "pimatic-maxcul config"
  type: "object"
  properties:
    serialPortName:
      doc: "Set the name of the serial device to use"
      type: "string"
      default: "/dev/ttyACM0"
    baudrate:
      doc: "Set the baudrate to use for the communication with the CUL868 device"
      type: "number"
      default: 9600
    homebaseAddress:
      doc: "The Address of this basestation in the MAX! System Default (123456)"
      type: "string"
      default: "123456"
    enablePairMode:
      doc: "Enabled the pair mode, should be false for production because it could interfere with your neighbours"
      type: "boolean"
      default: false
    debug:
      doc: "Enabled debug messages"
      type: "boolean"
      default: false
}
