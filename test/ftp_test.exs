defmodule FtpTest do
  use ExUnit.Case
  doctest Ftp
  doctest FtpActiveSocket
  doctest FtpPasvSocket

  test "the truth" do
    assert 1 + 1 == 2
  end
end
