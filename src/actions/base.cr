require "../client.cr"

abstract class Action
  abstract def aliases : Set(String)

  abstract def invoke(
    client : Client,
    tx : Channel({String, SourceData}),
    sources : Hash(String, Source),
    line : String
  ) : Nil
end
