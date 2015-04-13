require 'digest/sha1'
require 'base64'
require 'socket'
require_relative 'websocket_connection'

class WebsocketServer

  WS_MAGIC_STRING = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

  def initialize(options={path: '/', port: 4567, host: 'localhost'})
    @path, port, host = options[:path], options[:port], options[:host]
    @tcp_server = TCPServer.new(host, port)
  end

  def connect(&block)
    loop do
      Thread.start(@tcp_server.accept) do |socket|
        send_handshake(socket) && yield(WebsocketConnection.new(socket, @path))
      end
    end
  end

  private

  def send_handshake(socket)
    request_line = socket.gets
    if request_line =~ /GET #{@path}/
      header = get_header(socket)
      return send_400(socket) if !(header =~ /Sec-WebSocket-Key: (.*)\r\n/)
      ws_accept = create_websocket_accept($1)
      send_handshake_response(socket, ws_accept)
      return true
    end
    false
  end

  def get_header(socket, header = "")
    (line = socket.gets) == "\r\n" ? header : get_header(socket, header + line)
  end

  def send_400(socket)
    socket << "HTTP/1.1 400 Bad Request\r\n" +
              "Content-Type: text/plain\r\n" +
              "Connection: close\r\n" +
              "\r\n" +
              "Incorrect request"
    socket.close
    false  
  end

  def send_handshake_response(socket, ws_accept)
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