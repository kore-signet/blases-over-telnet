require "socket"
require "colorize"
#


def show_help(socket : TCPSocket, query : String)
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
  socket << "\t  resumes writing live updates to your screen"
  socket << "\x1b[10000E" # goto end of page
  socket << "\x1b[1F" # go back up a line
  socket << "type 'resume' to return to the feed\r\n"
end