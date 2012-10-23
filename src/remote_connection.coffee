exports = window

class RemoteConnection extends EventEmitter

  constructor: ->
    super
    @serverDevice = undefined
    @_isServer = true
    @devices = []
    @_ircSocketMap = {}
    @_thisDevice = {port: RemoteDevice.FINDING_PORT}
    @_getState = -> {}
    RemoteDevice.getOwnDevice @_onHasOwnDevice

  isSupported: ->
    return !!chrome.socket.create

  setPassword: (password) ->
    @_password = password

  _getAuthToken: (value) =>
    hex_md5 @_password + value

  _onHasOwnDevice: (device) =>
    @_thisDevice = device
    @_thisDevice.listenForNewDevices @_addUnauthenticatedDevice

  _addUnauthenticatedDevice: (device) =>
    @_log 'adding unauthenticated device', device.id
    device.getAddr =>
      @_log 'found unauthenticated device addr', device.addr
      device.on 'authenticate', (authToken) =>
        @_authenticateDevice device, authToken

  _authenticateDevice: (device, authToken) ->
    if authToken is @_getAuthToken device.addr
      @_addClientDevice device
    else
      @_log 'w', 'AUTH FAILED', @_getAuthToken(device.addr), 'should be', authToken
      device.close()

  _addClientDevice: (device) ->
    @_log 'auth passed, adding client device', device.id, device.addr
    @_listenToDevice device
    @_addDevice device
    @_broadcast 'connection_message', 'irc_state', @_getState()

  _addDevice: (device) ->
    @devices.push device

  _listenToDevice: (device) ->
    device.on 'user_input', @_emitUserInput
    device.on 'socket_data', @_emitSocketData
    device.on 'connection_message', @_emitConnectionMessage
    device.on 'closed', => @_onDeviceClosed device

  _emitUserInput: (event) =>
    @emit event.type, Event.wrap event

  _emitSocketData: (server, type, data) =>
    if type is 'data'
      data = irc.util.dataViewToArrayBuffer data
    @_ircSocketMap[server]?.emit type, data

  _emitConnectionMessage: (type, args...) =>
    if type is 'irc_state' and @isServer()
      @_makeClient()
    @emit type, args...

  _onDeviceClosed: (closedDevice) ->
    for device, i in @devices
      @devices.splice i, 1 if device.id is closedDevice.id
      break
    if not @_isServer and closedDevice.id is @serverDevice.id
      @_log 'w', 'lost connection to server -', closedDevice.addr
      @_isServer = true
      @emit 'server_disconnected'
      @connectToServer @serverDevice.addr, @serverDevice.port

  getConnectionInfo: ->
    @_thisDevice

  setStateGenerator: (getState) ->
    @_getState = getState

  createSocket: (server) ->
    if @isServer()
      socket = new net.ChromeSocket
      @broadcastSocketData socket, server
    else
      socket = new net.RemoteSocket
      @_ircSocketMap[server] = socket
    socket

  broadcastUserInput: (userInput) ->
    userInput.on 'command', (event) =>
      unless event.name in ['network-info', 'join-server']
        @_broadcast 'user_input', event

  broadcastSocketData: (socket, server) ->
    socket.onAny (type, data) =>
      if type is 'data'
        data = new Uint8Array data
      @_broadcast 'socket_data', server, type, data

  _broadcast: (type, args...) ->
    for device in @devices
      device.send type, args

  connectToServer: (addr, port) ->
    @serverDevice = new RemoteDevice addr, port
    @_listenToDevice @serverDevice
    @serverDevice.connect (success) =>
      @serverDevice.sendAuthentication @_getAuthToken if success

  close: ->
    for device in @devices
      device.close()
    @_thisDevice.close()

  isServer: ->
    @_isServer

  _makeClient: ->
    @_addDevice @serverDevice
    @_isServer = false

exports.RemoteConnection = RemoteConnection