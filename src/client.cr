require "socket"
require "./layouts.cr"
require "./user_settings.cr"

class Client
  property renderer : Layout
  property source : String
  getter socket : TCPSocket
  property writeable : Bool = true
  property closed : Bool = false
  property settings : UserSettings = UserSettings.new

  def initialize(@renderer, @socket, @source)
  end

  def close
    @closed = true
    @socket.close
  end

  def render(msg : SourceData)
    @renderer.render msg, settings
  end
end
