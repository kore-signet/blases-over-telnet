require "json"

class ColorMap
  property color_map : Hash({Float64, Float64, Float64}, UInt8)

  def initialize(file)
    color_data = JSON.parse(File.read(file)).as_a
    @color_map = Hash({Float64, Float64, Float64}, UInt8).new

    color_data.each do |c|
      r = c["rgb"]["r"].as_i
      g = c["rgb"]["g"].as_i
      b = c["rgb"]["b"].as_i

      xyz = rgb_to_xyz(r, g, b)
      lab = xyz_to_lab(*xyz)

      @color_map[{lab[0], lab[1], lab[2]}] = c["colorId"].as_i.to_u8
    end
  end

  def get_hex_color(s : String) : Colorize::Color256
    if s.empty?
      return Colorize::Color256.new 15_u8
    end

    r = s[1..2].to_u8 base: 16
    g = s[3..4].to_u8 base: 16
    b = s[5..6].to_u8 base: 16

    Colorize::Color256.new find_closest_ansi(r, g, b)
  end

  def find_closest_ansi(r : UInt8, g : UInt8, b : UInt8) : UInt8
    r = r.to_f64
    g = g.to_f64
    b = b.to_f64

    xyz = rgb_to_xyz(r, g, b)
    lab = xyz_to_lab(*xyz)

    @color_map.map { |compare, ansi| {get_lab_squared_distance(*lab, *compare), ansi} }
      .sort_by { |a| a[0] }[0][1]
  end

  def find_furthest_color_from_background(
    r_1 : UInt8,
    g_1 : UInt8,
    b_1 : UInt8,
    r_2 : UInt8,
    g_2 : UInt8,
    b_2 : UInt8,
    background_r : UInt8,
    background_g : UInt8,
    background_b : UInt8
  ) : Colorize::Color256
    r_1 = r_1.to_f64
    g_1 = g_1.to_f64
    b_1 = b_1.to_f64

    r_2 = r_2.to_f64
    g_2 = g_2.to_f64
    b_2 = b_2.to_f64

    background_r = background_r.to_f64
    background_g = background_g.to_f64
    background_b = background_b.to_f64

    xyz_1 = rgb_to_xyz(r_1, g_1, b_1)
    xyz_2 = rgb_to_xyz(r_2, g_2, b_2)
    xyz_background = rgb_to_xyz(background_r, background_g, background_b)

    lab_1 = xyz_to_lab(*xyz_1)
    lab_2 = xyz_to_lab(*xyz_2)
    lab_background = xyz_to_lab(*xyz_background)

    closest_1 : {Float64, {Float64, Float64, Float64}, UInt8} = @color_map.map { |compare, ansi| {get_lab_squared_distance(*lab_1, *compare), compare, ansi} }
      .sort_by { |a| a[0] }[0]
    closest_2 : {Float64, {Float64, Float64, Float64}, UInt8} = @color_map.map { |compare, ansi| {get_lab_squared_distance(*lab_2, *compare), compare, ansi} }
      .sort_by { |a| a[0] }[0]

    if get_lab_squared_distance(*closest_1[1], *lab_background) < get_lab_squared_distance(*closest_2[1], *lab_background)
      Colorize::Color256.new closest_2[2]
    else
      Colorize::Color256.new closest_1[2]
    end
  end

  def get_lab_squared_distance(
    l, a, b,
    cl, ca, cb
  ) : Float64
    ((l - cl) ** 2) + ((a - ca) ** 2) + ((b - cb) ** 2)
  end

  def rgb_to_xyz(r, g, b)
    r /= 255
    g /= 255
    b /= 255

    r = if r > 0.04045
          ((r + 0.055) / 1.055) ** 2.4
        else
          r / 12.92
        end

    g = if g > 0.04045
          ((g + 0.055) / 1.055) ** 2.4
        else
          g / 12.92
        end

    b = if b > 0.04045
          ((b + 0.055) / 1.055) ** 2.4
        else
          b / 12.92
        end

    r *= 100
    g *= 100
    b *= 100

    x = r * 0.4124 + g * 0.3576 + b * 0.1805
    y = r * 0.2126 + g * 0.7152 + b * 0.0722
    z = r * 0.0193 + g * 0.1192 + b * 0.9505

    return {x, y, z}
  end

  def xyz_to_lab(x, y, z)
    ref_x = 95.047
    ref_y = 100.000
    ref_z = 108.883

    x /= ref_x
    y /= ref_y
    z /= ref_z

    x = if x > 0.008856
          x ** (1/3)
        else
          (7.787 * x) + 16 / 116
        end

    y = if y > 0.008856
          y ** (1/3)
        else
          (7.787 * y) + 16 / 116
        end

    z = if z > 0.008856
          z ** (1/3)
        else
          (7.787 * z) + 16 / 116
        end

    l = (116 * y) - 16
    a = 500 * (x - y)
    b = 200 * (y - z)
    return {l, a, b}
  end
end
