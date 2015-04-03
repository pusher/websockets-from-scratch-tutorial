require_relative 'websocket_server'

server = WebsocketServer.new port: 4567, path: '/ws'

server.connect do |connection|

	connection.listen do |message|
		puts message
	end

	sleep 5

	connection.send("yo!")

end