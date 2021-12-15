require "spec"
require "../src/components/progress_bar"

describe "Progress Bar" do
    it "half value, percentage, 20 wide" do
        get_progress_bar(50, 100, 20, true).should eq "[██████████          ] 50.0%"
    end

    it "3 / 20, non percentage, 20 wide" do
        get_progress_bar(3, 20, 20, false).should eq "[███                 ] 3/20"
    end

    it "10%, percentage, 10 wide" do
        get_progress_bar(1, 10, 10, true).should eq "[█         ] 10.0%"
    end

    it "100%, percentage, 5 wide" do
        get_progress_bar(1, 1, 5, true).should eq "[█████] 100.0%"
    end
end