# WebSockets From Scratch

I have been at Pusher for almost 6 months and, mainly working on customer-facing developer work, parts of our deeper infrastructure have seemed a bit of a black box to me. Pusher, a message service that lets you send realtime data from server to client or from client to client, has the WebSocket protocol at its core. I was aware of how the HTTP protocol worked, but not WebSocket - aside from the fact it lets you do some nifty realtime stuff.

Therefore I decided to dig a little deeper and try to build a WebSocket server from scratch - and by 'scratch', I mean using only Ruby's built-in libraries. This blog post is to partly share what I've learnt and partly act as a tutorial, given that I couldn't find many that would lead me through the process step-by-step. That said, there were plenty of awesome resources for getting to grips on the matter, such as on [Mozilla](https://developer.mozilla.org/en-US/docs/WebSockets/Writing_WebSocket_servers) and this post from [Armin Ronacher](http://lucumr.pocoo.org/2012/9/24/websockets-101/).

This guide is aimed at people who are new to WebSocket, or just wish to know more about what's under the hood. What I'll cover, in around 100 lines of Ruby, is:

* The HTTP handshake that initiates a WebSocket connection.
* Listening to messages on the server.
* Sending messages from the server.

A lot of very important features will be left out for the sake of brevity, such as ping/pong heartbeats, types of messages that aren't UTF-8 text data, security, proxying, handling different WebSocket protocol versions, and message fragmentation. So let's get to it.

## An Overview to the WebSocket Procotol

