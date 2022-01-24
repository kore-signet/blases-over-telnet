require "../client.cr"
require "./base.cr"

class PauseAction < Action
  getter aliases : Set(String) = Set{"pause"}

  def invoke(
    client : Client,
    tx : Channel({String, SourceData}),
    sources : Hash(String, Source),
    line : String
  ) : Nil
    client.writeable = false
  end
end

class ResumeAction < Action
  getter aliases : Set(String) = Set{"resume"}

  def invoke(
    client : Client,
    tx : Channel({String, SourceData}),
    sources : Hash(String, Source),
    line : String
  ) : Nil
    client.writeable = true
    client.socket << client.last_rendered_message
  end
end
