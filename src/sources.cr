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

def get_top_of_next_hour(time : Time) : Time
  result = Time.utc(time.year, time.month, time.day, time.hour, 0, 0)
  result += Time::Span.new(hours: 1)
  return result
end

def get_time(start_time : JSON::Any, end_time : JSON::Any) : Time::Span
  start_value = Time::Format::ISO_8601_DATE_TIME.parse(start_time.to_s)
  end_time_string = end_time.as_s?
  if end_time_string.nil?
    return Time.utc - start_value
  else
    return Time::Format::ISO_8601_DATE_TIME.parse(end_time_string) - start_value
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
  property running : Bool = false

  property last_data_fetch_time = Time.utc

  getter loop_frequency_seconds : UInt8 = 2
  getter sim_fetch_frequency_seconds : UInt32 = 3600
  getter team_fetch_frequency_seconds : UInt32 = 60

  def initialize(@ident : String, @tx : Channel({String, SourceData}))
    @current_data = SourceData.new

    start
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

  def start
    if @running
      return
    end

    @running = true

    spawn do
      begin
        counter = 0
        has_sim_data_been_fetched_for_new_day = false

        while @running
          any_updates = false
          if counter % @sim_fetch_frequency_seconds == 0 || !has_sim_data_been_fetched_for_new_day
            new_sim = get_sim
            if !new_sim.nil?
              Log.trace { "live sim data fetched" }
              if !@current_data.sim.nil?
                previous_day = @current_data.sim.not_nil!["day"]
                new_day = new_sim["day"]
                has_sim_data_been_fetched_for_new_day = new_day != previous_day
                any_updates |= has_sim_data_been_fetched_for_new_day
                Log.trace { "  is_sim_data_different=#{has_sim_data_been_fetched_for_new_day} (previous_day=#{previous_day}, new_day=#{new_day})" }
              end
              @current_data.sim = new_sim
            end
          end

          if @current_data.sim.nil?
            Log.error { "could not get data for sim" }
            break
          end
          current_sim = @current_data.sim.not_nil!
          @last_data_fetch_time = Time.utc
          if Time::Format::ISO_8601_DATE_TIME.parse(current_sim["simEnd"].to_s) < @last_data_fetch_time
            Log.info { "sim has ended" }
            break
          end

          if counter % @team_fetch_frequency_seconds == 0
            new_teams = get_teams
            if !new_teams.nil?
              Log.trace { "live team data fetched" }
              is_team_data_different = new_teams != @current_data.teams
              any_updates |= is_team_data_different
              Log.trace { "  is_team_data_different=#{is_team_data_different}" }
              @current_data.teams = new_teams
            end
          end

          new_games = get_games current_sim["day"].as_i, current_sim["season"].as_i, current_sim["id"].as_s
          is_game_data_different = false
          if !new_games.nil?
            Log.trace { "live game data fetched" }
            is_game_data_different = new_games != @current_data.games
            any_updates |= is_game_data_different
            Log.trace { "  is_game_data_different=#{is_game_data_different}" }
            @current_data.games = new_games
          end

          if any_updates
            Log.trace { "drawing to client" }
            @tx.send({@ident, @current_data})
          end

          if is_game_data_different &&
             !@current_data.games.nil? &&
             @current_data.games.not_nil!.all? { |g| g["data"]["gameComplete"].as_bool } &&
             @current_data.games.not_nil!.all? { |g| get_time(g["startTime"], g["endTime"]) < Time::Span.new(hours: 1) }
            @last_data_fetch_time = Time.utc

            Log.debug { "sleeping until top of next hour" }
            counter = 0
            sleep get_top_of_next_hour(@last_data_fetch_time) - @last_data_fetch_time
            has_sim_data_been_fetched_for_new_day = false
          else
            counter += @loop_frequency_seconds
            sleep @loop_frequency_seconds.seconds
          end
        end
      rescue ex
        Log.error(exception: ex) { }
      ensure
        Log.info { "loop ended at time #{Time.utc}" }
        @running = false
      end
    end
  end

  def close
    @running = false
  end

  def get_sim : Hash(String, JSON::Any)?
    response = get_chron_entity("Sim")
    if response.nil?
      return
    end
    return response.not_nil![0]["data"].as_h
  end

  def get_teams : Array(JSON::Any)?
    response = get_chron_entity("Team")
    if response.nil?
      return
    end
    return response.not_nil!.as_a.map { |e| e["data"] }
  end

  def get_chron_entity(entity_type : String) : JSON::Any?
    url = URI.parse(ENV["CHRONICLER_URL"] ||= "https://api.sibr.dev/chronicler/")
    url.query = URI::Params.encode({"type" => entity_type})
    url.path = (Path.new(url.path) / "v2" / "entities").to_s

    begin
      response = HTTP::Client.get url
      if response.success?
        messages = JSON.parse response.body
        return messages["items"]
      else
        Log.error { "http request failed" }
        Log.error { url }
        Log.error { response.status_code }
        return
      end
    rescue ex
      Log.error(exception: ex) { }
      return
    end
  end

  def get_games(day : Int32, season : Int32, sim : String) : Array(JSON::Any)?
    url = URI.parse(ENV["CHRONICLER_URL"] ||= "https://api.sibr.dev/chronicler/")
    url.query = URI::Params.encode({"day" => day.to_s, "season" => season.to_s, "sim" => sim})
    url.path = (Path.new(url.path) / "v1" / "games").to_s

    begin
      response = HTTP::Client.get url

      if response.success?
        messages = JSON.parse response.body
        return messages["data"].as_a
      else
        puts "http request failed"
        pp url
        pp response.status_code
        return
      end
    rescue ex
      Log.error(exception: ex) { }
      return
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
