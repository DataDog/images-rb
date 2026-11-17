# ruby-version-min: 1.8.7

require "minitest/autorun"
require "socket"

class TestIO < Minitest::Test
  def test_select_tracks_pending_reads
    reader, writer = IO.pipe
    assert_nil(IO.select([reader], nil, nil, 0))

    writer.write("ab")
    assert_equal("a", reader.read(1))
    assert_equal([reader], IO.select([reader], nil, nil, 0)[0])
    assert_equal("b", reader.read(1))
    assert_nil(IO.select([reader], nil, nil, 0))
  ensure
    reader.close if reader
    writer.close if writer
  end

  def test_recv_on_a_fresh_socket
    server = TCPServer.new("127.0.0.1", 0)
    client = TCPSocket.new("127.0.0.1", server.addr[1])
    peer = server.accept
    peer.write("r")
    assert_equal("r", client.recv(1))
  ensure
    peer.close if peer
    client.close if client
    server.close if server
  end
end
