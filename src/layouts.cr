require "colorize"
color_map = ColorMap.new "color_data.json"

def make_ord(number)
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

class Colorizer
  property color_map : ColorMap
  property current_game : Hash(String,JSON::Any)
  def initialize(@color_map, @current_game = Hash(String,JSON::Any).new)
  end

  def colorize(away?, string)
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

  def initialize(@colorizer)

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
      m << %(Day #{games["sim"]["day"].as_i + 1}, Season #{games["sim"]["season"].as_i + 1}).colorize.bold.to_s
      m << "\n\r"
      m << %(#{games["sim"]["eraTitle"].to_s.colorize.fore(@colorizer.color_map.get_hex_color games["sim"]["eraColor"].to_s)} - #{games["sim"]["subEraTitle"].to_s.colorize.fore(@colorizer.color_map.get_hex_color games["sim"]["subEraColor"].to_s)}).colorize.underline.to_s
      m << "\n\r"

      games["schedule"].as_a.sort_by {|g| get_team_name g, true}.each do |game|
        colorizer.current_game = game.as_h
        m << render_game colorizer, game
      end

      m << "\x1b8"
    end

    @last_message
  end

  def get_team_name(game : JSON::Any, away : Bool)
    if @last_league.has_key? "teams"
      target_team_id = away ? game["awayTeam"] : game["homeTeam"]
      last_league["teams"].as_a.each do |team_json|
        team = team_json.as_h
        if team["id"] == target_team_id
          team_name = team["fullName"].to_s
          if team.has_key? "state"
            team_state = team["state"].as_h
            if team_state.has_key? "scattered"
              team_name = team_state["scattered"].as_h["fullName"].to_s
            end
          end
          return team_name
        end
      end
      raise "Team with id #{target_team_id} not found in sim league object"
    else
      return away ? game["awayTeamName"].to_s : game["homeTeamName"].to_s
    end
  end

  def get_team_nickname(game : JSON::Any, away : Bool)
    if @last_league.has_key? "teams"
      target_team_id = away ? game["awayTeam"] : game["homeTeam"]
      last_league["teams"].as_a.each do |team_json|
        team = team_json.as_h
        if team["id"] == target_team_id
          team_name = team["nickname"].to_s
          if team.has_key? "state"
            team_state = team["state"].as_h
            if team_state.has_key? "scattered"
              team_name = team_state["scattered"].as_h["nickname"].to_s
            end
          end
          return team_name
        end
      end
      raise "Team with id #{target_team_id} not found in sim league object"
    else
      return away ? game["awayTeamNickname"].to_s : game["homeTeamNickname"].to_s
    end
  end

  def render_game(colorizer,game)
    away_team_name = get_team_name(game, true)
    home_team_name = get_team_name(game, false)
    away_team_nickname = get_team_nickname(game, true)
    home_team_nickname = get_team_nickname(game, false)
    String.build do |m|
      m << "\n\r"
      m << %(#{colorizer.colorize true, (away_team_name + " (#{game["awayScore"]})")} #{"@".colorize.underline} #{colorizer.colorize false, (home_team_name + " (#{game["homeScore"]})")})
      m << "\n\r"
      m << %(#{game["topOfInning"].as_bool ? "Top of the" : "Bottom of the"} #{make_ord game["inning"].as_i+1}).colorize.bold

      if game["topOfInning"].as_bool
        m << %( - #{colorizer.colorize false, game["homePitcherName"].to_s} pitching)
      else
        m << %( - #{colorizer.colorize true, game["awayPitcherName"].to_s} pitching)
      end

      m << "\n\r"

      if game["finalized"].as_bool?
        away_score = (game["awayScore"].as_f? || game["awayScore"].as_i?).not_nil!
        home_score = (game["homeScore"].as_f? || game["homeScore"].as_i?).not_nil!
        if away_score > home_score
          m << %(The #{colorizer.colorize true, away_team_nickname} #{"won against".colorize.underline} the #{colorizer.colorize false, home_team_nickname})
        else
          m << %(The #{colorizer.colorize false, home_team_nickname} #{"won against".colorize.underline} the #{colorizer.colorize true, away_team_nickname})
        end
      else
        last_game_update = %(#{game["lastUpdate"]})
        line_break_regex = /(?<!\r)\n/
        regex_match = last_game_update.match(line_break_regex)
        while regex_match
          last_game_update = last_game_update.sub(line_break_regex, "\r\n")
          regex_match = last_game_update.match(line_break_regex)
        end
        m << last_game_update
      end
      m << "\n\r"
    end
  end

  def clear_last
    @last_message = "\x1b7\x1b[1A\x1b[1J\x1b[1;1H\rloading..\x1b8"
  end
end
