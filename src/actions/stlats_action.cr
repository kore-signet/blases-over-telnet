require "../client.cr"
require "./base.cr"

class StlatsAction < Action
  getter aliases : Set(String) = Set{"stlats"}

  def invoke(
    client : Client,
    tx : Channel({String, SourceData}),
    sources : Hash(String, Source),
    line : String
  ) : Nil
    total_clients = sources.each.map { |(k, v)| v.n_clients }.sum
    client.socket << "\x1b[1A\rcurrently connected clients: #{total_clients}"
    client.socket << "\x1b[10000B"
    client.socket << "\r"
  end
end
