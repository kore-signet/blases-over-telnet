class UserSettings
  property number_of_columns : UInt8 = 1
  property column_width : UInt16 = 85

  def use_columns
    number_of_columns > 1
  end
end
