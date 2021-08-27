require "socket"
require "sse"
require "json"
require "./sources.cr"
require "./layouts.cr"
require "./color_diff.cr"
#


class Client
  property renderer : Layout
  property source : String
  property socket : TCPSocket
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

sockets = Array(Client).new

ENV["STREAM_URL"] ||= "https://www.blaseball.com/events/streamData"
ENV["PORT"] ||= "8023"
server = TCPServer.new "0.0.0.0", ENV["PORT"].to_i

tx = Channel({String, Hash(String,JSON::Any)}).new

sources = Hash(String,Source).new
sources["live"] = LiveSource.new ENV["STREAM_URL"], "live", tx

def handle_client(socket : TCPSocket, sockets : Array(Client), sources : Hash(String,Source), tx : Channel({String, Hash(String,JSON::Any)}))
  begin
    color_map = ColorMap.new "color_data.json"
    colorizer = Colorizer.new color_map
    default_renderer = DefaultLayout.new colorizer

    socket << "\x1b[1;1H"
    socket << "\x1b[0J"
    socket << "\x1b[10000B"
    socket << "\r"

    client = Client.new default_renderer, socket, "live"
    sockets << client
    sources["live"].add_client

    while line = socket.gets chomp: false
      if line.starts_with? "replay:"
        begin
          timestamp = Time::Format::ISO_8601_DATE_TIME.parse line.lstrip("replay:").lstrip

          if !sources.has_key? "replay:#{timestamp}"
            sources["replay:#{timestamp}"] = LiveSource.new "https://api.sibr.dev/replay/v1/replay?from=#{Time::Format::ISO_8601_DATE_TIME.format timestamp}", "replay:#{timestamp}", tx
          end

          sources[client.source].rm_client
          sources["replay:#{timestamp}"].add_client

          client.source = "replay:#{timestamp}"
          socket << "\x1b[1;1H"
          socket << "\x1b[0J"
          socket << "remembering before...".colorize.red.bold
          socket << "\x1b[10000B"
          socket << "\r"

        rescue ex
          pp ex.inspect_with_backtrace
          socket << "invalid timestamp"
        end
      elsif line.starts_with? "live"
        if client.source != "live"
          sources[client.source].rm_client
          sources["live"].add_client

          socket << "\x1b[1;1H"
          socket << "\x1b[0J"
          socket << "writing the present...".colorize.red.bold
          socket << "\x1b[10000B"
          socket << "\r"

          client.source = "live"
          client.renderer.clear_last
        end
      elsif line.starts_with? "stlats"
        total_clients = sources.each.map { |(k,v)| v.n_clients }.sum
        socket << "\x1b[1A\rcurrently connected clients: #{total_clients}"
        socket << "\x1b[10000B"
        socket << "\r"
      elsif line.starts_with? "clear"
        socket << "\x1b[1;1H"
        socket << "\x1b[0J"
        socket << "\x1b[10000B"
        socket << "\r"
      end
    end
  ensure
    socket.close
    sockets.delete socket
  end
end

spawn do
  while socket = server.accept?
    spawn handle_client(socket,sockets,sources,tx)
  end
end

while data = tx.receive?
  to_delete = Array(Client).new
  puts data[0]
  sockets.each.select(&.source.==(data[0])).each do |s|
    begin
      s.socket << s.render data[1]
    rescue
      puts "removing dead client from source #{s.source}"
      sources[s.source].rm_client

      s.close
      to_delete.push s
    end
  end

  if data[0] != "live" && sources[data[0]].n_clients < 1
    sources[data[0]].close
    sources.delete data[0]
  end

  sockets -= to_delete
end
