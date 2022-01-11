require "colorize"
require "http/client"
require "json"
require "../client.cr"
require "./base.cr"

class ReplayAction < Action
  getter aliases : Set(String) = Set{"replay"}

  def invoke(
    client : Client,
    tx : Channel({String, SourceData}),
    sources : Hash(String, Source),
    line : String
  ) : Nil
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

      client.socket << "\x1b[1;1H"
      client.socket << "\x1b[0J"
      client.socket << "remembering before...".colorize.red.bold
      client.socket << "\x1b[10000B"
      client.socket << "\r"
    rescue ex
      pp ex.inspect_with_backtrace
      client.socket << "invalid timestamp"
    end
  end
end
