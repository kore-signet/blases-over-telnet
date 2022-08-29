alias SimDataOverTime = Array(SimData)
alias TeamDataOverTime = Array(TeamData)
alias GameDataOverTime = Array(GameData)

class ChroniclerSource < Source
  property tx : Channel({String, SourceData})
  property ident : String
  property clients : Int32 = 0
  property current_data : SourceData
  property running : Bool = false

  property current_time : Time

  property current_sim_id_yo : String = "thisidisstaticyo"
  property current_day : Int32 = -1
  property current_season : Int32 = -2

  property current_sim : SimData? = nil
  property current_teams : Hash(TeamId, TeamData) = Hash(TeamId, TeamData).new
  property current_games : Hash(GameId, GameData) = Hash(GameId, GameData).new

  property historic_sims : SimDataOverTime? = nil
  property historic_teams : Hash(TeamId, TeamDataOverTime) = Hash(TeamId, TeamDataOverTime).new
  property historic_games : Hash(GameId, GameDataOverTime) = Hash(GameId, GameDataOverTime).new

  def initialize(
    start_time : Time,
    @ident : String,
    @tx : Channel({String, SourceData})
  )
    @current_time = start_time
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

    Log.info &.emit "Starting historic source", ident: @ident

    @running = true

    spawn do
      while @running
        sim_data_change_status = update_day_and_season_if_necessary

        games_data_change_status = update_current_game_event_for_all_ongoing_games

        team_data_change_status = update_teams_if_necessary

        if any_data_has_been_updated sim_data_change_status, games_data_change_status, team_data_change_status
          Log.info { "Updating current data" }
          update_current_data
          @tx.send({@ident, @current_data})
        elsif all_data_is_finished sim_data_change_status, games_data_change_status, team_data_change_status
          @running = false
          break
        end

        if have_all_games_finished
          skip_to_start_of_next_day_if_desired
        end
        time_that_next_data_expires = get_time_that_next_data_expires
        if time_that_next_data_expires == @current_time
          # no
          pp time_that_next_data_expires
          pp @current_time
          raise "Somehow... palpatine has returned"
        end

        time_to_next_event = time_that_next_data_expires - @current_time
        Log.info &.emit "Historic source sleeping", ident: @ident, current_time: @current_time, time_that_next_data_expires: time_that_next_data_expires, sleeping_for: time_to_next_event.total_milliseconds
        sleep time_to_next_event

        Log.trace &.emit "Setting time for historic playback", ident: @ident, new_time: time_that_next_data_expires
        @current_time = time_that_next_data_expires
      end

      Log.debug &.emit "Historic playback ended", ident: @ident, current_time: @current_time
    end
  end

  def get_time_that_next_data_expires : Time
    # let me set my max time to 20020, crystal
    max_time : Time = Time.utc(9999, 10, 4)

    Log.trace { "Getting time that data expires" }

    if !@historic_sims.nil? && @historic_sims.not_nil!.size > 0
      next_sim_valid_from = Time::Format::ISO_8601_DATE_TIME.parse @historic_sims.not_nil![0]["validFrom"].as_s
      if next_sim_valid_from < max_time && @current_time < next_sim_valid_from
        Log.trace &.emit "Updating max time to be sim time", current_max: max_time, new_max: next_sim_valid_from
        max_time = next_sim_valid_from
      end
    end

    @historic_teams.each do |team_id, team_data_over_time|
      if team_data_over_time.size > 0
        next_data_for_team_valid_from = Time::Format::ISO_8601_DATE_TIME.parse team_data_over_time[0]["validFrom"].as_s
        if next_data_for_team_valid_from < max_time
          Log.trace &.emit "Updating max time to be team time", current_max: max_time, new_max: next_sim_valid_from, team_id: team_id
          max_time = next_data_for_team_valid_from
        end
      end
    end

    # we could avoid the size > 0 here and just leave it up to the iterator, but it's conceivable that there might be
    # no games, whereas there should always be teams
    if @historic_games.size > 0
      @historic_games.each do |game_id, game_updates|
        if game_updates.size > 0
          next_update_timestamp = Time::Format::ISO_8601_DATE_TIME.parse game_updates[0]["timestamp"].as_s
          if next_update_timestamp < max_time
            Log.trace &.emit "Updating max time to be game time", current_max: max_time, new_max: next_sim_valid_from, game_id: game_id
            max_time = next_update_timestamp
          end
        end
      end
    end

    return @current_time
  end

  def update_day_and_season_if_necessary : DataChangeStatus
    if @historic_sims.nil? || @historic_sims.not_nil!.empty?
      @historic_sims = fetch_historic_sims
      if @historic_sims.nil? || @historic_sims.not_nil!.empty?
        Log.debug &.emit "Historic replay stopped because there was no more sim data", current_time: @current_time
        return DataChangeStatus::NoMoreData
      end
    end

    next_sim_valid_from = Time::Format::ISO_8601_DATE_TIME.parse @historic_sims.not_nil![0]["validFrom"].as_s
    if next_sim_valid_from <= @current_time
      @current_sim = @historic_sims.not_nil![0]["data"].as_h

      current_sim_id = @current_sim.not_nil!["sim"]?
      if current_sim_id.nil?
        @current_sim_id_yo = "thisidisstaticyo"
      else
        @current_sim_id_yo = current_sim_id.not_nil!.as_s
      end
      @current_season = @current_sim.not_nil!["season"].as_i
      @current_day = @current_sim.not_nil!["day"].as_i

      @historic_games.reject! do |_game_id, updates_for_game|
        updates_for_game.size > 0 || updates_for_game[0]["day"] == @current_day
      end

      return DataChangeStatus::Updated
    end

    DataChangeStatus::NoChanges
  end

  def update_current_game_event_for_all_ongoing_games : DataChangeStatus
    if have_all_games_finished
      Log.trace &.emit "all games for current day have finished, fetching game data for next day", fetching_for: (@current_day + 1)
      # nb: if this increments the game day, must be sure that we don't end up sending out these as new dates and showing "game started" between
      # end of games one day and start the next
      get_all_updates_for_all_games_for_day_and_push_to_historic_games @current_sim_id_yo, @current_season, @current_day + 1
    end

    any_games_updated = false
    is_first_time = @current_games.size == 0

    @historic_games.each do |game_id, updates_for_game|
      if updates_for_game.size > 0
        time_of_next_update = Time::Format::ISO_8601_DATE_TIME.parse updates_for_game[0]["timestamp"].as_s
        if is_first_time || time_of_next_update <= @current_time
          @current_games[game_id] = updates_for_game.shift

          # i have no idea how this is going to work with cancelled games in s24. s24 my beloathed
          # turns outl fnine. those games _did_ start, weirdly
          while !@current_games[game_id]["data"]["gameStart"].as_bool && updates_for_game.size > 0
            Log.info &.emit "Discarding update for game, bcs game hasn't started yet", game_id: game_id, timestamp: time_of_next_update

            @current_games[game_id] = updates_for_game.shift
            time_of_next_update = Time::Format::ISO_8601_DATE_TIME.parse @current_games[game_id]["timestamp"].as_s
          end

          Log.info &.emit "Pushing update for game", game_id: game_id, timestamp: time_of_next_update, next_timestamp: Time::Format::ISO_8601_DATE_TIME.parse updates_for_game[0]["timestamp"].as_s
          any_games_updated = true
        end
      end
    end

    if any_games_updated
      Log.info &.emit "Games have updated", ident: @ident
      return DataChangeStatus::Updated
    else
      return DataChangeStatus::NoChanges
    end
  end

  def update_teams_if_necessary : DataChangeStatus
    if @current_teams.size > 0
      return DataChangeStatus::NoChanges
    end

    current_teams = get_teams_currently
    if current_teams.nil?
      raise "Could not get team entities data from chron"
    end
    @current_teams = current_teams.not_nil!
    return DataChangeStatus::Updated
  end

  def have_all_games_finished : Bool
    @current_games.all? do |_, update_for_game|
      data = update_for_game["data"]
      game_day = data["day"].as_i
      # in b4 falsehoods: should only need to check that the days match, not also season/sim
      if @current_day == game_day
        return data["gameComplete"].as_bool
      end
    end
    return true
  end

  def update_current_data : Nil
    @current_data.sim = @current_sim
    @current_data.games = @current_games.values.select { |update_for_game| update_for_game["data"]["day"].as_i == @current_day }
    @current_data.teams = @current_teams
  end

  def skip_to_start_of_next_day_if_desired : Nil
  end

  enum DataChangeStatus
    NoChanges
    Updated
    NoMoreData
  end

  def any_data_has_been_updated(
    sim_data_change_status : DataChangeStatus,
    games_data_change_status : DataChangeStatus,
    team_data_change_status : DataChangeStatus
  ) : Bool
    sim_data_change_status == DataChangeStatus::Updated ||
      games_data_change_status == DataChangeStatus::Updated ||
      team_data_change_status == DataChangeStatus::Updated
  end

  def all_data_is_finished(
    sim_data_change_status : DataChangeStatus,
    games_data_change_status : DataChangeStatus,
    team_data_change_status : DataChangeStatus
  ) : Bool
    sim_data_change_status == DataChangeStatus::NoMoreData ||
      games_data_change_status == DataChangeStatus::NoMoreData ||
      team_data_change_status == DataChangeStatus::NoMoreData
  end

  def close
    @running = false
  end

  def fetch_historic_sims : SimDataOverTime?
    Log.trace &.emit "Fetching sim data", time: @current_time
    sim_data_response = get_chron_versions "Sim", @current_time

    if sim_data_response.nil?
      return nil
    end

    return sim_data_response.not_nil!.map { |sim_data| sim_data.as_h }
  end

  def get_all_updates_for_all_games_for_day_and_push_to_historic_games(sim_id_yo : String, season : Int32, day : Int32) : Nil
    Log.trace &.emit "Fetching game list for specific day", day: day, season: season, sim: sim_id_yo
    most_recent_events_for_games_for_day = get_most_recent_event_for_games day - 1, season, sim_id_yo

    if most_recent_events_for_games_for_day.nil? || most_recent_events_for_games_for_day.not_nil!.size == 0
      Log.warn &.emit "Did not get any last_updates for games for specific day", day: day, season: season, sim: sim_id_yo
      return
    end

    most_recent_events_for_games_for_day.not_nil!.each do |game|
      game_id : GameId = (game["data"]["id"]? || game["data"]["_id"]).as_s
      game_updates = get_all_updates_for_game(game_id)
      if game_updates.nil?
        Log.error &.emit "Failed to get data for game", game_id: game_id
      else
        Log.trace &.emit "Successfully fetched game updates", game_id: game_id, number_of_updates: game_updates.not_nil!.size
        @historic_games[game_id] = game_updates.not_nil!
      end
    end
  end

  def get_all_updates_for_game(game_id : GameId) : GameDataOverTime?
    url = URI.parse(ENV["CHRON_API_URL"])
    url.query = URI::Params.encode({
      "game" => game_id,
      # reblase uses 2000 as the size, and that's fine for the semicentennial
      # inb4 falsehoods
      "count" => 2000.to_s,
    })
    url.path = (Path.new(url.path) / "v1" / "games" / "updates").to_s

    begin
      response = HTTP::Client.get url

      if response.success?
        messages = JSON.parse response.body
        return messages["data"].as_a.map { |game| game.as_h }
      else
        Log.error &.emit "Http request failed", url: url.to_s, status_code: response.status_code
      end
    rescue ex
      Log.error(exception: ex) { }
      return
    end
  end

  def get_chron_versions(entity_type : String, from_time : Time) : Array(JSON::Any)?
    url = URI.parse(ENV["CHRON_API_URL"])
    url.query = URI::Params.encode({
      "type"  => entity_type,
      "after" => Time::Format::ISO_8601_DATE_TIME.format(from_time),
    })
    url.path = (Path.new(url.path) / "v2" / "versions").to_s

    begin
      response = HTTP::Client.get url
      if response.success?
        messages = JSON.parse response.body
        return messages["items"].as_a
      else
        Log.error { "http request failed" }
        Log.error { url }
        Log.error { response.status_code }
        return nil
      end
    rescue ex
      Log.error(exception: ex) { }
      return nil
    end
  end

  def get_teams_currently : Hash(TeamId, TeamData)?
    url = URI.parse(ENV["CHRON_API_URL"])
    url.query = URI::Params.encode({"type" => "team"})
    url.path = (Path.new(url.path) / "v2" / "entities").to_s

    begin
      response = HTTP::Client.get url
      if response.success?
        messages = JSON.parse response.body
        return messages["items"].as_a.to_h { |team| {team["entityId"].as_s, team["data"].as_h} }
      else
        Log.error { "http request failed" }
        Log.error { url }
        Log.error { response.status_code }
        return nil
      end
    rescue ex
      Log.error(exception: ex) { }
      return nil
    end
  end

  def last_data : SourceData
    @current_data
  end
end
