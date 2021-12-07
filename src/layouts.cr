require "colorize"
color_map = ColorMap.new "color_data.json"

def make_ord(number : Number) : String
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

class Colorizer
  property color_map : ColorMap
  property current_game : Hash(String,JSON::Any)
  def initialize(@color_map, @current_game = Hash(String,JSON::Any).new)
  end

  def colorize_string_for_team(
      away? : Bool,
      string : String) : String
    string
    .colorize
    .bold
    .fore(@color_map.get_hex_color @current_game[away? ? "awayTeamColor" : "homeTeamColor"].as_s)
    .to_s
  end
end

colorizer = Colorizer.new color_map

abstract class Layout
  abstract def clear_last
end

class DefaultLayout < Layout
  property last_message : String = ""
  property last_league : Hash(String,JSON::Any) = Hash(String,JSON::Any).new
  property colorizer : Colorizer
  property feed_season_list : Hash(String,JSON::Any)

  def initialize(@colorizer, @feed_season_list)

  end

  def render(message)
    if message.has_key? "leagues"
      @last_league = message["leagues"].as_h
    end

    if !message.has_key? "games"
      return @last_message
    end

    games = message["games"]

    @last_message = String.build do |m|
      m << "\x1b7"
      m << "\x1b[1A\x1b[1J"
      m << "\x1b[1;1H"
      m << "\x1b[0J"
      m << %(Day #{games["sim"]["day"].as_i + 1}, Season #{games["sim"]["season"].as_i + 1}).colorize.bold.to_s
      m << "\n\r"
      m << render_season_identifier @colorizer, games.as_h

      games["schedule"].as_a.sort_by {|g| get_team_name g, true}.each do |game|
        colorizer.current_game = game.as_h
        m << render_game colorizer, game
      end

      m << "\x1b8"
    end

    @last_message
  end

  def get_team_name(
      game : JSON::Any,
      away : Bool) : String
    get_team_identifier game, away, "awayTeamName", "homeTeamName", "fullName"
  end

  def get_team_nickname(
      game : JSON::Any,
      away : Bool) : String
    get_team_identifier game, away, "awayTeamNickname", "homeTeamNickname", "nickname"
  end

  def get_team_identifier(
      game : JSON::Any,
      away : Bool,
      away_game_identifier : String,
      home_game_identifier : String,
      identifier : String) : String
    if @last_league.has_key? "teams"
      target_team_id = away ? game["awayTeam"] : game["homeTeam"]
      last_league["teams"].as_a.each do |team_json|
        team = team_json.as_h
        if team["id"] == target_team_id
          team_name = team[identifier].to_s
          if team.has_key? "state"
            team_state = team["state"].as_h
            if team_state.has_key? "scattered"
              team_name = team_state["scattered"].as_h[identifier].to_s
            end
          end
          return team_name
        end
      end
      raise "Team with id #{target_team_id} not found in sim league object"
    else
      return away ? game[away_game_identifier].to_s : game[home_game_identifier].to_s
    end
  end

  def render_game(
      colorizer : Colorizer,
      game : JSON::Any) : String
    away_team_name = get_team_name(game, true)
    home_team_name = get_team_name(game, false)
    away_team_nickname = get_team_nickname(game, true)
    home_team_nickname = get_team_nickname(game, false)
    String.build do |m|
      m << "\n\r"
      m << %(#{colorizer.colorize_string_for_team true, (away_team_name + " (#{game["awayScore"]})")})
      m << %( #{"@".colorize.underline} )
      m << %(#{colorizer.colorize_string_for_team false, (home_team_name + " (#{game["homeScore"]})")})
      m << "\n\r"
      m << %(#{game["topOfInning"].as_bool ? "Top of the" : "Bottom of the"} #{make_ord game["inning"].as_i+1}).colorize.bold

      if game["topOfInning"].as_bool
        m << %( - #{colorizer.colorize_string_for_team false, game["homePitcherName"].to_s} pitching)
      else
        m << %( - #{colorizer.colorize_string_for_team true, game["awayPitcherName"].to_s} pitching)
      end

      m << "\n\r"

      if game["finalized"].as_bool?
        away_score = (game["awayScore"].as_f? || game["awayScore"].as_i?).not_nil!
        home_score = (game["homeScore"].as_f? || game["homeScore"].as_i?).not_nil!
        if away_score > home_score
          m << %(The #{colorizer.colorize_string_for_team true, away_team_nickname} #{"won against".colorize.underline} the #{colorizer.colorize_string_for_team false, home_team_nickname})
        else
          m << %(The #{colorizer.colorize_string_for_team false, home_team_nickname} #{"won against".colorize.underline} the #{colorizer.colorize_string_for_team true, away_team_nickname})
        end
        m << "\n\r"
      else
        m << make_newlines(game["lastUpdate"].as_s)
      end
    end
  end

  def render_season_identifier(
    colorizer : Colorizer,
    games : Hash(String, JSON::Any)) : String
    sim = games["sim"]
    id = sim["id"].to_s

    if id != "thisidisstaticyo"
      collection = @feed_season_list["items"][0]["data"]["collection"].as_a.index_by { |s| s["sim"] }
      return %(#{collection[id]["name"]}\r\n)
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

  def clear_last : Nil
    @last_message = "\x1b7\x1b[1A\x1b[1J\x1b[1;1H\rloading..\x1b8"
  end
end
