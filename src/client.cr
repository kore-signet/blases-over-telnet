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
  property last_rendered_message : String = ""

  def initialize(@renderer, @socket, @source)
  end

  def close
    @closed = true
    @socket.close
  end

  def render(msg : SourceData)
    @last_rendered_message = @renderer.render msg, settings
    @last_rendered_message
  end
end
