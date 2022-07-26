abstract class Source
  abstract def add_client
  abstract def rm_client
  abstract def close
  abstract def n_clients
  abstract def last_data

  def get_most_recent_event_for_games(day : Int32, season : Int32, sim : String) : Array(GameData)?
    url = URI.parse(ENV["CHRON_API_URL"])
    url.query = URI::Params.encode({"day" => day.to_s, "season" => season.to_s, "sim" => sim})
    url.path = (Path.new(url.path) / "v1" / "games").to_s

    begin
      response = HTTP::Client.get url

      if response.success?
        messages = JSON.parse response.body
        return messages["data"].as_a.map { |game| game.as_h }
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

  def get_all_games(season : Int32, sim : String, started : Bool = true) : Array(GameData)?
    url = URI.parse(ENV["CHRON_API_URL"])
    url.query = URI::Params.encode({"season" => season.to_s, "sim" => sim, "started" => started.to_s})
    url.path = (Path.new(url.path) / "v1" / "games").to_s

    begin
      response = HTTP::Client.get url

      if response.success?
        messages = JSON.parse response.body
        return messages["data"].as_a.map { |game| game.as_h }
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
end
