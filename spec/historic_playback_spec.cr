require "spec"
require "../src/sources/historic_source.cr"

def get_historic_source : ChroniclerSource
  historic_source = ChroniclerSource.new(
    Time.utc(2021, 6, 27, 7, 0, 0),
    "Test",
    Channel({String, SourceData}).new,
    false)

  historic_source.current_day = 12

  historic_source.current_games["game1"] = {
    "timestamp" => JSON.parse(%("2021-06-27T07:00:00Z")),
    "data"      => JSON.parse(%({
        "day": 12,
        "gameStart": true,
        "gameComplete": false,
        "lastUpdate": "Play Ball!"
      })),
  }

  historic_source.historic_games["game1"] = [
    {
      "timestamp" => JSON.parse(%("2021-06-27T07:01:00Z")),
      "data"      => JSON.parse(%({
        "day": 12,
        "gameStart": true,
        "gameComplete": false,
        "lastUpdate": "Game canceled. Neither team non-lost."
      })),
    },
    {
      "timestamp" => JSON.parse(%("2021-06-27T07:02:00Z")),
      "data"      => JSON.parse(%({
        "day": 12,
        "gameStart": true,
        "gameComplete": false,
        "lastUpdate": "Game over."
      })),
    },
  ]

  return historic_source
end

describe "get_time_next_data_expires" do
  Spec.before_suite do
    Log.setup(:trace)
  end

  it "current time" do
    get_historic_source.current_time.should eq Time.utc(2021, 6, 27, 7, 0, 0)
  end

  it "initial time that data expires" do
    historic_source = get_historic_source
    historic_source.get_time_that_next_data_expires.should eq Time.utc(2021, 6, 27, 7, 1, 0)
    historic_source.current_time.should eq Time.utc(2021, 6, 27, 7, 0, 0)
  end

  it "update current game event" do
    historic_source = get_historic_source
    historic_source.current_time = historic_source.get_time_that_next_data_expires
    historic_source.update_current_game_event_for_all_ongoing_games
    historic_source.update_current_data
    Log.info { "updated current game event" }

    current_game : GameData = historic_source.current_data.games.not_nil![0]
    current_game["timestamp"].as_s.should eq "2021-06-27T07:01:00Z"
    current_game["data"]["lastUpdate"].as_s.should eq "Game canceled. Neither team non-lost."
    historic_source.current_time.should eq Time.utc(2021, 6, 27, 7, 1, 0)
    historic_source.get_time_that_next_data_expires.should eq Time.utc(2021, 6, 27, 7, 2, 0)
  end
end
