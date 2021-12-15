require "json"
require "sse"
require "json-tools"

abstract class Source
  abstract def add_client
  abstract def rm_client
  abstract def n_clients
  abstract def last_data
end

class LiveSource < Source
  property sse : HTTP::ServerSentEvents::EventSource
  property last_message : JSON::Any
  property tx : Channel({String, Hash(String, JSON::Any)})
  property ident : String
  property clients : Int32 = 0

  def initialize(url : String, @ident : String, @tx : Channel({String, Hash(String, JSON::Any)}))
    @last_message = JSON.parse(%({"empty": "message"}))
    @sse = HTTP::ServerSentEvents::EventSource.new url
    @sse.on_message do |msg|
      begin
        parsed_message = JSON.parse(msg.data[0]).as_h
      rescue ex
        begin
          parsed_message = JSON.parse(msg.data[0][8..msg.data[0].size - 2])
        rescue ex2
          puts "error in source #{ident}"
          pp ex.inspect_with_backtrace
          puts "error in SSE formatting workaround"
          pp ex2.inspect_with_backtrace
          next
        end
      end

      if parsed_message.has_key? "value"
        @last_message = parsed_message["value"]
        @tx.send({@ident, @last_message.as_h})
      elsif parsed_message.has_key? "delta"
        apply_patch(parsed_message["delta"])
        @tx.send({@ident, @last_message.as_h})
      end
    end

    spawn do
      @sse.run
    end
  end

  def apply_patch(patch : JSON::Any)
    begin
      @last_message = Json::Tools::Patch.new(patch).apply(@last_message)
    rescue ex
      puts "error in applying patch"
      pp ex.inspect_with_backtrace
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

  def set_last_message(@last_message)
  end

  def last_data : Hash(String, JSON::Any)
    @last_message.as_h
  end
end
