class DisplayAction < Action
  getter aliases : Set(String) = Set{"display"}

  def invoke(
    client : Client,
    tx : Channel({String, SourceData}),
    sources : Hash(String, Source),
    line : String
  ) : Nil
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
  end
end
