require 'digest/sha1'
require 'base64'
require 'socket'
require_relative 'websocket_connection'

class WebsocketServer

  def initialize(options={path: '/', port: 4567, host: 'localhost'})
    @path, port, host = options[:path], options[:port], options[:host]
    @tcp_server = TCPServer.new(host, port)
  end

  def connect(&block)
    loop do
      Thread.start(@tcp_server.accept) do |socket|
          connection = WebsocketConnection.new(socket, @path)
          yield(connection) if connection.handshake_made
      end
    end
  end

end