WebSocket, like HTTP, is a layer upon the [TCP protocol](http://en.wikipedia.org/wiki/Transmission_Control_Protocol). A high-level difference between the two is that a classic HTTP response closes the TCP socket, whereas in the WebSocket protocol, the connection stays open. This allows bi-directional communication between the server and client, and is great for the realtime functionality you are used to: chat applications, data visualization, activity streams and so on.

A WebSocket connection begins with a HTTP GET request from the client to the server, called the 'handshake'. This request carries with it a `Connection: upgrade` and `Upgrade: websocket` header to tell the server that it wants to begin a WebSocket connection, and a `Sec-WebSocket-Version` header that indicates the kind of response it wants. In this guide we'll only focus on version 13.

The request headers also include a `Sec-WebSocket-Key` field. With this, the server creates a `Sec-WebSocket-Accept` header that forms part of its response. How it does this, I will explain later.

Once this handshake is made, each party is free to exchange messages, which are wrapped in 'frames'. Each frame consists of information about:

- Whether this frame is or isn't part of a continuation. In this guide, we'll only deal with frames that contain a complete message (not fragmented).
- The content-type. In this post, we'll only deal with UTF8-encoded text.
- Whether the frame is encoded, or 'masked'. Frames from the client always have to be masked; frames from the server do not have to be.
- The payload length.
- The masking 'key' with which to decode the message - if the frame is masked.
- The payload of the frame.

## The Guide

### What We'll Build

During this post we'll build a simple echo server that takes messages from a client and sends them back with a thank you, simply as a basic implementation of a WebSocket server.

```ruby
server = WebSocketServer.new(port: 3333, path: '/')

server.connect do |connection|
  puts "Connected"
  connection.listen do |message|
    puts "Received #{message} from the browser"
    connection.send("Received #{message}. Thanks!")
  end

end
```

### Getting Started

Let's start with two classes: our `WebSocketServer` and our `WebSocketConnection`. Create them in files called `websocket_server.rb` and `websocket_connection.rb` respectively.

#### `WebSocketServer`

The `WebSocketServer` will be initialized with options, such as the path of the WebSocket endpoint, the port and the host - these will default to `'/'`, `4567` and `localhost` respectively.

```ruby
require 'socket'

class WebSocketServer

  def initialize(options={path: '/', port: 4567, host: 'localhost'})
    @path, port, host = options[:path], options[:port], options[:host]
    @tcp_server = TCPServer.new(host, port)
  end
  ...
 end
```

Upon initializaton, a `TCPServer` object, will be created with our host and port options - though it will not run until we '`accept`' it. Remember to require the built-in `socket` library that lets you create TCP connections.

On calling `#connect`, our `WebSocketServer` will constantly be listening for incoming WebSocket requests on a separate thread. It will be responsible for validating incoming HTTP requests, and sending back a handshake. If a handshake can and has been made - that is, if `send_handshake` returns `true` - it will yield a `WebSocketConnection` to the `block` supplied, as shown in the example below. If `#send_handshake` returns `false`, the server will not create the `WebSocketConnection` instance and will just carry on listening for new requests.

```ruby
class WebSocketServer

  ...

  def connect(&block)
    loop do
      Thread.start(@tcp_server.accept) do |socket|
        begin
          send_handshake(socket) && yield(WebSocketConnection.new(socket))
        rescue => e
          puts e.backtrace
        end
      end
    end
  end

end
```

#### `WebSocketConnection`

The `WebSocketConnection` will be our API for sending and receiving messages. We initialize it with the TCP socket made upon firing up the `TCPServer` in `WebSocketServer#connect`.

```ruby
class WebSocketConnection

  attr_reader :socket

  def initialize(socket)
    @socket = socket
  end
end
```

The connection object will read and write to this socket as it listens for and sends messages.

### The Handshake

Going back to our `WebSocketServer` class, a `WebSocketServer#send_handshake` method is where everything begins. Firstly, let's get the `request_line` (e.g. `'GET / HTTP/1.1'`) and request `header` from the socket, using the `socket#gets` method. This will block if there is nothing yet available, and will also get a line at a time.

```ruby
private

def send_handshake(socket)
  request_line = socket.gets
  header = get_header(socket)
  ...
end

# this gets the header by recursively reading each line offered by the socket
def get_header(socket, header = "")
  (line = socket.gets) == "\r\n" ? header : get_header(socket, header + line)
end
```

If we have not received a GET request at the specified path, or there is no `Sec-WebSocket-Key` in the header, let's write a 400 error to the socket. We can use the `<<` operator, and then close the socket to end the request. By returning `false`, we make sure a `WebSocketConnection` is not created and yielded to the application thread.

```ruby
def send_handshake(socket)
  request_line = socket.gets
  header = get_header(socket)
  if (request_line =~ /GET #{@path} HTTP\/1.1/) && (header =~ /Sec-WebSocket-Key: (.*)\r\n/)
    ... # complete the handshake
  end
  send_400(socket)
  false # reject the handshake
end

def send_400(socket)
  socket << "HTTP/1.1 400 Bad Request\r\n" +
            "Content-Type: text/plain\r\n" +
            "Connection: close\r\n" +
            "\r\n" +
            "Incorrect request"
  socket.close
end
```

If there is a value to `Sec-WebSocket-Key`, according to the regular expression above, we can take that value and create the `Sec-WebSocket-Accept` header in our response. It does so by taking the value of the `Sec-WebSocket-Key` and concatenating it with `"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"`, a 'magic string', defined in the [protocol specification](https://tools.ietf.org/html/rfc6455#page-60). It takes this concatenation, creates a SHA1 digest of it, then encodes this digest in Base64. We can do this using the built-in `digest/sha1` and `base64` libraries.

```ruby
def send_handshake(socket)
  request_line = socket.gets
  header = get_header(socket)
  if (request_line =~ /GET #{@path} HTTP\/1.1/) && (header =~ /Sec-WebSocket-Key: (.*)\r\n/)
    ws_accept = create__accept($1)
    ...
  end
  send_400(socket)
  false
end

WS_MAGIC_STRING = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

require 'digest/sha1'
require 'base64'

def create_websocket_accept(key)
  digest = Digest::SHA1.digest(key + WS_MAGIC_STRING)
  Base64.encode64(digest)
end
```

Now we can take this key, and write our expected response to the socket. This response includes the status code `"101 Switching Protocols"`, to indicate that the server and client will now be speaking via a WebSocket. This also includes the same `Upgrade` and `Connection` headers sent to us by the client, and also the appropriate `Sec-WebSocket-Accept` key and value.

```ruby
def send_handshake(socket)
  request_line = socket.gets
  header = get_header(socket)
  if (request_line =~ /GET #{@path} HTTP\/1.1/) && (header =~ /Sec-WebSocket-Key: (.*)\r\n/)
    ws_accept = create__accept($1)
    send_handshake_response(socket, ws_accept)
    return true
  end
  send_400(socket)
  false
end

def send_handshake_response(socket, ws_accept)
  socket << "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            "Sec-WebSocket-Accept: #{ws_accept}\r\n"
end
```

Now that we've sent the handshake and returned `true`, a new `WebSocketConnection` will be yielded to the application thread. So, test it out!

In your Ruby app, write this:

```ruby
server = WebSocketServer.new(port: 3333, path: '/')

server.connect do |connection|
  puts "Connected"
end
```

Run this app and while this code is running, open up your browser console and create a WebSocket connection to your server:

```js
var socket = new WebSocket("ws://localhost:3333");
```

You should see that your server thread has yielded to the application thread upon handshake, and printed `"Connected"` to your terminal window. If not, you can check out the source code [here](https://github.com/pusher/s-from-scratch-tutorial/blob/master/websocket_server.rb#L25-L35).

### Listening For Messages

Now that clients can connect to us and the user has access to the `WebSocketConnection` object, we can start listening to messages from the client.

By the end of this section, here is what we want to have:

```ruby
server.connect do  |connection|
  puts "Connected"

  connection.listen do |message|
    puts message
  end
end
```

And if from our browser console, we type -

```js
var socket = new WebSocket("ws://localhost:3333");
socket.send("hello");
```

\- we should hope to see `"hello"` in our terminal window. Of course if you try this out now you'll get an error.

So let's create `WebSocketConnection#listen` method. In it we will open a new thread that constantly listens to incoming messages on the connection's socket.

```ruby
class WebSocketConnection

  ...

  def listen(&block)
    Thread.new do
      loop do
        begin
          ...
        rescue => e
          puts e.backtrace
        end
      end
    end
  end

end
```

As mentioned in the overview above, WebSocket messages are wrapped in frames, which are a sequence of bytes carrying information about the message. Our `#listen` method will parse the bytes of a frame and yield the message's content to the application thread.

Let's have a look at what we'll receive if, as in the example above, we send `"hello"` over the socket.

|Byte value|129   |133   |32   |25   |208   |9   |72   |124   |188   |101   |79   |
|:-:|:-:|:-:|---|---|---|---|---|---|---|---|---|
|**Binary representation**| 10000001| 10000101| 00100000| 00011001| 11010000| 00001001| 01001000| 01111100| 10111100| 01100101| 01001111|
|**Meaning**|Fin + opcode   |Mask indicator + Length indicator   | Key |Key|Key|Key| Content|Content|Content|Content|Content

The first byte indicates whether this is the complete message. If the first bit is `1` (as it is) then yes, otherwise it is `0`. The next 3 bytes are reserved. And the remainder of the byte (`0001`) indicates that the content type is text.

Using the `TCPSocket#read` method, we can read `n` bytes at a time:

```ruby
def listen(&block)
  Thread.new do
    loop do
      fin_and_opcode = socket.read(1).bytes[0] # get the 0th item of [129]
    end
  end
end
```

The second byte contains two pieces of information. Firstly, if the message is encoded with a 'mask'. If it's from a client, it always will be. It cannot be if it's from a server. If it is masked, the first bit will be `1`.

The remainder of the byte indicates the content's length. Firstly, we need to remove the first bit out of the equation by subtracting 128 (or calling `mask_and_length_indicator & 0x7f`, if you are comfortable with bitwise operators - which I'm not).

```ruby
def listen(&block)
  Thread.new do
    loop do
      fin_and_opcode = socket.read(1).bytes[0]
      mask_and_length_indicator = socket.read(1).bytes[0]
      length_indicator = mask_and_length_indicator - 128
    end
  end
end
```

If the result is smaller or equal to 125, that is the content length.

```ruby
def listen(&block)
  Thread.new do
    loop do
      fin_and_opcode = socket.read(1)
      mask_and_length_indicator = socket.read(1).bytes
      length_indicator = mask_and_length_indicator - 128

      length =  if length_indicator <= 125
                  length_indicator
                  ...
                end
    end
  end
end
```

If the `length_indicator` is equal to 126, the next two bytes need to be parsed into a 16-bit unsigned integer to get the numeric value of the length. We do this by using Ruby's `Array#unpack` method, passing in `"n"` to show we want a 16-bit unsigned integer, [as per Ruby's documentation here](http://ruby-doc.org/core-2.2.0/Array.html#pack-method).

```ruby
def listen(&block)
  Thread.new do
    loop do
      fin_and_opcode = socket.read(1).bytes[0]
      mask_and_length_indicator = socket.read(1).bytes[0]
      length_indicator = mask_and_length_indicator - 128

      length =  if length_indicator <= 125
                  length_indicator
                elsif length_indicator == 126
                  socket.read(2).unpack("n")[0]
                  ...
                end
    end
  end
end
```

If the `length_indicator` is equal to 127, the next eight bytes will need to be parsed into a 64-bit unsigned integer to get the length. `"Q>"` is passed to `unpack` to indicate this.

```ruby
def listen(&block)
  Thread.new do
    loop do
      fin_and_opcode = socket.read(1).bytes[0]
      mask_and_length_indicator = socket.read(1).bytes[0]
      length_indicator = mask_and_length_indicator - 128

      length =  if length_indicator <= 125
                  length_indicator
                elsif length_indicator == 126
                  socket.read(2).unpack("n")[0]
                else
                  socket.read(8).unpack("Q>")[0]
                end
      ...
    end
  end
end
```

The mask-key itself - what we use to decode the content - will be the next 4 bytes. Then, the encoded content will be the next `nth` bytes, where `n` is the content-length we extracted.

```ruby
def listen(&block)
  Thread.new do
    loop do
      fin_and_opcode = socket.read(1).bytes[0]
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

      ...
    end
  end
end
```

Let's again use the mask-key to decode the content by using this magic function that loops through the bytes and [XORs](http://en.wikipedia.org/wiki/Bitwise_operation#XOR) the octet with the `(i % 4)`th octet of the mask. This is defined in the specification [here](https://tools.ietf.org/html/rfc6455#page-33).


```ruby
def listen(&block)
  Thread.new do
    loop do
      fin_and_opcode = socket.read(1).bytes[0]
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

      ...
    end
  end
end
```

Now that we have the decoded content of the message, let's turn it into a string and yield it to the application thread:

```ruby
def listen(&block)
  Thread.new do
    loop do
      fin_and_opcode = socket.read(1).bytes[0]
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

      message = decoded.pack("c*") # "c*" turns the byte array into a string

      yield(message)
    end
  end
end
```

Test it out on the example at the top of this section. If you've gotten stuck, you can refer to the code [here](https://github.com/jpatel531/socket-and-see/blob/frozen/_connection.rb#L13-L40).

### Sending Messages

To complete our echo server and show the bidirectional power of WebSockets, let's implement a message sending method to our `WebSocketConnection` object. This should be a little more straightforward, as messages from a server do not have to be masked.

```ruby
def send(message)
  ...
end
```

We'll create the initial state of our byte array to send over the socket. This is straightforward as we're sending a complete message and our content is text, so the first value in the array will be `129`, i.e. `10000001`. The first bit `1`, representing that this is a full message, and the last four bits, `0001`, showing that the payload is UTF-8 text.

Then we'll get the size of the message and set the length indicator accordingly. Because our frame is not masked, we do not need to add or subtract by 128 (in other words, set the first bit as `1`), which the client had done to their messages sent to us.

If the size is smaller or equal to 125, we concatenate this to the byte array.

```ruby
def send(message)
  bytes = [129]
  size = message.bytesize

  bytes +=  if size <= 125
              [size]
              ...
            end
end
```

If the size is greater than 125 but smaller than 2<sup>16</sup>, which is the maximum size of two bytes, then we append 126 and the byte array of the length converted from an unsigned 16-bit integer.

```ruby
def send(message)
  bytes = [129]
  size = message.bytesize

  bytes +=  if size <= 125
              [size]
            elsif size < 2**16
              [126] + [size].pack("n").bytes
            ...
            end
end
```

If the size is greater than 2<sup>16</sup>, we append 127 to the frame and then the byte array of the length converted from an unsigned 64-bit integer.

```ruby
def send(message)
  bytes = [129]
  size = message.bytesize

  bytes +=  if size <= 125
              [size]
            elsif size < 2**16
              [126] + [size].pack("n").bytes
            else
              [127] + [size].pack("Q>").bytes
            end
  ...
end
```

Now we can simply append our `message` as bytes. Then we turn this byte array into chars (using `Array#pack` with the argument `"C*"`). Now we can write this to the socket!

```ruby
def send(message)
  bytes = [129]
  size = message.bytesize

  bytes +=  if size <= 125
              [size]
            elsif size < 2**16
              [126] + [size].pack("n").bytes
            else
              [127] + [size].pack("Q>").bytes
            end

  bytes += message.bytes
  data = bytes.pack("C*")
  socket << data
end
```

### The Echo Server

Now that we can begin connections, send messages and receive messages, we can write our tiny echo-server application.

```ruby
server = WebSocketServer.new(port: 3333, path: '/')

server.connect do |connection|
  puts "Connected"
  connection.listen do |message|
    puts "Received #{message} from the browser"
    connection.send("Received #{message}. Thanks!")
  end

end
```

Run this server, and then go into your browser console. Then type:

```js
var socket = new WebSocket("ws://localhost:3333");

socket.onmessage = function(event){console.log(event.data);};
```

This will set up your WebSocket connection by sending a handshake to your server. Then, if a message is received, it will log it to the console.

Let's send a message and see what we get back:

```js
socket.send("hello world!");
```

Immediately after sending the message, your browser should have logged out an event whose data is `"Received hello world. Thanks!"`. Meanwhile, your terminal running the server should have logged out `"Received hello world from the browser"`.

That's it! I hope you enjoyed this post and that it was informative for those who were new to WebSocket.

## What's Missing?

As I mentioned earlier, there's a lot more one can improve and add to make it a fully-functional WebSocket server - not to mention making it able to handle thousands of concurrent connections. From experience, we've found that developers who implement their own scalable WebSocket solutions have found it tricky to maintain and debug. Thus Pusher's appeal to those for whom realtime is core to their application; we essentially host, maintain and scale these servers for you, and provide an easy-to-use API to interact with them so you can focus on the rest of your application. Hopefully this post has showed you a bit about what goes on underneath.
