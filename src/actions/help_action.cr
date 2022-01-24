require "socket"
require "colorize"
require "http/client"
require "../client.cr"
require "./base.cr"

class HelpAction < Action
  getter aliases : Set(String) = Set{"help"}

  def invoke(
    client : Client,
    tx : Channel({String, SourceData}),
    sources : Hash(String, Source),
    line : String
  ) : Nil
    client.socket << "\x1b[1;1H"
    client.socket << "\x1b[0J"
    client.writeable = false
    show_help(client.socket, line)
  end
end

def show_help(
  socket : TCPSocket,
  query : String
) : Nil
  socket << "blases over telnet - help\r\n"
  socket << "\twelcome to blases over telnet\r\n"
  socket << "\n"
  socket << "options:\r\n"
  socket << "\treplay\r\n"
  socket << "\t  just send in 'replay: ISO8601Timestamp', like 'replay: 2021-06-22T14:00:52.000Z'\r\n"
  socket << "\t  or a season and day (1-indexed), like 'replay: season 18 99'\r\n"
  socket << "\tlive\r\n"
  socket << "\t  use if you've travelled back in time, in order to return to the present\r\n"
  socket << "\tclear\r\n"
  socket << "\t  clears the screen\r\n"
  socket << "\tpause\r\n"
  socket << "\t  pauses the writing to your screen (time keeps marching on in the background)\r\n"
  socket << "\tresume\r\n"
  socket << "\t  resumes writing live updates to your screen\r\n"
  socket << "\tdisplay\r\n"
  socket << "\t  set display options (currently just column control)\r\n"
  # socket << "\t  (focused games maybe coming soon)\r\n"
  # socket << "\tstandings\r\n"
  # socket << "\t  coming soon\r\n"
  socket << "\x1b[10000E" # goto end of page
  socket << "\x1b[1F"     # go back up a line
  socket << "type 'resume' to return to the feed\r\n"
end
