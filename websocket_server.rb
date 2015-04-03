require 'digest/sha1'
require 'base64'
require 'socket'
require_relative 'websocket_connection'

class WebsocketServer

	attr_reader :host, :tcp_server

	def initialize(options={})
		@path = options.fetch(:path, '/')
		port = options.fetch(:port, 4567)
		host = options.fetch(:host, 'localhost')
		@tcp_server = TCPServer.new(host, port)
	end

	def connect(&block)
		loop do
			Thread.start(tcp_server.accept) do |socket|
				connection = WebsocketConnection.new(socket, @path)
				yield(connection) if connection.handshake
			end
		end
	end

end