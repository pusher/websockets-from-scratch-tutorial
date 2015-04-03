require 'digest/sha1'
require 'base64'
# require 'json'
# require 'stringio'
require 'socket'

class WebsocketServer

	attr_reader :port, :path, :host

	def initialize(options={})
		@port = options.fetch(:port, 3000)
		@path = options.fetch(:path, '/')
		@host = options.fetch(:host, 'localhost')
	end

	def connect(&block)
		server = TCPServer.new(host, port)

		loop do
			Thread.start(server.accept) do |socket|
				connection = WebsocketConnection.new(socket, path)
				yield(connection) if connection.handshake
			end
		end

	end


end

class WebsocketConnection

	WS_MAGIC_STRING = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


	attr_reader :socket, :path

	def initialize(socket, path)
		@socket, @path = socket, path
	end

	def handshake	
			request = socket.gets
			STDERR.puts request

			if request =~ /GET #{path}/
				header = get_header
				header =~ /Sec-WebSocket-Key: (.*)\r\n/
				ws_accept = create_websocket_accept($1)
				send_handshake_response(ws_accept)
				true
			else
				false
			end

	end

	private

	def get_header(header = "")
		(line = socket.gets) == "\r\n" ? header : get_header(header + line)
	end

	def send_handshake_response(ws_accept)
		socket.print "HTTP/1.1 101 Switching Protocols\r\n" +
			"Upgrade: websocket\r\n" +
			"Connection: Upgrade\r\n" +
			"Sec-WebSocket-Accept: #{ws_accept}\r\n"		
	end

	def create_websocket_accept(key)
		accept = Digest::SHA1.digest(key + WS_MAGIC_STRING)
		Base64.encode64(accept)
	end

end




















