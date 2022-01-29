require "socket"
require "./layouts.cr"
require "./user_settings.cr"

class Client
  property renderer : Layout
  property source : String
  getter socket : TCPSocket
  property writeable : Bool = true
  property closed : Bool = false
  property settings : UserSettings

  property last_rendered_message : String = ""
  property last_source_data : SourceData?

  def initialize(@renderer, @socket, @source, @last_source_data, @settings = UserSettings.new)
  end

  def close
    @closed = true
    @socket.close
  end

  def render(msg : SourceData)
    @last_source_data = msg
    return @last_rendered_message = @renderer.render msg, settings
  end

  def rerender
    if @last_source_data.nil?
      raise Exception.new("last_source_data is null somehow")
    end
    @last_rendered_message = @renderer.render(@last_source_data.not_nil!, settings)
    @last_rendered_message
  end
end
