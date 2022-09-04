alias Id = String
alias DataOverTime = Array(Data)
alias Data = Hash(String, Int32)

describe "hash_which_contains_list" do
  it "just_shift" do
    dictionary = {"only" => [1, 2]}
    dictionary["only"].shift

    dictionary["only"].size.should eq 1
    dictionary["only"][0].should eq 2
  end

  it "iterator_shift" do
    dictionary = {"only" => [1, 2, 3]}
    dictionary.each do |key, value|
      value.shift
    end

    dictionary["only"].size.should eq 2
    dictionary["only"][0].should eq 2
    dictionary["only"][1].should eq 3
  end

  it "iterator_shift_using_new" do
    dictionary = Hash(String, Array(Int32)).new
    dictionary["only"] = [1, 2, 3]
    dictionary.each do |key, value|
      value.shift
    end

    dictionary["only"].size.should eq 2
    dictionary["only"][0].should eq 2
    dictionary["only"][1].should eq 3
  end

  it "iterator_key_shift" do
    dictionary = {"only" => [1, 2]}
    dictionary.each_key do |key|
      dictionary[key].shift
    end

    dictionary["only"].size.should eq 1
  end

  it "iterator_shift_aliased" do
    dictionary : Hash(Id, DataOverTime) = Hash(Id, DataOverTime).new
    dictionary["only"] = [{"foo" => 1}, {"foo" => 2}, {"foo" => 3}]

    dictionary.each do |key, value|
      value.shift
      value.shift
    end

    dictionary["only"].size.should eq 1
    dictionary["only"][0]["foo"].should eq 3
  end
end
