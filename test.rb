require_relative 'websocket_server'

server = WebsocketServer.new port: 4567, path: '/ws'

server.connect do |connection|
	puts 'yolo'
	puts connection
end