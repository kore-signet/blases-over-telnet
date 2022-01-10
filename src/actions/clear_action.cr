require "../client.cr"
require "./base.cr"

class ClearAction < Action
  getter aliases : Set(String) = Set{"clear"}

  def invoke(
    client : Client,
    tx : Channel({String, SourceData}),
    sources : Hash(String, Source),
    line : String
  ) : Nil
    client.socket << "\x1b[1;1H"
    client.socket << "\x1b[0J"
    client.socket << "\x1b[10000B"
    client.socket << "\r"
  end
end
