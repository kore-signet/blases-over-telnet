require "socket"
require "http/client"
require "sse"
require "json"
require "colorize"
require "./sources.cr"
require "./layouts.cr"
require "./color_diff.cr"
require "./help.cr"

#
class Client
  property renderer : Layout
  property source : String
  property socket : TCPSocket
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

sockets = Array(Client).new

ENV["STREAM_URL"] ||= "https://api.blaseball.com/events/streamData"
ENV["SIBR_API_URL"] ||= "https://api.sibr.dev"
ENV["PORT"] ||= "8023"
server = TCPServer.new "0.0.0.0", ENV["PORT"].to_i

tx = Channel({String, SourceData}).new

sources = Hash(String, Source).new
sources["live"] = LiveSource.new ENV["STREAM_URL"], "live", tx
feed_season_list = JSON.parse((HTTP::Client.get "#{ENV["SIBR_API_URL"]}/chronicler/v2/entities?type=FeedSeasonList").body).as_h

def handle_client(
  socket : TCPSocket,
  sockets : Array(Client),
  sources : Hash(String, Source),
  feed_season_list : Hash(String, JSON::Any),
  tx : Channel({String, SourceData})
) : Nil
  begin
    color_map = ColorMap.new "color_data.json"
    colorizer = Colorizer.new color_map
    default_renderer = DefaultLayout.new colorizer, feed_season_list

    socket << "\x1b[1;1H"   # return cusor to start of page
    socket << "\x1b[0J"     # clear from cursor to the end of the page
    socket << "\x1b[10000E" # move cursor down and to start of line

    client = Client.new default_renderer, socket, "live"
    sockets << client
    sources["live"].add_client

    socket << default_renderer.render sources["live"].last_data

    while line = socket.gets chomp: false
      if line.starts_with? "replay:"
        client.writeable = true
        begin
          timestamp_string = line.lstrip("replay:").lstrip
          if timestamp_string.starts_with? "season"
            timestamp_chunks = timestamp_string.split
            season = timestamp_chunks[1].to_i - 1
            day = timestamp_chunks[-1].to_i - 1
            response = HTTP::Client.get "https://api.sibr.dev/corsmechanics/time/season/#{season}/day/#{day}/"
            timestamp_string = JSON.parse(response.body)[0]["startTime"].as_s
          end

          timestamp = Time::Format::ISO_8601_DATE_TIME.parse timestamp_string

          client.renderer.clear_last

          if !sources.has_key? "replay:#{timestamp}"
            sources["replay:#{timestamp}"] = ChroniclerSource.new timestamp, "replay:#{timestamp}", tx
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
      elsif line.starts_with?("pause")
        client.writeable = false
      elsif line.starts_with?("resume")
        client.writeable = true
      elsif line.starts_with?("help")
        socket << "\x1b[1;1H"
        socket << "\x1b[0J"
        client.writeable = false
        show_help(socket, line)
      elsif line.starts_with? "live"
        client.writeable = true

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
        total_clients = sources.each.map { |(k, v)| v.n_clients }.sum
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
    spawn handle_client(socket, sockets, sources, feed_season_list, tx)
  end
end

while data = tx.receive?
  to_delete = Array(Client).new
  sockets.each.select(&.source.==(data[0])).each do |s|
    rendered_data = s.render data[1]
    message = s.writeable ? rendered_data : "\x1b[0J"
    begin
      s.socket << message
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
