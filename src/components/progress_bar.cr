def get_progress_bar(
    value : Number,
    value_range : Number,
    dimension : Int,
    display_as_percentage : Bool) : String
    result = String.build do |str| 
        percent_value = (value / value_range)
        str << "["
        str << "█"*(percent_value * dimension).to_i
        str << " "*((1 - percent_value) * dimension).to_i
        str << "] "
        if display_as_percentage
            str << "#{(percent_value * 100).format}\u{25}"
        else
            str << "#{value}/#{value_range}"
        end
    end

    result
end