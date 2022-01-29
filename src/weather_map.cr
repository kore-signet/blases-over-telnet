require "json"
require "colorize"
require "./color_diff.cr"

class WeatherEntry
  getter id : Int32
  getter name : String
  getter background : Colorize::Color256
  getter color : Colorize::Color256

  def initialize(
    @id : Int32,
    @name : String,
    @background : Colorize::Color256,
    @color : Colorize::Color256
  )
  end
end

class WeatherMap
  property weather_map : Array(WeatherEntry)

  def initialize(file : String, color_map : ColorMap)
    weather_data = JSON.parse(File.read(file)).as_a
    @weather_map = (weather_data.map do |weather|
      background = color_map.get_hex_color weather["background"].as_s
      color = color_map.get_hex_color weather["color"].as_s
      WeatherEntry.new(
        weather["id"].as_i,
        weather["name"].as_s,
        background,
        color)
    end)
  end

  def display_weather(type : Int32) : Colorize::Object(String)
    entry = weather_map[type]?
    if entry.nil?
      entry = weather_map[0]
    end
    entry.name.colorize.fore(entry.color).back(entry.background)
  end
end
