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

	def listen
		Thread.start(socket) do |socket|
			loop do

				fin, pre_length = socket.read(2).bytes

				second_byte_mod = pre_length - 128

				if second_byte_mod <= 125
					length = second_byte_mod
				elsif second_byte_mod == 126
					length = socket.read(2).unpack("n")[0]
				elsif second_byte_mod == 127
					length = socket.read(8).unpack("n")[0] # this is wrong
				end

				keys = socket.read(4).bytes
				content = socket.read(length).bytes

				decoded = content.each_with_index.map { |byte, index| byte ^ keys[index % 4] }.pack("c*")

				yield(decoded)
			end
		end
	end

	def send(message)
		bytes = [129]
		size = message.bytesize

		if size <= 125
			bytes += [size]
		elsif size < 2**16
			bytes += ([126] + [size].pack("n").bytes)
		else
			bytes += ([127] + [size].pack("n").bytes) # also wrong
		end 

		bytes += message.bytes
		send_data = bytes.pack("C*")
		socket.write(send_data)
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