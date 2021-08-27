require "json"
require "sse"

abstract class Source
  abstract def add_client
  abstract def rm_client
  abstract def n_clients
  abstract def last_data
end

class LiveSource < Source
  property sse : HTTP::ServerSentEvents::EventSource
  property last_message : Hash(String,JSON::Any) = Hash(String,JSON::Any).new
  property tx : Channel({String, Hash(String,JSON::Any)})
  property ident : String
  property clients : Int32 = 0

  def initialize(url : String, @ident : String, @tx : Channel({String, Hash(String,JSON::Any)}))
    @sse = HTTP::ServerSentEvents::EventSource.new url
    @sse.on_message do |msg|
      begin
        @last_message = JSON.parse(msg.data[0])["value"].as_h
        @tx.send({ @ident, @last_message })
      rescue ex
        begin
          @last_message = JSON.parse(msg.data[0][8..msg.data[0].size-2]).as_h
          @tx.send({ @ident, @last_message })
        rescue ex2
          puts "error in source #{@ident}"
          pp ex.inspect_with_backtrace
          puts "error in SSE formatting workaround"
          pp ex2.inspect_with_backtrace
        end
      end
    end

    spawn do
      @sse.run
    end
  end

  def add_client
    @clients += 1
  end

  def rm_client
    @clients -= 1
  end

  def n_clients
    @clients
  end

  def close
    @sse.stop
  end

  def last_data
    @last_message
  end
end
