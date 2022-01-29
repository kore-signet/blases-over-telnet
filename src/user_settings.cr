class UserSettings
  property number_of_columns : UInt8 = 1
  property column_width : UInt16 = 85

  property debug : Bool = false
  property show_weather : Bool = true

  def use_columns
    number_of_columns > 1
  end
end
