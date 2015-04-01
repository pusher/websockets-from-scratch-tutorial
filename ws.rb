# require 'sinatra'
require 'digest/sha1'
require 'base64'
# require 'json'

# get '/' do
# 	"Hello world"
# end

# get '/ws' do 
# 	# puts request.env
# 	websocket_key = request.env["HTTP_SEC_WEBSOCKET_KEY"] + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	
# 	# puts websocket_key

# 	sha = Digest::SHA1.digest websocket_key
# 	base = Base64.encode64 sha
# 	# puts base
# 	status 101
# 	headers \
# 		"Upgrade" => "websocket",
# 		"Connection" => "Upgrade",
# 		"Sec-WebSocket-Accept" => base

# 	puts response.inspect
# 	# {success:200}.to_json
# 	nil
# end
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


		wsdata = socket.readpartial(1024)

		ws_bytes = wsdata.each_byte.to_a

		puts ws_bytes

		fin = ws_bytes[0]

		second_byte_mod = ws_bytes[1] - 128

		puts second_byte_mod

		if 0 <= second_byte_mod && second_byte_mod <= second_byte_mod
			length = ws_bytes[1]
			keys = ws_bytes[2..5]
			content = ws_bytes[6..-1]

			puts length
			puts keys
			puts content

		elsif second_byte_mod == 126
			length = ws_bytes[2..3]
			keys = ws_bytes[4..7]
			content = ws_bytes[8..-1]
		elsif second_byte_mod == 127
			length = ws_bytes[2..9]
			keys = ws_bytes[10..13]
			content = ws_bytes[13..-1]
		end
			
		decoded = []

		content.each_with_index do |byte, index|
			decoded[index] = byte ^ keys[index % 4]
		end

		puts decoded.pack("c*")
			

			# socket.print "\r\n"
		# socket.close

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
