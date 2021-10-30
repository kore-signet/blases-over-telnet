require "spec"
require "socket"
require "http/client"
require "sse"
require "json"
require "colorize"
require "../src/layouts.cr"
require "../src/color_diff.cr"

describe "layout" do
  describe "render" do
    describe "no games, no temporal" do
      layout = get_layout()
      it "should render an empty string" do
        unrelated_json = %{{"nextPage":"AAAAAAAAAAAAAAAAAAAAAGgEF1-1EQEA","items":[{"entityId":"00000000-0000-0000-0000-000000000000","hash":"6d1a1be6-adaa-69c1-6be6-131d44a0d28f","validFrom":"2021-06-14T07:36:05.88074Z","validTo":"2021-06-14T15:03:01.002066Z","data":{"current":0,"maximum":99999,"recharge":26244}}]}}
        message : Hash(String,JSON::Any) = JSON.parse(unrelated_json)["items"][0].as_h
  
        output : String = layout.render message

        output.blank?.should be_true
      end
    end

    describe "games, no temporal" do
      layout = get_layout()
      message : Hash(String,JSON::Any) = JSON.parse(File.read("spec/games.json")).as_h

      output : String = layout.render message

      it "should not be blank" do
        output.blank?.should be_false   
      end

      it "should be expected" do
        # gross hardcoding but i can't work out how to get reading from files to work
        # keeps escaping things :/ 
        expected : String = "\x1b7\x1b[1A\x1b[1J\x1b[1;1H\x1b[0J\x1b[1mDay 58, Season 24\x1b[0m\n\r" \
        "\x1b[4m\x1b[38;5;214mTHE EXPANSION ERA\x1b[0m - \x1b[38;5;74mSAVE SITUATION\x1b[0m\x1b[0m\n\r" \
        "\n\r" \
        "\x1b[38;5;96;1m-- --------- ----- (-2)\x1b[0m \x1b[4m@\x1b[0m \x1b[38;5;52;1mHades Tigers (3)\x1b[0m\n\r" \
        "\x1b[1mTop of the 9th\x1b[0m - \x1b[38;5;52;1mW-lton Spor--\x1b[0m pitching\n\r" \
        "The \x1b[38;5;52;1mTigers\x1b[0m \x1b[4mwon against\x1b[0m the \x1b[38;5;96;1m-----\x1b[0m\n\r" \
        "\n\r" \
        "\x1b[38;5;160;1m---- --------- (6.4)\x1b[0m \x1b[4m@\x1b[0m \x1b[38;5;30;1mPhilly Pies (3.1)\x1b[0m\n\r" \
        "\x1b[1mBottom of the 9th\x1b[0m - \x1b[38;5;160;1m------ -------\x1b[0m pitching\n\r" \
        "The \x1b[38;5;160;1m---------\x1b[0m \x1b[4mwon against\x1b[0m the \x1b[38;5;30;1mPies\x1b[0m\n\r" \
        "\n\r" \
        "\x1b[38;5;60;1m------- ----- (0)\x1b[0m \x1b[4m@\x1b[0m \x1b[38;5;58;1mOhio Worms (2)\x1b[0m\n\r" \
        "\x1b[1mBottom of the 9th\x1b[0m - \x1b[38;5;60;1m---- ---------\x1b[0m pitching\n\r" \
        "The \x1b[38;5;58;1mWorms\x1b[0m \x1b[4mwon against\x1b[0m the \x1b[38;5;60;1m-----\x1b[0m\n\r" \
        "\n\r" \
        "\x1b[38;5;161;1m----------- ----- (24)\x1b[0m \x1b[4m@\x1b[0m \x1b[38;5;54;1mCarolina Queens (2)\x1b[0m\n\r" \
        "\x1b[1mBottom of the 9th\x1b[0m - \x1b[38;5;161;1m------ ----------\x1b[0m pitching\n\r" \
        "The \x1b[38;5;161;1m-----\x1b[0m \x1b[4mwon against\x1b[0m the \x1b[38;5;54;1mQueens\x1b[0m\n\r" \
        "\n\r" \
        "\x1b[38;5;43;1mAtlantis Georgias (8)\x1b[0m \x1b[4m@\x1b[0m \x1b[38;5;229;1m--------- -------- (4)\x1b[0m\n\r" \
        "\x1b[1mBottom of the 9th\x1b[0m - \x1b[38;5;43;1mRigby Friedrich\x1b[0m pitching\n\r" \
        "The \x1b[38;5;43;1mGeorgias\x1b[0m \x1b[4mwon against\x1b[0m the \x1b[38;5;229;1m--------\x1b[0m\n\r" \
        "\n\r" \
        "\x1b[38;5;225;1mBoston Flowers (1)\x1b[0m \x1b[4m@\x1b[0m \x1b[38;5;166;1mMexico City Wild Wings (2)\x1b[0m\n\r" \
        "\x1b[1mTop of the 9th\x1b[0m - \x1b[38;5;166;1mSilvia Rugrat\x1b[0m pitching\n\r" \
        "The \x1b[38;5;166;1mWild Wings\x1b[0m \x1b[4mwon against\x1b[0m the \x1b[38;5;225;1mFlowers\x1b[0m\n\r" \
        "\n\r" \
        "\x1b[38;5;245;1mDallas Steaks (5)\x1b[0m \x1b[4m@\x1b[0m \x1b[38;5;231;1mCanada Moist Talkers (6)\x1b[0m\n\r" \
        "\x1b[1mTop of the 9th\x1b[0m - \x1b[38;5;231;1mSlosh Truk\x1b[0m pitching\n\r" \
        "The \x1b[38;5;231;1mMoist Talkers\x1b[0m \x1b[4mwon against\x1b[0m the \x1b[38;5;245;1mSteaks\x1b[0m\n\r" \
        "\n\r" \
        "\x1b[38;5;134;1mMiami Dale (2.5)\x1b[0m \x1b[4m@\x1b[0m \x1b[38;5;131;1m------- ------------ (1)\x1b[0m\n\r" \
        "\x1b[1mBottom of the 9th\x1b[0m - \x1b[38;5;134;1mSixpack Santiago\x1b[0m pitching\n\r" \
        "The \x1b[38;5;134;1mDale\x1b[0m \x1b[4mwon against\x1b[0m the \x1b[38;5;131;1m------------\x1b[0m\n\r" \
        "\n\r" \
        "\x1b[38;5;224;1mNew York Millennials (9)\x1b[0m \x1b[4m@\x1b[0m \x1b[38;5;178;1mOxford Paws (-3)\x1b[0m\n\r" \
        "\x1b[1mBottom of the 9th\x1b[0m - \x1b[38;5;224;1mBeck Whitney\x1b[0m pitching\n\r" \
        "The \x1b[38;5;224;1mMillennials\x1b[0m \x1b[4mwon against\x1b[0m the \x1b[38;5;178;1mPaws\x1b[0m\n\r" \
        "\n\r" \
        "\x1b[38;5;52;1mSan Francisco Lovers (4)\x1b[0m \x1b[4m@\x1b[0m \x1b[38;5;95;1mBaltimore Crabs (5)\x1b[0m\n\r" \
        "\x1b[1mBottom of the 10th\x1b[0m - \x1b[38;5;52;1mJacob Winner\x1b[0m pitching\n\r" \
        "The \x1b[38;5;95;1mCrabs\x1b[0m \x1b[4mwon against\x1b[0m the \x1b[38;5;52;1mLovers\x1b[0m\n\r" \
        "\n\r" \
        "\x1b[38;5;60;1mSeattle Garages (6)\x1b[0m \x1b[4m@\x1b[0m \x1b[38;5;220;1m---------- ---- ------- (5)\x1b[0m\n\r" \
        "\x1b[1mBottom of the 10th\x1b[0m - \x1b[38;5;60;1mAlaynabella Hollywood\x1b[0m pitching\n\r" \
        "The \x1b[38;5;60;1mGarages\x1b[0m \x1b[4mwon against\x1b[0m the \x1b[38;5;220;1m---- -------\x1b[0m\n\r" \
        "\n\r" \
        "\x1b[38;5;199;1mTokyo Lift (5)\x1b[0m \x1b[4m@\x1b[0m \x1b[38;5;67;1mBreckenridge Jazz Hands (8)\x1b[0m\n\r" \
        "\x1b[1mTop of the 9th\x1b[0m - \x1b[38;5;67;1mAugust Sky\x1b[0m pitching\n\r" \
        "The \x1b[38;5;67;1mJazz Hands\x1b[0m \x1b[4mwon against\x1b[0m the \x1b[38;5;199;1mLift\x1b[0m\n\r" \
        "\x1b8"
        output.should eq(expected)
      end
    end
  end
end

def get_layout()
  color_map = ColorMap.new "color_data.json"
  colorizer = Colorizer.new color_map
  layout = DefaultLayout.new colorizer
  return layout
end