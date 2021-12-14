require "spec"
require "../src/layouts.cr"

describe "make ord" do
  cases = {
      1 => "1st",
      2 => "2nd",
      3 => "3rd",
      4 => "4th",
      5 => "5th",
     10 => "10th",
     11 => "11th",
     12 => "12th",
     13 => "13th",
     14 => "14th",
     15 => "15th",
     20 => "20th",
     21 => "21st",
     22 => "22nd",
    100 => "100th",
    101 => "101st", # woe betide us if we ever get to 101 innings
    102 => "102nd",
  }

  cases.each do |numeral, ordinal|
    it ordinal do
      make_ord(numeral).should eq ordinal
    end
  end
end
