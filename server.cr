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
  begin
    sockets << socket

    while line = socket.gets chomp: false
    end
  ensure
    socket.close
    sockets.delete socket
  end
end

spawn do
  while socket = server.accept?
    spawn handle_client(socket,sockets)
  end
end

spawn do
  while m = tx.receive?
    to_delete = Array(TCPSocket).new

    sockets.each do |s|
      begin
        s << m
      rescue
        s.close
        to_delete.push s
      end
    end

    sockets -= to_delete
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

def make_ord(number)
  number.to_s +
  case number.to_s[-1]
  when '1'
    "st"
  when '2'
    "nd"
  when '3'
    "rd"
  else
    "th"
  end
end

def render_game(colorizer,game)
  String.build do |m|
    m << "\n\r"
    m << %(#{colorizer.colorize true, (game["awayTeamName"].as_s + " (#{game["awayScore"]})")} #{"@".colorize.underline} #{colorizer.colorize false, (game["homeTeamName"].as_s + " (#{game["homeScore"]})")})
    m << "\n\r"
    m << %(#{game["topOfInning"].as_bool ? "Top of the" : "Bottom of the"} #{make_ord game["inning"].as_i+1}).colorize.bold

    if game["topOfInning"].as_bool
      m << %( - #{colorizer.colorize false, game["homePitcherName"].to_s} pitching)
    else
      m << %( - #{colorizer.colorize true, game["awayPitcherName"].to_s} pitching)
    end

    m << "\n\r"

    if game["finalized"].as_bool?
      away_score = (game["awayScore"].as_f? || game["awayScore"].as_i?).not_nil!
      home_score = (game["homeScore"].as_f? || game["homeScore"].as_i?).not_nil!
      if away_score > home_score
        m << %(The #{colorizer.colorize true, game["awayTeamNickname"].as_s} #{"won against".colorize.underline} the #{colorizer.colorize false, game["homeTeamNickname"].as_s})
      else
        m << %(The #{colorizer.colorize false, game["homeTeamNickname"].as_s} #{"won against".colorize.underline} the #{colorizer.colorize true, game["awayTeamNickname"].as_s})
      end
    else
      m << %(#{game["lastUpdate"]})
    end
    m << "\n\r"
  end
end

while true
  begin
    sse = HTTP::ServerSentEvents::EventSource.new ENV["STREAM_URL"]
    sse.on_message do |message|
      sleep 0.2

      tx.send "\u001b[2J"
      tx.send "\u001b[0;0f"

      msg = String.build do |m|
        begin
          games = JSON.parse(message.data[0])["value"]["games"]
        rescue
          begin # nested try-catch. i know. i hate it too.
            games = JSON.parse(message.data[0][8..message.data[0].size-2])["games"]
          rescue
            last_message.each_line(chomp: false) do |l|
              tx.send l
            end

            next
          end
        end

        m << %(Day #{games["sim"]["day"].as_i + 1}, Season #{games["sim"]["season"].as_i + 1}).colorize.bold.to_s
        m << "\n\r"
        m << %(#{games["sim"]["eraTitle"].to_s.colorize.fore(color_map.get_hex_color games["sim"]["eraColor"].to_s)} - #{games["sim"]["subEraTitle"].to_s.colorize.fore(color_map.get_hex_color games["sim"]["subEraColor"].to_s)}).colorize.underline.to_s
        m << "\n\r"

        games["schedule"].as_a.sort_by {|g| g["awayTeamName"].to_s}.each do |game|
          colorizer.current_game = game.as_h
          m << render_game colorizer, game
        end
      end

      if !msg.empty?
        last_message = msg
      end

      msg.each_line(chomp: false) do |l|
        tx.send l
      end
    end

    sse.run
  rescue ex
    pp ex.inspect_with_backtrace
  end
end
