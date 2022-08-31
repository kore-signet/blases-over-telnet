DEFAULT_COLUMN_WIDTH = 65_u16

class DisplayAction < Action
  getter aliases : Set(String) = Set{"display"}

  def invoke(
    client : Client,
    tx : Channel({String, SourceData}),
    sources : Hash(String, Source),
    line : String
  ) : Nil
    args : Array(String) = line.split
    number_of_args = args.size

    if number_of_args > 1
      if number_of_args > 2
        if args[1] == "contrast" && !args[2].to_f64?.nil?
          client.settings.contrast_threshold = args[2].to_f64
        elsif args[1] == "columns"
          parse_columns(client, args[2], number_of_args > 3 ? args[3] : nil)
        elsif args[1] == "preset" && args[2] == "lofty"
          client.settings.contrast_threshold = 0
          client.settings.debug = true
          client.settings.background = {0x2e_u8, 0x34_u8, 0x36_u8}
          client.settings.number_of_columns = 2
          client.settings.column_width = DEFAULT_COLUMN_WIDTH
        elsif args[1] == "light"
          client.settings.background = {0xFF_u8, 0xFF_u8, 0xFF_u8}
        elsif args[1] == "dark"
          client.settings.background = {0x00_u8, 0x00_u8, 0x00_u8}
        elsif args[1] == "snow"
          client.settings.show_snow = !client.settings.show_snow
        end
      else
        if args[1] == "debug"
          client.settings.debug = !client.settings.debug
        else
          client.writeable = false
          client.socket << "unknown display setting: "
          client.socket << line
          client.socket << "\r\n"
        end
      end
    else
      client.writeable = false
      client.socket << "\r\nenter a number of columns: "
      number_of_columns_string = client.socket.gets chomp: false
      if !number_of_columns_string
        return
      end

      number_of_columns = number_of_columns_string.to_u8?

      if number_of_columns
        if number_of_columns < 2
          client.socket << "no longer using columns"
          client.settings.number_of_columns = 1
        else
          client.socket << "enter a desired column width: "
          column_width_string = client.socket.gets chomp: false
          if !column_width_string
            return
          end

          column_width = column_width_string.to_u8?

          if column_width
            client.socket << "now using columns.\r\n"
            client.settings.number_of_columns = number_of_columns
            client.settings.column_width = column_width
          else
            client.socket << "\""
            client.socket << column_width_string
            client.socket << "\" is not a valid number.\r\n"
          end
        end
      else
        client.socket << "\r\n\""
        client.socket << number_of_columns_string
        client.socket << "\" is not a valid number (must be between 0 and 255).\r\n"
      end
      client.writeable = true
      client.socket << client.rerender
    end
  end

  private def parse_columns(
    client : Client,
    number_of_columns_string : String,
    column_width_string : String?
  )
    client.socket << "setting columns number_of_columns_string=#{number_of_columns_string} column_width_string=#{column_width_string}\r\n"

    number_of_columns = number_of_columns_string.to_u8?

    if !number_of_columns.nil?
      if column_width_string.nil?
        if number_of_columns < 2
          client.socket << "no longer using columns"
          client.settings.number_of_columns = 1
        else
          client.settings.number_of_columns = number_of_columns
        end
        client.settings.column_width = DEFAULT_COLUMN_WIDTH
      else
        column_width = column_width_string.to_u8?
        if !column_width.nil?
          client.settings.number_of_columns = number_of_columns
          client.settings.column_width = column_width
        else
          client.socket << "\""
          client.socket << column_width_string
          client.socket << "\" is not a valid number.\r\n"
        end
      end
    else
      client.socket << "\r\n\""
      client.socket << number_of_columns_string
      client.socket << "\" is not a valid number (must be between 0 and 255).\r\n"
    end
  end
end
