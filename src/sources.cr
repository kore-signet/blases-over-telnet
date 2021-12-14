require "json"
require "sse"
require "json-tools"

CHRONICLER_URL = URI.parse(ENV["CHRONICLER_URL"] ||= "https://api.sibr.dev/chronicler/")

class SourceData
  property temporal : Hash(String, JSON::Any)? = nil
  property games : Array(JSON::Any)? = nil
  property leagues : Hash(String, JSON::Any)? = nil
  property sim : Hash(String, JSON::Any)? = nil

  def initialize
  end

  def initialize(value : JSON::Any)
    from_stream value
  end

  def from_stream(value : JSON::Any)
    @leagues = value["leagues"]?.try &.as_h?
    @temporal = value["temporal"]?.try &.as_h?
    value["games"]?.try do |games_data|
      @sim = games_data["sim"]?.try &.as_h?
      @games = games_data["schedule"]?.try &.as_a?
    end
  end
end

abstract class Source
  abstract def add_client
  abstract def rm_client
  abstract def n_clients
  abstract def last_data
end

class LiveSource < Source
  property sse : HTTP::ServerSentEvents::EventSource
  property tx : Channel({String, SourceData})
  property ident : String
  property clients : Int32 = 0
  property current_data : SourceData
  property last_message : JSON::Any

  def initialize(url : String, @ident : String, @tx : Channel({String, SourceData}))
    @current_data = SourceData.new
    @last_message = JSON.parse(%({"empty": "message"}))

    @sse = HTTP::ServerSentEvents::EventSource.new url
    @sse.on_message do |msg|
      begin
        parsed_message = JSON.parse(msg.data[0]).as_h
      rescue ex
        begin
          parsed_message = JSON.parse(msg.data[0][8..msg.data[0].size - 2])
        rescue ex2
          puts "error in source #{ident}"
          pp ex.inspect_with_backtrace
          puts "error in SSE formatting workaround"
          pp ex2.inspect_with_backtrace
          next
        end
      end

      if parsed_message.has_key? "value"
        @last_message = parsed_message["value"]

        @current_data.from_stream @last_message
        @tx.send({@ident, @current_data})
      elsif parsed_message.has_key? "delta"
        apply_patch(parsed_message["delta"])

        @current_data.from_stream @last_message
        @tx.send({@ident, @current_data})
      end
    end

    spawn do
      @sse.run
    end
  end

  def apply_patch(patch : JSON::Any)
    begin
      @last_message = Json::Tools::Patch.new(patch).apply(@last_message)
    rescue ex
      puts "error in applying patch"
      pp ex.inspect_with_backtrace
    end
  end

  def add_client
    @clients += 1
  end

  def rm_client
    @clients -= 1
  end

  def n_clients
    @clients
  end

  def close
    @sse.stop
  end

  def set_last_message(@last_message)
  end

  def last_data : SourceData
    @current_data
  end
end

class ChroniclerSource < Source
  property tx : Channel({String, SourceData})
  property ident : String
  property clients : Int32 = 0
  property current_data : SourceData
  property cached_messages : Array({Time, SourceData}) = Array({Time, SourceData}).new
  property last_time : Time
  property running : Bool = true

  def initialize(@last_time, @ident : String, @tx : Channel({String, SourceData}))
    @current_data = SourceData.new
    spawn do
      while @running
        if cached_messages.size == 0
          fetch_messages
        end

        break if cached_messages.size == 0

        next_message = @cached_messages.delete_at 0

        sleep next_message[0] - @last_time
        @last_time = next_message[0]
        @tx.send({ident, next_message[1]})
      end
    end
  end

  def add_client
    @clients += 1
  end

  def rm_client
    @clients -= 1
  end

  def n_clients
    @clients
  end

  def close
    @running = false
  end

  def fetch_messages
    url = CHRONICLER_URL
    url.query = URI::Params.encode({"type" => "Stream", "count" => "30", "order" => "asc", "after" => @last_time.to_rfc3339})
    url.path = (Path.new(url.path) / "v2" / "versions").to_s

    response = HTTP::Client.get url

    messages = JSON.parse response.body
    @cached_messages = messages["items"].as_a.select { |v| !v["data"]["value"]?.nil? }.map do |v|
      {
        Time.parse_rfc3339(v["validFrom"].as_s),
        SourceData.new v["data"]["value"],
      }
    end
  end

  def last_data : SourceData
    @current_data
  end
end
