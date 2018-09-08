defmodule PropertyTest do
  use PropCheck.StateM
  use PropCheck
  use ExUnit.Case, async: false
  alias PropertyTest.Off
  alias PropertyTest.Disconnected
  alias PropertyTest.Connected
  alias PropertyTest.Authenticated

  @default_dir '/'
  @test_dir './tmp/ftp_root'
  @test_port 2525
  @initial_filename 'initial_file.txt'
  @initial_file @test_dir ++ '/' ++ @initial_filename
  @initial_file_content "initial content"

  require Logger
  @moduletag capture_log: true

  def reset_server do
    Application.stop(:ftp)
    File.rm_rf(@test_dir)
    File.mkdir_p(@test_dir)
    :ok = File.write(@initial_file, @initial_file_content)
  end

  property "ftp connections", [:verbose] do
    numtests(
      200,
      trap_exit(
        forall cmds in commands(__MODULE__) do
          reset_server()
          Application.ensure_all_started(:ftp)

          {history, state, result} = run_commands(__MODULE__, cmds)

          Application.stop(:ftp)

          (result == :ok)
          |> when_fail(
            IO.puts("""
            History: #{inspect(history, pretty: true)}
            State: #{inspect(state, pretty: true)}
            Result: #{inspect(result, pretty: true)}
            RanchInfo: #{inspect(:ranch.info(), pretty: true)}
            Commands Run: #{length(history)}
            """)
          )
          |> aggregate(command_names(cmds))
        end
      )
    )
  end

  defstruct pid: nil,
            pwd: @default_dir,
            files: [{@default_dir, @initial_filename, @initial_file_content}],
            dirs: ['/']

  def initial_state, do: {Off, %__MODULE__{}}

  def start_server do
    Ftp.sample()
  end

  def stop_server do
    Ftp.close_server(:sample)
  end

  def connect do
    {:ok, pid} =
      with {:error, _} <- :ftp.open('localhost', port: @test_port) do
        :ftp.open('localhost', port: @test_port)
      end

    pid
  end

  def disconnect(pid) do
    :ftp.close(pid)
  end

  def receive_with_offset(pid, {filename, offset}) do
    :ftp.recv_bin(pid, filename, offset)
  end

  def valid_login(pid) do
    :ftp.user(pid, 'user', 'pass')
  end

  def invalid_login(:password, pid) do
    :ftp.user(pid, 'user', 'badpass')
  end

  def invalid_login(:user, pid) do
    :ftp.user(pid, 'baduser', 'pass')
  end

  def get_unknown_file(pid) do
    :ftp.recv_bin(pid, "not_a_real_file.txt")
  end

  defmodule Off do
    def command(_) do
      {:call, PropertyTest, :start_server, []}
    end

    def precondition(_, {:call, PropertyTest, :start_server, []}), do: true
    def postcondition(_, {:call, PropertyTest, :start_server, []}, {:ok, _}), do: true
  end

  defmodule Disconnected do
    def command(_) do
      weighted_union([
        {20, {:call, PropertyTest, :connect, []}},
        {1, {:call, PropertyTest, :stop_server, []}}
      ])
    end

    def precondition(_, {:call, PropertyTest, :connect, []}), do: true

    def next(data, pid, {:call, PropertyTest, :connect, []}) do
      {Connected, %{data | pid: pid}}
    end

    def postcondition(_, {:call, PropertyTest, :connect, []}, {:error, _} = error) do
      IO.puts("inets failed to start protocol #{error}")
      false
    end

    def postcondition(_, {:call, PropertyTest, :connect, []}, pid) when is_pid(pid),
      do: true

    def postcondition(_, {:call, PropertyTest, :stop_server, []}, :ok), do: true
  end

  defmodule Connected do
    def command(%{pid: pid}) do
      weighted_union([
        {20, {:call, PropertyTest, :valid_login, [pid]}},
        {2, {:call, PropertyTest, :invalid_login, [:password, pid]}},
        {2, {:call, PropertyTest, :invalid_login, [:user, pid]}},
        {1, {:call, PropertyTest, :disconnect, [pid]}},
        {1, {:call, PropertyTest, :stop_server, []}}
      ])
    end

    def precondition(_, {:call, PropertyTest, :disconnect, _}), do: true
    def precondition(_, {:call, PropertyTest, :invalid_login, _}), do: true
    def precondition(_, {:call, PropertyTest, :valid_login, _}), do: true
    def precondition(_, {:call, PropertyTest, :stop_server, _}), do: true

    def next(
          %{pid: pid} = data,
          _,
          {:call, PropertyTest, :valid_login, [pid]}
        ),
        do: {Authenticated, data}

    def next(
          %{pid: pid} = data,
          _,
          {:call, PropertyTest, :invalid_login, [_, pid]}
        ),
        do: {Disconnected, %{data | pid: nil}}

    def postcondition(_, {:call, PropertyTest, :valid_login, _}, :ok), do: true

    def postcondition(_, {:call, PropertyTest, :valid_login, _}, {:error, _} = error) do
      IO.puts("Failed valid login error: #{inspect(error)}")
      false
    end

    def postcondition(_, {:call, PropertyTest, :invalid_login, _}, {:error, :euser}),
      do: true

    def postcondition(_, {:call, PropertyTest, :invalid_login, _}, :ok) do
      IO.puts("Insecure login allowed")
      false
    end

    def postcondition(_, {:call, PropertyTest, :stop_server, []}, :ok), do: true

    def postcondition(%{pid: pid}, {:call, PropertyTest, :disconnect, [pid]}, :ok), do: true
  end

  defmodule Authenticated do
    def command(%{pid: pid} = data) do
      file_in_pwd = a_file_relative_pwd(data)

      weighted_union([
        {1, {:call, PropertyTest, :disconnect, [pid]}},
        {10, {:call, :ftp, :recv_bin, [pid, file_in_pwd]}},
        {10, {:call, :ftp, :delete, [pid, file_in_pwd]}},
        {10, {:call, :ftp, :send_bin, [pid, file_content(), filename()]}},
        {10, {:call, :ftp, :mkdir, [pid, dirname()]}},
        {5, {:call, :ftp, :pwd, [pid]}},
        {1, {:call, PropertyTest, :stop_server, []}},
        {10, {:call, PropertyTest, :receive_with_offset, [pid, a_file_with_offset(data)]}},
        {5, {:call, PropertyTest, :get_unknown_file, [pid]}}
      ])
    end

    def precondition(_, {:call, PropertyTest, :disconnect, _}), do: true

    def precondition(%{files: []}, {:call, :ftp, command, _})
        when command in [:recv_bin, :delete],
        do: false

    def precondition(
          %{dirs: dirs, pwd: pwd},
          {:call, :ftp, :mkdir, [_, directory]}
        ) do
      attempting_add = Path.join([to_string(pwd), to_string(directory)]) |> to_charlist()
      attempting_add not in dirs
    end

    def precondition(
          %{files: []},
          {:call, PropertyTest, :receive_with_offset, [_, _]}
        ) do
      false
    end

    def precondition(
          _,
          {:call, PropertyTest, :receive_with_offset, [_, _]}
        ),
        do: true

    def precondition(
          _,
          {:call, PropertyTest, :get_unknown_file, [_]}
        ),
        do: true

    def precondition(_, {:call, :ftp, _, _}), do: true

    def next(data, _, {:call, :ftp, :pwd, _}), do: {Authenticated, data}
    def next(data, _, {:call, :ftp, :recv_bin, _}), do: {Authenticated, data}
    def next(data, _, {:call, PropertyTest, :receive_with_offset, _}), do: {Authenticated, data}
    def next(data, _, {:call, PropertyTest, :get_unknown_file, _}), do: {Authenticated, data}

    def postcondition(_, {:call, PropertyTest, :stop_server, []}, :ok), do: true
    def postcondition(%{pid: pid}, {:call, PropertyTest, :disconnect, [pid]}, :ok), do: true

    def postcondition(
          _,
          {:call, :ftp, :pwd, _},
          {:error, _} = error
        ) do
      IO.puts("failed to get pwd #{inspect(error)}")
      false
    end

    def postcondition(%{pwd: pwd}, {:call, :ftp, :pwd, _}, {:ok, pwd}), do: true

    def postcondition(%{pwd: other_pwd}, {:call, :ftp, :pwd, _}, {:ok, pwd})
        when other_pwd != pwd do
      IO.puts("Expected current directory to be #{other_pwd} but got #{pwd}")
      false
    end

    def postcondition(
          _,
          {:call, :ftp, :recv_bin, [_, filename]},
          {:error, _} = error
        ) do
      IO.puts("Expected to recv file #{inspect(filename)} #{inspect(error)}")
      false
    end

    def postcondition(
          %{files: files, pwd: pwd},
          {:call, :ftp, :recv_bin, [_, download_name]},
          {:ok, bin}
        ) do
      found =
        Enum.any?(files, fn
          {dir, filename, ^bin} ->
            dir ++ filename == pwd ++ download_name

          _ ->
            false
        end)

      if not found do
        IO.puts("Could not match file #{inspect({download_name, bin})}")
      end

      found
    end

    def postcondition(
          _,
          {:call, PropertyTest, :receive_with_offset, [_, {filename, offset}]},
          {:error, _} = error
        ) do
      IO.puts(
        "Expected to recv with offset #{offset} file #{inspect(filename)} #{inspect(error)}"
      )

      false
    end

    def postcondition(
          %{files: files, pwd: pwd},
          {:call, PropertyTest, :receive_with_offset, [_, {download_name, offset}]},
          {:ok, bin}
        ) do
      found =
        Enum.find(files, :not_found, fn {dir, filename, _} ->
          dir ++ filename == pwd ++ download_name
        end)

      case found do
        {_, ^download_name, content} ->
          <<_::binary-size(offset), expected_content::binary>> = content

          if expected_content == bin do
            true
          else
            IO.puts(
              "Could not match content offset #{offset} received #{inspect(bin, pretty: true)} expected #{
                inspect(expected_content, pretty: true)
              } original content #{inspect(content, pretty: true)}"
            )

            false
          end

        result ->
          IO.puts("Could not match file #{inspect({download_name, bin})} got #{result}")
          false
      end
    end

    def postcondition(
          _,
          {:call, :ftp, :mkdir, [_pid, _dirname]},
          {:error, _} = error
        ) do
      IO.puts("Failed to make dir #{inspect(error)}")
      false
    end

    def postcondition(_, {:call, :ftp, :mkdir, [pid, dirname]}, :ok) do
      case :ftp.ls(pid) do
        {:ok, listing} ->
          if listing |> to_string() |> String.contains?(to_string(dirname)) do
            true
          else
            IO.puts("expected #{inspect(dirname)} in #{inspect(listing)}")
            false
          end

        error ->
          IO.puts(
            "Sent, but can't ls #{inspect(error)} pid: #{inspect(pid)} dir: #{inspect(dirname)}"
          )

          false
      end
    end

    def postcondition(
          _,
          {:call, :ftp, :send_bin, [_pid, _contents, _filename]},
          {:error, _} = error
        ) do
      IO.puts("Failed to send file #{inspect(error)}")
      false
    end

    def postcondition(
          %{pwd: pwd},
          {:call, :ftp, :send_bin, [pid, contents, filename]},
          :ok
        ) do
      case :ftp.recv_bin(pid, pwd ++ filename) do
        {:ok, bin} ->
          if contents != bin do
            IO.puts(
              "expected #{inspect(filename)} to have contents #{inspect(bin)}, but got #{
                inspect(contents)
              }"
            )

            false
          else
            true
          end

        error ->
          IO.puts(
            "Sent, but can't recv_bin #{inspect(error)} pid: #{inspect(pid)} file: #{
              inspect(filename)
            }"
          )

          false
      end
    end

    def postcondition(
          _,
          {:call, :ftp, :delete, [_pid, _filename]},
          {:error, _} = error
        ) do
      IO.puts("Failed to delete file #{inspect(error)}")
      false
    end

    def postcondition(
          _,
          {:call, PropertyTest, :get_unknown_file, [_]},
          {:ok, _bin}
        ) do
      IO.puts("received unknown file")
      false
    end

    def postcondition(
          _,
          {:call, PropertyTest, :get_unknown_file, [_]},
          {:error, _}
        ) do
      true
    end

    def postcondition(%{pwd: pwd}, {:call, :ftp, :delete, [pid, filename]}, :ok) do
      case :ftp.recv_bin(pid, pwd ++ filename) do
        {:error, :epath} ->
          true

        response ->
          IO.puts(
            "Deleted but fetch reesponse was #{inspect(response)} pid: #{inspect(pid)} file: #{
              inspect(filename)
            }"
          )

          false
      end
    end

    def filename do
      oneof(['one.txt', 'two.jpg', 'three.bin', 'four.so', 'five.png'])
    end

    def dirname do
      oneof(['dirone', 'dirtwo', 'dirthree', 'dirfour'])
    end

    def file_content do
      binary(10)
    end

    def a_file_relative_pwd(%{files: []}) do
      :no_files
    end

    def a_file_relative_pwd(%{files: files, pwd: pwd}) do
      files
      |> Enum.map(fn {path, filename, _} ->
        Path.join([to_string(path), to_string(filename)])
        |> Path.relative_to(pwd)
        |> to_charlist()
      end)
      |> oneof()
    end

    def a_file_with_offset(%{files: []}) do
      :no_files
    end

    def a_file_with_offset(%{files: files, pwd: pwd}) do
      for {path, filename, content} <- files,
          size <- Range.new(0, byte_size(content)),
          file =
            Path.join([to_string(path), to_string(filename)])
            |> Path.relative_to(pwd)
            |> to_charlist() do
        {file, size}
      end
      |> oneof()
    end
  end

  def command({state, data}), do: state.command(data)

  def precondition({state, _}, {:call, __MODULE__, :stop_server, []}) when state != Off, do: true

  def precondition({state, data}, call), do: state.precondition(data, call)

  def next_state({_, data}, _, {:call, __MODULE__, :start_server, []}), do: {Disconnected, data}
  def next_state({_, data}, _, {:call, __MODULE__, :stop_server, []}), do: {Off, data}
  def next_state({_, data}, _, {:call, __MODULE__, :disconnect, _}), do: {Disconnected, data}

  def next_state(
        {state, %{files: files, pwd: pwd} = data},
        _,
        {:call, :ftp, :send_bin, [_, contents, filename]}
      ) do
    {state, %{data | files: [{pwd, filename, contents} | files]}}
  end

  def next_state(
        {Authenticated, %{dirs: dirs, pwd: pwd} = data},
        _,
        {:call, :ftp, :mkdir, [_, dirname]}
      ) do
    {Authenticated, %{data | dirs: [pwd ++ dirname | dirs]}}
  end

  def next_state(
        {state, %{files: files, pwd: pwd} = data},
        _,
        {:call, :ftp, :delete, [_, filename]}
      ) do
    new_files =
      files
      |> Enum.reject(fn {dir, name, _} ->
        Path.join([to_string(dir), to_string(name)]) ==
          Path.join([to_string(pwd), to_string(filename)])
      end)

    {state, %{data | files: new_files}}
  end

  def next_state({state, data}, result, call), do: state.next(data, result, call)

  def postcondition({state, data}, call, result), do: state.postcondition(data, call, result)

  def postcondition(previous_state, command, result) do
    IO.puts("default failure #{inspect([previous_state, command, result])} ")
    false
  end

  def receive_event(event, message) do
    receive do
      {:ftp_event, ^event} ->
        true

      _ ->
        receive_event(event, message)
    after
      1000 ->
        IO.puts("#{event} never received: #{message}")
        false
    end
  end
end
