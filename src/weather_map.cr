require "json"
require "colorize"
require "./color_diff.cr"

class WeatherEntry
  getter id : Int32
  getter name : String
  getter background : {UInt8, UInt8, UInt8}
  getter color : {UInt8, UInt8, UInt8}

  def initialize(
    @id : Int32,
    @name : String,
    @background : {UInt8, UInt8, UInt8},
    @color : {UInt8, UInt8, UInt8}
  )
  end
end

def convert_hex_string_to_int_tuple(hex_string : String) : {UInt8, UInt8, UInt8}
  if hex_string.empty?
    return {0_u8, 0_u8, 0_u8}
  end

  r = hex_string[1..2].to_u8 base: 16
  g = hex_string[3..4].to_u8 base: 16
  b = hex_string[5..6].to_u8 base: 16

  {r, g, b}
end

class WeatherMap
  property color_map : ColorMap
  property weather_map : Array(WeatherEntry)

  def initialize(file : String, @color_map : ColorMap)
    weather_data = JSON.parse(File.read(file)).as_a
    @weather_map = (weather_data.map do |weather|
      background = convert_hex_string_to_int_tuple weather["background"].as_s
      color = convert_hex_string_to_int_tuple weather["color"].as_s

      WeatherEntry.new(
        weather["id"].as_i,
        weather["name"].as_s,
        background,
        color)
    end)
  end

  def display_weather(
    type : Int32,
    settings : UserSettings
  ) : Colorize::Object(String)
    entry = weather_map[type]?
    if entry.nil?
      entry = weather_map[0]
    end

    color : Colorize::Color256 = @color_map.find_furthest_color_from_background(*entry.color, *entry.background, *settings.background)
    entry.name.colorize.fore(color)
  end
end
