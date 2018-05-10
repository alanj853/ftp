defmodule FtpTest do
  use ExUnit.Case
  doctest Ftp
  doctest FtpActiveSocket
  doctest FtpPasvSocket

  @no_tests 50

  @tag timeout: 180_000
  test "PUT TEST for 2000 files in passive mode" do
    host = '127.0.0.1'
    port = 2525
    user = 'user'
    passwd = 'pass'
    file = 'file'
    # no_tests =20
    test_dir = Path.absname("") <> "/_tmp_client"
    server_dir = Path.absname("") <> "/_tmp_server"

    Ftp.sample()
    File.mkdir_p!(test_dir)
    File.mkdir_p!(server_dir)

    for i <- 1..@no_tests do
      file_name = "#{file}_#{i}.txt"
      File.write!(file_name, "This is a test1")
      {:ok, pid} = :ftp.open(host, port: port, mode: :passive)
      :ok = :ftp.user(pid, user, passwd)
      file = File.read!(file_name)
      :ftp.send(pid, to_charlist(file_name))
      :ftp.close(pid)
      File.rm_rf!(file_name)
    end

    no_of_files_tx = File.ls!(server_dir) |> Enum.count()

    Ftp.close_server :sample
    ## clean up
    File.rm_rf!(test_dir)
    files = File.ls!(server_dir)
    for file <- files, do: "#{Path.absname("_tmp_server")}/#{file}" |> File.rm()

    assert no_of_files_tx == @no_tests
  end

  @tag timeout: 180_000
  test "PUT TEST for 2000 files in active mode" do
    host = '127.0.0.1'
    port = 2525
    user = 'user'
    passwd = 'pass'
    file = 'file'
    # no_tests =20
    test_dir = Path.absname("") <> "/_tmp_client"
    server_dir = Path.absname("") <> "/_tmp_server"

    Ftp.sample()
    File.mkdir_p!(test_dir)
    File.mkdir_p!(server_dir)

    for i <- 1..@no_tests do
      file_name = "#{file}_#{i}.txt"
      File.write!(file_name, "This is a test1")
      {:ok, pid} = :ftp.open(host, port: port, mode: :active)
      :ok = :ftp.user(pid, user, passwd)
      file = File.read!(file_name)
      :ftp.send(pid, to_charlist(file_name))
      :ftp.close(pid)
      File.rm_rf!(file_name)
    end

    no_of_files_tx = File.ls!(server_dir) |> Enum.count()
    Ftp.close_server :sample
    ## clean up
    File.rm_rf!(test_dir)
    files = File.ls!(server_dir)
    for file <- files, do: "#{Path.absname("_tmp_server")}/#{file}" |> File.rm()

    assert no_of_files_tx == @no_tests
  end

  @tag timeout: 180_000
  test "RETR TEST for 2000 files in active mode" do
    host = '127.0.0.1'
    port = 2525
    user = 'user'
    passwd = 'pass'
    file = 'file'
    # no_tests =20
    test_dir = Path.absname("") <> "/_tmp_client"
    server_dir = Path.absname("") <> "/_tmp_server"

    Ftp.sample()
    File.mkdir_p!(test_dir)
    File.mkdir_p!(server_dir)

    for i <- 1..@no_tests do
      file_name = "#{file}_#{i}.txt"
      file_loc = "#{server_dir}/#{file_name}"
      File.write!(file_loc, "This is a test1")
      {:ok, pid} = :ftp.open(host, port: port, mode: :active)
      :ok = :ftp.user(pid, user, passwd)
      :ftp.recv(pid, to_charlist(file_name), to_charlist(test_dir <> "/" <> file_name))
      :ftp.close(pid)
      File.rm_rf!(file_loc)
    end

    no_of_files_tx = File.ls!(test_dir) |> Enum.count()

    ## clean up
    File.rm_rf!(test_dir)
    Ftp.close_server :sample
    assert no_of_files_tx == @no_tests
  end
end
