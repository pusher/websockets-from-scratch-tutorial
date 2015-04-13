class WebsocketConnection

  WS_MAGIC_STRING = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  OPCODE_TEXT = 0x01

  attr_reader :socket, :path, :handshake_made

  def initialize(socket, path)
    @socket, @path, @handshake_made = socket, path, false
    begin_handshake
  end

  def listen(&block)
    Thread.new do
      loop do
        fin_and_opcode = socket.read(1).bytes
        mask_and_length_indicator = socket.read(1).bytes[0]
        length_indicator = mask_and_length_indicator - 128

        length =  if length_indicator <= 125
                    length_indicator
                  elsif length_indicator == 126
                    socket.read(2).unpack("n")[0]
                  else
                    socket.read(8).unpack("Q>")[0]
                  end

        keys = socket.read(4).bytes
        encoded = socket.read(length).bytes

        decoded = encoded.each_with_index.map do |byte, index| 
          byte ^ keys[index % 4] 
        end

        message = decoded.pack("c*")

        yield(message)
      end
    end
  end

  def send(message)
    bytes = [0x80 | OPCODE_TEXT]
    size = message.bytesize

    bytes +=  if size <= 125 
                [size] # i.e. `size | 0x00`; if masked, would be `size | 0x80`, or size + 128
              elsif size < 2**16
                [126] + [size].pack("n").bytes
              else
                [127] + [size].pack("Q>").bytes
              end 

    bytes += message.bytes
    data = bytes.pack("C*")
    socket << data
  end

  private

  def begin_handshake 
    request_line = socket.gets
    if request_line =~ /GET #{path}/
      header = get_header
      return send_400 if !(header =~ /Sec-WebSocket-Key: (.*)\r\n/)
      ws_accept = create_websocket_accept($1)
      send_handshake_response(ws_accept)
      @handshake_made = true
    end
  end

  def get_header(header = "")
    (line = socket.gets) == "\r\n" ? header : get_header(header + line)
  end

  def send_400
    socket << "HTTP/1.1 400 Bad Request\r\n" +
              "Content-Type: text/plain\r\n" +
              "Connection: close\r\n" +
              "\r\n" +
              "Incorrect request"
    socket.close   
  end

  def send_handshake_response(ws_accept)
    socket << "HTTP/1.1 101 Switching Protocols\r\n" +
              "Upgrade: websocket\r\n" +
              "Connection: Upgrade\r\n" +
              "Sec-WebSocket-Accept: #{ws_accept}\r\n" 
  end

  def create_websocket_accept(key)
    digest = Digest::SHA1.digest(key + WS_MAGIC_STRING)
    Base64.encode64(digest)
  end

end