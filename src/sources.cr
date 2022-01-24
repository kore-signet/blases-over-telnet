require "json"
require "sse"

class SourceData
  property temporal : Hash(String, JSON::Any)? = nil
  property games : Array(JSON::Any)? = nil
  property teams : Array(JSON::Any)? = nil
  property sim : Hash(String, JSON::Any)? = nil

  def initialize
  end

  def initialize(value : JSON::Any)
    from_stream value
  end

  def from_stream(value : JSON::Any)
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

class CompositeLiveSource < Source
  property tx : Channel({String, SourceData})
  property ident : String
  property clients : Int32 = 0
  property current_data : SourceData
  property running : Bool = true

  def initialize(@ident : String, @tx : Channel({String, SourceData}))
    @current_data = SourceData.new

    spawn do
      while @running
        @current_data.sim = get_sim
        break if !@current_data.sim
        current_sim = @current_data.sim.not_nil!
        break if Time::Format::ISO_8601_DATE_TIME.parse(current_sim["simEnd"].to_s) < Time.utc

        @current_data.teams = get_teams
        @current_data.games = get_games current_sim["day"].as_i, current_sim["season"].as_i, current_sim["id"].as_s
        @tx.send({@ident, @current_data})
        sleep 2.seconds
      end

      pp "loop ended at time #{Time.utc}"
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

  def get_sim : Hash(String, JSON::Any)
    get_chron_entity("Sim")[0]["data"].as_h
  end

  def get_teams : Array(JSON::Any)
    get_chron_entity("Team").as_a.map { |e| e["data"] }
  end

  def get_chron_entity(entity_type : String) : JSON::Any
    url = URI.parse(ENV["CHRONICLER_URL"] ||= "https://api.sibr.dev/chronicler/")
    url.query = URI::Params.encode({"type" => entity_type})
    url.path = (Path.new(url.path) / "v2" / "entities").to_s

    response = HTTP::Client.get url

    if response.success?
      messages = JSON.parse response.body
      return messages["items"]
    else
      puts "http request failed"
      pp url
      pp response.status_code
      return JSON.parse(%({"response_code": "failure"}))
    end
  end

  def get_games(day : Int32, season : Int32, sim : String) : Array(JSON::Any)
    url = URI.parse(ENV["CHRONICLER_URL"] ||= "https://api.sibr.dev/chronicler/")
    url.query = URI::Params.encode({"day" => day.to_s, "season" => season.to_s, "sim" => sim})
    url.path = (Path.new(url.path) / "v1" / "games").to_s

    response = HTTP::Client.get url

    if response.success?
      messages = JSON.parse response.body
      return messages["data"].as_a.map { |g| g["data"] }
    else
      puts "http request failed"
      pp url
      pp response.status_code
      return Array(JSON::Any).new
    end
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

      pp "loop ended at time #{@last_time}"
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
    url = URI.parse(ENV["CHRONICLER_URL"] ||= "https://api.sibr.dev/chronicler/")
    url.query = URI::Params.encode({"type" => "Stream", "count" => "30", "order" => "asc", "after" => @last_time.to_rfc3339})
    url.path = (Path.new(url.path) / "v2" / "versions").to_s

    response = HTTP::Client.get url

    if response.success?
      messages = JSON.parse response.body
      @cached_messages = messages["items"].as_a.select { |v| !v["data"]["value"]?.nil? }.map do |v|
        {
          Time.parse_rfc3339(v["validFrom"].as_s),
          SourceData.new v["data"]["value"],
        }
      end
    else
      puts "http request failed"
      pp response.status_code
    end
  end

  def last_data : SourceData
    @current_data
  end
end
