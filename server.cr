require "socket"
require "sse"
require "json"
require "colorize"
require "./color_diff.cr"

tx = Channel(String).new

ENV["PORT"] ||= "8023"

server = TCPServer.new "0.0.0.0", ENV["PORT"].to_i
sockets = Array(TCPSocket).new

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

while true
  begin
    sse = HTTP::ServerSentEvents::EventSource.new ENV["STREAM_URL"]
    sse.on_message do |message|
      sleep 0.2
      tx.send "\u001b[2J"
      tx.send "\u001b[0;0f"

      begin
        games = JSON.parse(message.data[0])["value"]["games"]
      rescue
        games = JSON.parse(message.data[0][8..message.data[0].size-2])["games"]
      end

      tx.send %(Day #{games["sim"]["day"].as_i + 1}, Season #{games["sim"]["season"].as_i + 1}).colorize.bold.to_s
      tx.send "\u001b[2;0f"
      tx.send %(#{games["sim"]["eraTitle"].to_s.colorize.fore(color_map.get_hex_color games["sim"]["eraColor"].to_s)} - #{games["sim"]["subEraTitle"].to_s.colorize.fore(color_map.get_hex_color games["sim"]["subEraColor"].to_s)}).colorize.underline.to_s
      i = 4

      games["schedule"].as_a.each do |game|
        tx.send "\u001b[#{i};0f"
        tx.send %(#{game["awayTeamName"].colorize.bold.fore(color_map.get_hex_color game["awayTeamColor"].as_s)} #{"vs.".colorize.underline} #{game["homeTeamName"].colorize.bold.fore(color_map.get_hex_color game["homeTeamColor"].as_s)})
        tx.send "\u001b[#{i+1};0f"
        tx.send %(#{game["awayScore"].to_s.colorize.fore(color_map.get_hex_color game["awayTeamColor"].as_s).bold} - #{game["homeScore"].to_s.colorize.bold.fore(color_map.get_hex_color game["homeTeamColor"].as_s)})
        tx.send "\u001b[#{i+2};0f"
        tx.send %(#{game["lastUpdate"]})
        i+=3+game["lastUpdate"].as_s.split("\n").size
      end
    end

    sse.run
  rescue ex
    pp ex.inspect_with_backtrace
  end
end
