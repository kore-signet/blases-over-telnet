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
  getter minimum_sleep_timer_seconds : UInt8 = 10

  def initialize(
    @ident : String,
    @tx : Channel({String, SourceData})
  )
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

    new_sim = get_sim
    if new_sim.nil?
      Log.error { "failed to get live data" }
      return
    end

    @current_data.sim = new_sim
    Log.trace { "live sim data fetched" }

    all_games = get_all_games new_sim.not_nil!["season"].as_i, new_sim.not_nil!["id"].as_s
    if !all_games.nil?
      Log.trace { "past game data fetched" }
      @current_data.past_games = all_games
    else
      Log.error { "failed to get games " }
    end

    @running = true
    @sleeping = false

    spawn do
      begin
        counter = 0
        has_sim_data_been_fetched_for_new_day = true

        while @running
          Log.trace { "counter=#{counter}, has_sim_data_been_fetched_for_new_day=#{has_sim_data_been_fetched_for_new_day}" }
          any_updates = false
          if counter % @sim_fetch_frequency_seconds == 0 || !has_sim_data_been_fetched_for_new_day
            new_sim = get_sim
            if !new_sim.nil?
              Log.trace { "live sim data fetched" }
              if !@current_data.sim.nil?
                previous_day = @current_data.sim.not_nil!["day"]
                new_day = new_sim.not_nil!["day"]
                has_sim_data_been_fetched_for_new_day |= new_day != previous_day
                any_updates |= has_sim_data_been_fetched_for_new_day
                Log.trace { "  is_sim_data_different=#{has_sim_data_been_fetched_for_new_day} (previous_day=#{previous_day}, new_day=#{new_day})" }
              else
                has_sim_data_been_fetched_for_new_day = true
                any_updates = true
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

          new_games = get_most_recent_event_for_games current_sim["day"].as_i, current_sim["season"].as_i, current_sim["id"].as_s
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
             counter > minimum_sleep_timer_seconds &&
             !@current_data.games.nil? &&
             @current_data.games.not_nil!.all? { |g| g["data"]["gameComplete"].as_bool } &&
             @current_data.games.not_nil!.all? { |g| get_time(g["startTime"], g["endTime"]) < Time::Span.new(hours: 1) }
            @last_data_fetch_time = Time.utc

            @current_data.games.not_nil!.each { |g| @current_data.past_games.not_nil!.push g }

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

  def get_teams : Hash(TeamId, TeamData)?
    response = get_chron_entity("Team")
    if response.nil?
      return
    end
    return response.not_nil!.as_a.to_h { |e| {e["entityId"].to_s, e["data"].as_h} }
  end

  def get_chron_entity(entity_type : String) : JSON::Any?
    url = URI.parse(ENV["CHRON_API_URL"])
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

  def last_data : SourceData
    @current_data
  end
end
