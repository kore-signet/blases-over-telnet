require "socket"
require "http/client"
require "sse"
require "json"
require "colorize"
require "levenshtein"
require "./sources.cr"
require "./client.cr"
require "./layouts.cr"
require "./color_diff.cr"
require "./actions/get_actions.cr"

#
sockets = Array(Client).new

ENV["STREAM_URL"] ||= "https://api.blaseball.com/events/streamData"
ENV["SIBR_API_URL"] ||= "https://api.sibr.dev"
ENV["PORT"] ||= "8023"
server = TCPServer.new "0.0.0.0", ENV["PORT"].to_i

tx = Channel({String, SourceData}).new

actions_by_aliases = get_actions()

sources = Hash(String, Source).new
sources["live"] = LiveSource.new ENV["STREAM_URL"], "live", tx
feed_season_list = JSON.parse((HTTP::Client.get "#{ENV["SIBR_API_URL"]}/chronicler/v2/entities?type=FeedSeasonList").body).as_h

def handle_client(
  socket : TCPSocket,
  sockets : Array(Client),
  sources : Hash(String, Source),
  feed_season_list : Hash(String, JSON::Any),
  actions_by_aliases : Hash(String, Action),
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
      line = line.strip
      if line.blank?
        next
      end

      if actions_by_aliases.has_key?(line)
        actions_by_aliases[line].invoke client, tx, sources, line
      else
        line_start = line.split(2)[0].rstrip(":")
        if actions_by_aliases.has_key?(line_start)
          actions_by_aliases[line_start].invoke client, tx, sources, line
        else
          pp line
          pp line_start
          closest_match = Levenshtein.find(line, actions_by_aliases.keys, 4)
          socket << "Unknown command: "
          socket << line
          if closest_match
            socket << "\r\nDid you mean: "
            socket << closest_match
          end
          socket << "\r\n"
        end
      end
    end
  ensure
    socket.close
    sockets.delete socket
  end
end

spawn do
  while socket = server.accept?
    spawn handle_client(socket, sockets, sources, feed_season_list, actions_by_aliases, tx)
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
