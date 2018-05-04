defmodule PropertyTests do
  use PropCheck.StateM
  use PropCheck
  use ExUnit.Case, async: false

  @default_dir '/'
  @test_dir './_tmp_server'
  @test_port 2525
  @initial_filename 'initial_file.txt'
  @initial_file_in_ftp [@default_dir | ['/' | @initial_filename]]
  @initial_file [@test_dir | ['/' | @initial_filename]]
  @initial_file_content "initial content"

  require Logger
  @moduletag capture_log: true

  def reset_server do
    File.rm_rf(@test_dir)
    File.mkdir_p(@test_dir)
    :ok = File.write(@initial_file, @initial_file_content)
  end

  property "ftp connections" do
    numtests(
      30,
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
            """)
          )
          |> aggregate(command_names(cmds))
        end
      )
    )
  end

  defstruct pid: nil, pwd: @default_dir, files: [{@initial_file_in_ftp, @initial_file_content}]

  def initial_state, do: {:disconnected, %__MODULE__{}}

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

  def filename do
    non_empty(list(union([range(97, 120), range(65, 90)])))
  end

  def file_content do
    binary()
  end

  def command({:disconnected, _}) do
    {:call, __MODULE__, :connect, []}
  end

  def command({:connected, %{pid: pid}}) do
    oneof([
      {:call, :ftp, :user, [pid, 'user', 'pass']},
      {:call, __MODULE__, :disconnect, [pid]}
    ])
  end

  def command({:authenticated, %{pid: pid}}) do
    oneof([
      {:call, __MODULE__, :disconnect, [pid]},
      {:call, :ftp, :recv_bin, [pid, @initial_filename]},
      {:call, :ftp, :send_bin, [pid, file_content(), filename()]},
      {:call, :ftp, :pwd, [pid]}
    ])
  end

  def precondition({:disconnected, _}, {:call, __MODULE__, :connect, []}), do: true
  def precondition({state, _}, {:call, __MODULE__, :disconnect, _}) when state in [:connected, :authenticated], do: true
  def precondition({:connected, _}, {:call, :ftp, :user, _}), do: true
  def precondition({:authenticated, _}, {:call, :ftp, _, _}), do: true
  def precondition(_, _), do: false

  def next_state({:disconnected, data}, pid, {:call, __MODULE__, :connect, []}) do
    {:connected, %{data | pid: pid}}
  end

  def next_state({:connected, data}, _, {:call, __MODULE__, :disconnect, _}), do: {:disconnected, data}

  def next_state(
        {:connected, %{pid: pid} = data},
        _,
        {:call, :ftp, :user, [pid, _, _]}
      ),
      do: {:authenticated, data}


  def next_state({state, %{files: files} = data}, _, {:call, :ftp, :send_bin, [_, contents, filename]}) do
    {state, %{data | files: [{filename, contents} | files]}}
  end

  def next_state(state, _, _), do: state

  def postcondition({:disconnected, _}, {:call, __MODULE__, :connect, []}, {:error, _} = error) do
    IO.puts("inets failed to start protocol #{error}")
    false
  end

  def postcondition(
    {:authenticated, _},
    {:call, :ftp, :send_bin, [_pid, _contents, _filename]},
    {:error, _} = error
  ) do
    IO.puts("Failed to send file #{inspect error}")
    false
  end

  def postcondition({:authenticated, _}, {:call, :ftp, :send_bin, [pid, contents, filename]}, :ok) do
    case :ftp.recv_bin(pid, filename) do
      {:ok, bin} ->
        if contents != bin do
          IO.puts "expected #{inspect filename} to have contents #{inspect bin}, but got #{inspect contents}"
        else
          true
        end
      error ->
        IO.puts "Failed to recv_bin #{inspect error} pid: #{inspect pid} file: #{inspect filename}"
        false
    end
  end

  def postcondition({:disconnected, _}, {:call, __MODULE__, :connect, []}, pid) when is_pid(pid), do: true
  def postcondition({:connected, %{pid: pid}}, {:call, __MODULE__, :disconnect, [pid]}, :ok), do: true

  def postcondition(
        {:authenticated, _},
        {:call, :ftp, :pwd, _},
        {:error, _} = error
      ) do
    IO.puts("failed to get pwd #{inspect(error)}")
    false
  end

  def postcondition({:authenticated, %{pwd: pwd}}, {:call, :ftp, :pwd, _}, {:ok, pwd}), do: true
  def postcondition({:authenticated, %{pwd: other_pwd}}, {:call, :ftp, :pwd, _}, {:ok, pwd}) when other_pwd != pwd do
    IO.puts "Expected current directory to be #{other_pwd} but got #{pwd}"
    false
  end

  def postcondition({:authenticated, _}, {:call, :ftp, :recv_bin, [_, filename]}, {:error, _} = error) do
    IO.puts "Expected to recv file #{inspect filename} #{inspect error}"
    false
  end

  def postcondition({:authenticated, files: files}, {:call, :ftp, :recv_bin, [_, filename]}, {:ok, bin}) do
    with :no_file_matched <- Enum.find_value(files, :no_file_matched, fn
      {filename, bin} ->
        true
    end) do
      IO.puts "Could not match file #{inspect {filename, bin}}"
      false
    end
  end

  def postcondition({:connected, _}, {:call, :ftp, :user, _}, :ok), do: true
  def postcondition({:connected, _}, {:call, :ftp, :user, args}, {:error, _} = error) do
    IO.puts "Failed to login as #{inspect args} error: #{error}"
  end

  def postcondition(previous_state, command, result) do
    IO.puts "default failure #{[previous_state, command, result]} "
    false
  end
end
