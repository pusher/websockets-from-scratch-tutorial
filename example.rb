require_relative 'websocket_server'

server = WebSocketServer.new

loop do
  Thread.new(server.accept) do |connection|
    puts "Connected"
    while (message = connection.recv)
      puts "Received #{message}"
      connection.send("Received #{message}. Thanks!")
    end
  end
end
