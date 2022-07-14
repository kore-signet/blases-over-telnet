require "colorize"
require "./sources.cr"
require "./weather_map.cr"

def make_ord(number : Number) : String
  if number > 10 && number.to_s[-2] == '1'
    return "#{number}th"
  end

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

def make_newlines(input : String) : String
  line_break_regex = /(?<!\r)\n/
  result = input
  regex_match = input.match(line_break_regex)
  while regex_match
    result = result.sub(line_break_regex, "\r\n")
    regex_match = result.match(line_break_regex)
  end
  return result
end

def move_lines(input : String, column : Int, row : Int) : Tuple(String, Int32)
  line_break_regex = /(\r\n|\n\r)/
  result = "\x1b[#{row};#{column}H#{input}"
  row += 1
  regex_match = input.match(line_break_regex)
  while regex_match
    result = result.sub(line_break_regex, "\x1b[#{row};#{column}H")
    row += 1
    regex_match = result.match(line_break_regex)
  end
  return {result, row}
end

class Colorizer
  property color_map : ColorMap
  property source_data : SourceData
  property settings : UserSettings
  property current_game : Hash(String, JSON::Any)

  def initialize(
    @color_map,
    @source_data,
    @settings,
    @current_game = Hash(String, JSON::Any).new
  )
  end

  def colorize_string_for_team(
    away? : Bool,
    string : String
  ) : String
    color = get_colour_for_team @current_game[away? ? "awayTeam" : "homeTeam"].as_s
    if !color.nil?
      color = @color_map.get_hex_color @current_game[away? ? "awayTeamColor" : "homeTeamColor"].as_s
    end

    string
      .colorize
      .bold
      .fore(color.not_nil!)
      .to_s
  end

  def get_colour_for_team(team_id : String) : Colorize::Color256?
    team : JSON::Any? = @source_data.teams.nil? ? nil : @source_data.teams.not_nil!.[team_id]?
    if !team.nil?
      main_color : {UInt8, UInt8, UInt8} = convert_hex_string_to_int_tuple team["mainColor"].as_s
      secondary_color : {UInt8, UInt8, UInt8} = convert_hex_string_to_int_tuple team["secondaryColor"].as_s
      return @color_map.pick_contrast_colour *main_color, *secondary_color, *@settings.background, @settings.contrast_threshold
    end
  end
end

abstract class Layout
  abstract def clear_last
end

