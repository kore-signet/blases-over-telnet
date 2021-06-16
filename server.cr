require "socket"
require "sse"
require "json"
require "colorize"
require "./color_diff.cr"

tx = Channel(String).new

ENV["PORT"] ||= "8023"

server = TCPServer.new "0.0.0.0", ENV["PORT"].to_i
sockets = Array(TCPSocket).new
last_message = ""

def handle_client(socket : TCPSocket, sockets : Array(TCPSocket))
  sockets << socket

  while line = socket.gets chomp: false
  end

  sockets.delete socket
end

spawn do
  while socket = server.accept?
    spawn handle_client(socket,sockets)
  end
end

spawn do
  while m = tx.receive?
    sockets.each do |s|
      s << m
    end
  end
end


ENV["STREAM_URL"] ||= "https://www.blaseball.com/events/streamData"
color_map = ColorMap.new "color_data.json"

class Colorizer
  property color_map : ColorMap
  property current_game : Hash(String,JSON::Any)
  def initialize(@color_map, @current_game = Hash(String,JSON::Any).new)
  end

  def colorize(away?, string)
    string
    .colorize
    .bold
    .fore(@color_map.get_hex_color @current_game[away? ? "awayTeamColor" : "homeTeamColor"].as_s)
    .to_s
  end
end

colorizer = Colorizer.new color_map

while true
  begin
    sse = HTTP::ServerSentEvents::EventSource.new ENV["STREAM_URL"]
    sse.on_message do |message|
      tx.send "\u001b[2J"
      tx.send "\u001b[0;0f"

      puts last_message

      msg = String.build do |m|
        begin
          games = JSON.parse(message.data[0])["value"]["games"]
        rescue
          begin # nested try-catch. i know. i hate it too.
            games = JSON.parse(message.data[0][8..message.data[0].size-2])["games"]
          rescue
            tx.send last_message
            next
          end
        end

        m << %(Day #{games["sim"]["day"].as_i + 1}, Season #{games["sim"]["season"].as_i + 1}).colorize.bold.to_s
        m << "\u001b[2;0f"
        m << %(#{games["sim"]["eraTitle"].to_s.colorize.fore(color_map.get_hex_color games["sim"]["eraColor"].to_s)} - #{games["sim"]["subEraTitle"].to_s.colorize.fore(color_map.get_hex_color games["sim"]["subEraColor"].to_s)}).colorize.underline.to_s

        i = 4

        games["schedule"].as_a.each do |game|
          colorizer.current_game = game.as_h

          m << "\u001b[#{i};0f"
          m << %(#{colorizer.colorize true, (game["awayTeamName"].as_s + " (#{game["awayScore"]})")} #{"vs".colorize.underline} #{colorizer.colorize false, (game["homeTeamName"].as_s + " (#{game["homeScore"]})")})
          #tx.send %(#{game["awayTeamName"].colorize.bold.fore(color_map.get_hex_color game["awayTeamColor"].as_s)} #{"vs.".colorize.underline} #{game["homeTeamName"].colorize.bold.fore(color_map.get_hex_color game["homeTeamColor"].as_s)})
          m << "\u001b[#{i+1};0f"
          m << %(#{game["lastUpdate"]})
          i+=2+game["lastUpdate"].as_s.split("\n").size
        end
      end

      if !msg.empty?
        last_message = msg
      end
      
      tx.send msg
    end

    sse.run
  rescue ex
    pp ex.inspect_with_backtrace
  end
end
