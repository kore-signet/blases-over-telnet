require "socket"
require "./layouts.cr"

class Client
  property renderer : Layout
  property source : String
  getter socket : TCPSocket
  property writeable : Bool = true
  property closed : Bool = false

  def initialize(@renderer, @socket, @source)
  end

  def close
    @closed = true
    @socket.close
  end

  def render(msg)
    @renderer.render msg
  end
end