class DefaultLayout < Layout
  property last_message : String = ""
  property last_teams : Hash(String, JSON::Any) = Hash(String, JSON::Any).new
  property colorizer : Colorizer
  property feed_season_list : Hash(String, JSON::Any)
  property weather_map : WeatherMap

  def initialize(@colorizer, @feed_season_list, @weather_map)
  end

  def render(
    message : SourceData,
    settings : UserSettings
  )
    message.teams.try do |teams|
      @last_teams = teams
    end

    if message.games.nil? || message.sim.nil?
      return @last_message
    end

    @last_message = String.build do |m|
      m << "\x1b7"          # bell
      m << "\x1b[1A\x1b[1J" # move cursor up one, clear from cursor to beginning of screen.
      m << "\x1b[1;1H"      # move cursor to top left of screen
      m << "\x1b[0J"        # clear from cursor to end of screen

      sim = message.sim.not_nil!
      readable_day = sim["day"].as_i + 1

      m << %(Day #{readable_day}, Season #{sim["season"].as_i + 1}).colorize.bold.to_s
      m << "\n\r"
      m << render_season_identifier @colorizer, message

      if message.games == 0
        m << "No games for day #{readable_day}"
      else
        start_offset = 4
        current_row_for_column = Array.new(settings.number_of_columns, start_offset)
        column = 0

        if !settings.use_columns
          m << "\r\n"
        end

        message.games
          .not_nil!
          .sort_by { |g| get_team_ordering g["data"] }
          .each do |game|
            colorizer.current_game = game["data"].as_h
            game_string = render_game colorizer, game, settings
            if settings.use_columns
              game_string, current_row_for_column[column] = move_lines(game_string, column * settings.column_width, current_row_for_column[column])
              column = (column + 1) % settings.number_of_columns
              m << game_string
            else
              m << game_string
              m << "\r\n"
            end
          end
        m << "\r\n"
      end

      m << "\x1b7"
    end

    @last_message
  end

  def get_team_ordering(
    game : JSON::Any
  ) : String
    away_team_name = get_team_name game, true
    home_team_name = get_team_name game, false
    if away_team_name == "nullteam"
      return "ZZZ#{home_team_name}"
    elsif home_team_name == "nullteam"
      return "ZZZ#{away_team_name}"
    end
    return away_team_name
  end

  def get_team_name(
    game : JSON::Any,
    away : Bool
  ) : String
    get_team_identifier game, away, "awayTeamName", "homeTeamName", "fullName"
  end

  def get_team_nickname(
    game : JSON::Any,
    away : Bool
  ) : String
    get_team_identifier game, away, "awayTeamNickname", "homeTeamNickname", "nickname"
  end

  def get_team_identifier(
    game : JSON::Any,
    away : Bool,
    away_game_identifier : String,
    home_game_identifier : String,
    identifier : String
  ) : String
    if @last_teams
      target_team_id = game[away ? "awayTeam" : "homeTeam"]
      team = @last_teams[target_team_id]?
      if !team.nil?
        team_name = team[identifier].to_s
        team_state = team["state"]?
        if !team_state.nil?
          team_state_scattered = team_state.not_nil!["scattered"]?
          if !team_state_scattered.nil?
            team_name = team_state_scattered[identifier].to_s
          end
        end
        return team_name
      end
      return "Unknown Team"
    else
      return away ? game[away_game_identifier].to_s : game[home_game_identifier].to_s
    end
  end

  def render_game(
    colorizer : Colorizer,
    game_wrapper : JSON::Any,
    settings : UserSettings
  ) : String
    game = game_wrapper["data"]

    away_team_name = get_team_name(game, true)
    home_team_name = get_team_name(game, false)
    away_team_nickname = get_team_nickname(game, true)
    home_team_nickname = get_team_nickname(game, false)
    String.build do |m|
      if settings.debug
        m << "duration "
        m << get_time(game_wrapper["startTime"], game_wrapper["endTime"])
        m << "\r\n"
      end

      m << %(#{colorizer.colorize_string_for_team true, away_team_name})
      m << %( #{"@".colorize.underline} )
      m << %(#{colorizer.colorize_string_for_team false, home_team_name})
      m << %{ (#{colorizer.colorize_string_for_team true, game["awayScore"].to_s} v #{colorizer.colorize_string_for_team false, game["homeScore"].to_s})}

      if settings.show_weather
        m << " ["
        m << @weather_map.display_weather game["weather"].as_i, settings
        m << "]"
      end

      m << "\n\r"

      if game["finalized"].as_bool?
        render_finalized_game colorizer, game, m, away_team_name, home_team_name, away_team_nickname, home_team_nickname
      else
        render_game_status colorizer, game, m

        last_update = make_newlines(game["lastUpdate"].as_s)
        m << last_update
        if !last_update.ends_with?("\r\n")
          m << "\r\n"
        end
      end
    end
  end

  def render_season_identifier(
    colorizer : Colorizer,
    message : SourceData
  ) : String
    sim = message.sim.not_nil!
    id = sim["id"].to_s

    if id != "thisidisstaticyo"
      collection = @feed_season_list["items"][0]["data"]["collection"].as_a.index_by { |s| s["sim"] }
      if collection.has_key? id
        return %(#{collection[id]["name"]}\r\n)
      elsif id == "gamma10"
        return "Gamma 4\r\n"
      else
        return "Unknown SIM #{id}\r\n"
      end
    else
      era_title = sim["eraTitle"].to_s
      sub_era_title = sim["subEraTitle"].to_s
      era_color = colorizer.color_map.get_hex_color sim["eraColor"].to_s
      sub_era_color = colorizer.color_map.get_hex_color sim["subEraColor"].to_s

      if !era_title.blank? && !sub_era_title.blank?
        return %(#{era_title.to_s.colorize.fore(era_color)} - #{sub_era_title.to_s.colorize.fore(sub_era_color)}\r\n).colorize.underline.to_s
      else
        return ""
      end
    end
  end

  def render_finalized_game(
    colorizer : Colorizer,
    game : JSON::Any,
    m : String::Builder,
    away_team_name : String,
    home_team_name : String,
    away_team_nickname : String,
    home_team_nickname : String
  ) : Nil
    away_team_name_colorized = colorizer.colorize_string_for_team true, away_team_nickname
    home_team_name_colorized = colorizer.colorize_string_for_team false, home_team_nickname

    if away_team_name == "nullteam"
      if home_team_name == "nullteam"
        m << "Game cancelled\r\n"
      else
        m << %(The #{home_team_name_colorized} #{"non-lost".colorize.underline} due to nullification.\r\n)
      end
    else
      if home_team_name == "nullteam"
        m << %(The #{away_team_name_colorized} #{"non-lost".colorize.underline} due to nullification.\r\n)
      else
        away_score = (game["awayScore"].as_f? || game["awayScore"].as_i?).not_nil!
        home_score = (game["homeScore"].as_f? || game["homeScore"].as_i?).not_nil!

        winning_team = away_score > home_score ? away_team_name_colorized : home_team_name_colorized
        losing_team = away_score > home_score ? home_team_name_colorized : away_team_name_colorized
        win_type = game["shame"].as_bool ? "shamed" : "won against"

        m << "The "
        m << winning_team
        m << " "
        m << win_type.colorize.underline
        m << " the "
        m << losing_team
        m << "\r\n"

        if !game["outcomes"]?.nil?
          game["outcomes"]
            .as_a
            .map { |outcome| outcome.to_s }
            .reject { |outcome| outcome =~ / won the / }
            .each do |outcome|
              outcome_as_lines = make_newlines outcome
              m << outcome_as_lines
              if !outcome_as_lines.ends_with? "\r\n"
                m << "\r\n"
              end
            end
        else
          m << "\r\n"
        end
      end
    end
  end

  def render_game_status(
    colorizer : Colorizer,
    game : JSON::Any,
    m : String::Builder
  ) : Nil
    if !game["state"]?.nil? && !game["state"]["prizeMatch"]?.nil?
      m << "Exhibition game".colorize.bold
      m << ". Prize: "
      m << game["state"]["prizeMatch"]["itemName"].to_s.colorize.bold
      m << "\r\n"
    elsif !game["isTitleMatch"]?.nil? && game["isTitleMatch"].as_bool?
      m << "Title Match: ".colorize.bold
      is_away_team_defending = @last_teams[game["awayTeam"].as_s]["permAttr"].as_a.any? { |attr| attr == "TITLE_BELT" }
      is_home_team_defending = @last_teams[game["homeTeam"].as_s]["permAttr"].as_a.any? { |attr| attr == "TITLE_BELT" }
      if is_away_team_defending && is_home_team_defending
        m << colorizer.colorize_string_for_team true, game["awayTeamName"].as_s
        m << " and ".colorize.bold
        m << colorizer.colorize_string_for_team false, game["homeTeamName"].as_s
        m << " defending\r\n"
      elsif is_away_team_defending
        m << %(#{colorizer.colorize_string_for_team true, game["awayTeamName"].as_s} defending\r\n)
      elsif is_home_team_defending
        m << %(#{colorizer.colorize_string_for_team false, game["homeTeamName"].as_s} defending\r\n)
      end
    end

    is_top_of_inning = game["topOfInning"].as_bool

    m << %(#{is_top_of_inning ? "Top of the" : "Bottom of the"} #{make_ord game["inning"].as_i + 1}).colorize.bold

    if is_top_of_inning
      m << %( - #{colorizer.colorize_string_for_team false, game["homePitcherName"].to_s} pitching)

      max_balls = game["awayBalls"].as_i?
      max_strikes = game["awayStrikes"].as_i?
      max_outs = game["awayOuts"].as_i?
      number_of_bases_including_home = game["awayBases"].as_i?
    else
      m << %( - #{colorizer.colorize_string_for_team true, game["awayPitcherName"].to_s} pitching)

      max_balls = game["homeBalls"].as_i?
      max_strikes = game["homeStrikes"].as_i?
      max_outs = game["homeOuts"].as_i?
      number_of_bases_including_home = game["homeBases"].as_i?
    end

    m << "\n\r"
    m << game["atBatBalls"]
    if max_balls && max_balls != 4
      m << %( (of #{max_balls}))
    end

    m << "-"

    m << game["atBatStrikes"]
    if max_strikes && max_strikes != 3
      m << %( (of #{max_strikes}))
    end

    bases_occupied = game["basesOccupied"].as_a
    if bases_occupied.size == 0
      m << ". Nobody on"
    else
      bases_occupied = bases_occupied.map { |b| b.as_i }
      m << ". #{bases_occupied.size} on ("

      number_bases = bases_occupied.max + 1
      if number_of_bases_including_home && number_bases < (number_of_bases_including_home - 1)
        number_bases = number_of_bases_including_home - 1
      end
      if number_bases < 3
        number_bases = 3
      end

      bases = Array.new(number_bases, 0)
      bases_occupied.each do |b|
        bases[b] += 1
      end

      bases.reverse.each do |b|
        if b == 0
          m << "\u{25cb}"
        elsif b == 1
          m << "\u{25cf}"
        else
          m << b.to_s
        end
      end

      m << ")"
    end

    number_of_outs = game["halfInningOuts"]
    if number_of_outs == 0
      m << ", no outs"
    elsif number_of_outs == 1
      m << ", 1 out"
    else
      m << ", #{number_of_outs} outs"
    end

    if max_outs && max_outs != 3
      m << %( (of #{max_outs}))
    end
    m << ".\r\n"
  end

  def render_temporal(
    colorizer : Colorizer,
    temporal : Hash(String, JSON::Any)
  ) : String
    # alpha: number = number of peanuts that can be purchased
    # beta: number = squirrel count
    # gamma: number = entity id
    # delta: boolean = sponsor in store?
    # epsilon: boolean = is site takeover in process
    # zeta: string = actual output text

    if temporal.has_key? "doc"
      entity : Int32 = temporal["doc"]["gamma"].as_i
      zeta : String = make_newlines temporal["doc"]["zeta"].as_s
      if !zeta.blank?
        if @entities.entities_40.has_key? entity
          return "#{@entities.entities_40[entity]}#{zeta}"
        end
        return "#{@entities.entities_40[-1]}#{zeta}"
      end
    end
    return ""
  end

  def is_takeover_in_process : Bool
    if @last_temporal.has_key? "doc"
      if @last_temporal["doc"]["epsilon"]?
        return @last_temporal["doc"]["epsilon"].as_bool
      end
    end
    return false
  end

  def render_temporal_alert(
    message : String
  ) : String
    if message.starts_with? "Please Wait."
      return message[..1] << ".".mode(:blink)
    end
    return message
  end

  def clear_last : Nil
    @last_message = "\x1b7\x1b[1A\x1b[1J\x1b[1;1H\rloading..\x1b8"
  end
end
