module.exports = (env) ->

  class CulPacket
    constructor: () ->
      @length = 0
      @messageCount = 0
      @flag = 0
      @groupid = 0

      @source = ''
      @dest = ''
      @rawType = ''
      @rawPayload = ''
      @forMe = false
      @command = ''
      @status = 'new'
      #contains a hole packet
      @rawPacket = ''
      #contains only the payload
      @rawPayload = ''
      @sendTries = 0
      @decodedPayload = null

    getLength: () -> return @length
    setLength: (length) -> @length = length

    getMessageCount: () -> return @messageCount
    setMessageCount: (messageCount) -> @messageCount = messageCount

    getFlag: () -> return @flag
    setFlag: (flag) -> @flag = flag

    getGroupId: () -> return @groupid
    setGroupId: (groupid) -> @groupid = groupid

    getSource: () -> return @source
    setSource: (source) -> @source = source.toLowerCase()

    getDest: () -> return @dest
    setDest: (dest) -> @dest = dest.toLowerCase()

    getRawType: () -> return @rawType
    setRawType: (rawType) -> @rawType = rawType

    getRawPayload: () -> return @rawPayload
    setRawPayload: (rawPayload) -> @rawPayload = rawPayload

    getForMe: () -> return @forMe
    setForMe: (forMe) -> @forMe = forMe

    getCommand: () -> return @command
    setCommand: (command) -> @command = command

    getStatus: () -> return @status
    setStatus: (status) -> @status = status

    getRawPacket : () -> return @rawPacket
    setRawPacket : (rawPacket) -> @rawPacket = rawPacket

    getRawPayload : () -> return @rawPayload
    setRawPayload: (rawPayload) -> @rawPayload = rawPayload.toUpperCase()

    getSendTries : () -> return @sendTries
    setSendTries : (sendTries) -> @sendTries = sendTries

    getDecodedPayload : () -> return @decodedPayload
    setDecodedPayload : (decodedPayload) -> @decodedPayload = decodedPayload
