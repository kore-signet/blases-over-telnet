require "log"
require "http"
require "./base_source.cr"
require "./source_data.cr"

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
  property current_zero_indexed_day : Int32 = -1
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
    @tx : Channel({String, SourceData}),
    should_autostart : Bool = true
  )
    @current_time = start_time
    @current_data = SourceData.new

    if should_autostart
      start
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
        if time_that_next_data_expires <= @current_time
          Log.error &.emit "Time was incorrect", time_that_next_data_expires: time_that_next_data_expires, current_time: @current_time
          raise "Didn't increment current time, attempted to sleep for no seconds, would loop infinitely"
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

    Log.trace &.emit "Getting time that data expires", current_time: @current_time

    if !@historic_sims.nil? && @historic_sims.not_nil!.size > 0
      next_sim_valid_from = Time::Format::ISO_8601_DATE_TIME.parse @historic_sims.not_nil![0]["validFrom"].as_s
      if next_sim_valid_from < max_time && @current_time < next_sim_valid_from
        Log.trace &.emit "Updating max time to be sim time", current_max: max_time, new_max: next_sim_valid_from
        max_time = next_sim_valid_from
      end
    else
      Log.trace { "no sims" }
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
    if @historic_games.size == 0
      Log.warn { "No games" }
    else
      @historic_games.each do |game_id, game_updates|
        Log.trace { "considering game #{game_id}, with #{game_updates.size} updates" }

        if game_updates.size > 0
          next_update_timestamp = Time::Format::ISO_8601_DATE_TIME.parse game_updates[0]["timestamp"].as_s

          if next_update_timestamp > @current_time
            Log.trace { "\tnot removing game updates #{game_id}/#{next_update_timestamp}" }
          else
            while next_update_timestamp <= @current_time
              Log.trace { "\tremoving game update #{game_id}/#{next_update_timestamp} in get_time_next_data_expires because timestamp in the past" }
              game_updates.shift
              next_update_timestamp = Time::Format::ISO_8601_DATE_TIME.parse game_updates[0]["timestamp"].as_s
            end
          end

          if next_update_timestamp < max_time
            if @current_time < next_update_timestamp
              Log.trace &.emit "Updating max time to be game time", current_max: max_time, new_max: next_update_timestamp, game_id: game_id
              max_time = next_update_timestamp
            else
              Log.warn &.emit "Events which have happened should have been removed in previous step", game_id: game_id, current_time: @current_time, update_timestamp: next_update_timestamp, number_of_updates: game_updates.size
            end
          else
            Log.trace &.emit "Not updating because max time is closer to now than event time", current_max: max_time, new_max: next_sim_valid_from, game_id: game_id, number_of_updates: game_updates.size
          end
        end
      end
    end

    if max_time == Time.utc(9999, 10, 4)
      raise "max time not set"
    end

    return max_time
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
      Log.trace &.emit "Updating current data for sim", next: next_sim_valid_from, current: @current_time
      pending_sim = @historic_sims.not_nil!.shift["data"].as_h

      new_zero_indexed_day = pending_sim.not_nil!["day"].as_i

      if new_zero_indexed_day < @current_zero_indexed_day
        Log.trace &.emit "uppy downy (discarding sim because it's in the past)"
        # technically didn't update but we don't want to end the playback because of it
        return DataChangeStatus::Updated
      end

      if new_zero_indexed_day == @current_zero_indexed_day
        return DataChangeStatus::NoChanges
      end
      
      Log.trace &.emit "\tupdated day (0-indexed)", ident: @ident, old_zero_indexed_day: @current_zero_indexed_day, new_zero_indexed_day: new_zero_indexed_day
      @current_zero_indexed_day = new_zero_indexed_day
      @current_season = pending_sim.not_nil!["season"].as_i
      current_sim_id = pending_sim.not_nil!["sim"]?
      if current_sim_id.nil?
        @current_sim_id_yo = "thisidisstaticyo"
      else
        @current_sim_id_yo = current_sim_id.not_nil!.as_s
      end
      @current_sim = pending_sim

      Log.trace &.emit "Rejecting historic games which are not today or later, or which have no events", number_of_historic_games: @historic_games.size
      @historic_games.reject! do |_game_id, updates_for_game|
        # keep if there are updates, and the updates are for today or tomorrow
        updates_for_game.size > 0 && updates_for_game[0]["data"]["day"].as_i >= @current_zero_indexed_day
      end
      Log.trace &.emit "\trejection finished", number_of_historic_games: @historic_games.size

      return DataChangeStatus::Updated
    else
      Log.trace &.emit "Not updating current data for sim", next: next_sim_valid_from, current: @current_time
    end

    DataChangeStatus::NoChanges
  end

  def update_current_game_event_for_all_ongoing_games : DataChangeStatus
    if have_all_games_finished
      Log.trace &.emit "all games for current day have finished, fetching game data for next day", fetching_for_one_indexed_day: (@current_zero_indexed_day + 1)
      # nb: if this increments the game day, must be sure that we don't end up sending out these as new dates and showing "game started" between
      # end of games one day and start the next
      get_all_updates_for_all_games_for_day_and_push_to_historic_games @current_sim_id_yo, @current_season, @current_zero_indexed_day
    end

    any_games_updated = false
    is_first_time = @current_games.size == 0

    @historic_games.each do |game_id, updates_for_game|
      Log.trace { "incrementing current data for game #{game_id}, current number of updates #{updates_for_game.size}" }
      if updates_for_game.size > 0
        time_of_next_update = Time::Format::ISO_8601_DATE_TIME.parse updates_for_game[0]["timestamp"].as_s

        Log.trace &.emit "there are updates for game", time_of_next_update: time_of_next_update, current_time: @current_time

        if is_first_time || time_of_next_update <= @current_time
          @current_games[game_id] = updates_for_game.shift

          # i have no idea how this is going to work with cancelled games in s24. s24 my beloathed
          # turns out fine. those games _did_ start, weirdly
          while !@current_games[game_id]["data"]["gameStart"].as_bool && updates_for_game.size > 0
            Log.info &.emit "Discarding update for game, bcs game hasn't started yet", game_id: game_id, timestamp: time_of_next_update

            Log.trace { "\tremoving game update #{game_id}/#{time_of_next_update} in update_game_event_for_all_ongoing_games because timestamp in the past" }
            @current_games[game_id] = updates_for_game.shift
            time_of_next_update = Time::Format::ISO_8601_DATE_TIME.parse @current_games[game_id]["timestamp"].as_s
          end

          Log.info &.emit "Pushing update for game", game_id: game_id, timestamp: time_of_next_update, next_timestamp: Time::Format::ISO_8601_DATE_TIME.parse updates_for_game[0]["timestamp"].as_s
          Log.trace &.emit "\tRemaining updates", game_id: game_id, number_of_updates: updates_for_game.size

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
      game_zero_indexed_day = data["day"].as_i
      # in b4 falsehoods: should only need to check that the days match, not also season/sim
      if @current_zero_indexed_day == game_zero_indexed_day
        return data["gameComplete"].as_bool
      end
    end
    return true
  end

  def update_current_data : Nil
    @current_data.sim = @current_sim
    @current_data.games = @current_games.values.select { |update_for_game| update_for_game["data"]["day"].as_i == @current_zero_indexed_day }
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
    Log.info { "Should update current data? sim: #{sim_data_change_status}, team: #{team_data_change_status}, games: #{games_data_change_status} " }

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

  def get_all_updates_for_all_games_for_day_and_push_to_historic_games(sim_id_yo : String, season : Int32, zero_indexed_day : Int32) : Nil
    Log.trace &.emit "Fetching game list for specific day", zero_indexed_day: zero_indexed_day, season: season, sim: sim_id_yo
    most_recent_events_for_games_for_day = get_most_recent_event_for_games zero_indexed_day, season, sim_id_yo

    if most_recent_events_for_games_for_day.nil? || most_recent_events_for_games_for_day.not_nil!.size == 0
      Log.warn &.emit "Did not get any last_updates for games for specific day", zero_indexed_day: zero_indexed_day, season: season, sim: sim_id_yo
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
