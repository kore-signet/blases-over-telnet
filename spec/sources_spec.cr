require "spec"
require "../src/sources"
require "json"

describe "LiveSource" do
  source = LiveSource.allocate
  stream_data = File.open("spec/streamData.json")
  last_message = JSON.parse(stream_data).as_h["value"]

  patch_file = File.open("spec/streamData_diff1.json")
  patches = JSON.parse(patch_file).as_h["delta"]

  source.set_last_message last_message
  source.apply_patch patches
  source.last_data
end
