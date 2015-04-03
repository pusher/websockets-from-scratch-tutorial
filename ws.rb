require 'digest/sha1'
require 'base64'
# require 'json'
require 'stringio'
require 'socket'

server = TCPServer.new 'localhost', 4567

loop do 

	socket = server.accept

	request = socket.gets

	STDERR.puts request

	if request =~ /GET \/ws/
		data = socket.readpartial(2048).split("\r\n\r\n")
		puts request

		# puts socket.methods
		
		data[0] =~ /Sec-WebSocket-Key: (.*)\r\n/

		# puts data[0].inspect
		# puts $1
		websocket_key = $1 + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
		# puts websocket_key
		sha = Digest::SHA1.digest websocket_key
		base = Base64.encode64 sha

		socket.print "HTTP/1.1 101 Switching Protocols\r\n" +
			"Upgrade: websocket\r\n" +
			"Connection: Upgrade\r\n" +
			"Sec-WebSocket-Accept: #{base}\r\n"

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

				puts "Length of message: #{length}"
				puts "Content of message: #{decoded}"
			end
		end
			
		sleep 5

		payload = ("a" * 1000)

		bytes = [129]

		size = payload.bytesize

		if size <= 125
			bytes += [size]
		elsif size < 2**16
			bytes += ([126] + [size].pack("n").bytes)
		else
			bytes += ([127] + [size].pack("n").bytes) # also wrong
		end
		
		bytes += payload.bytes
		send_data = bytes.pack("C*")

		socket.write(send_data)


	elsif request =~ /GET \//
		response = "Hello World!\n"

		socket.print "HTTP/1.1 200 OK\r\n" +
			"Content-Type: text/plain\r\n" +
			"Content-Length: #{response.bytesize}\r\n" +
			"Connection: close\r\n"

			socket.print "\r\n"

			socket.print response

			socket.close
	else
		puts 'yolo'
		# data = socket.readpartial(2048)
		data = socket.recv(100)
		puts data
	end

end
