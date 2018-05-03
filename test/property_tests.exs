defmodule PropertyTests do
  use PropCheck.StateM
  use PropCheck
  use ExUnit.Case, async: false

  @default_dir "/"
  @test_port 2525

  require Logger
  @moduletag capture_log: true

  property "ftp connections" do
    numtests(
      30,
      trap_exit(
        forall cmds in commands(__MODULE__) do
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

  defstruct connected: false, authenticated: false, inets_pid: :disconnected

  def initial_state, do: %__MODULE__{}

  def connect do
    {:ok, pid} =
      with {:error, _} <- :inets.start(:ftpc, host: 'localhost', port: @test_port) do
        :inets.start(:ftpc, host: 'localhost', port: @test_port)
      end

    pid
  end

  def disconnect(pid) do
    :inets.stop(:ftpc, pid)
  end

  def command(%{inets_pid: :disconnected}) do
    {:call, __MODULE__, :connect, []}
  end

  def command(%{authenticated: false, connected: true, inets_pid: pid}) do
    oneof([
      {:call, :ftp, :user, [pid, 'user', 'pass']},
      {:call, __MODULE__, :disconnect, [pid]}
    ])
  end

  def command(%{authenticated: true, connected: true, inets_pid: pid}) do
    oneof([
      {:call, __MODULE__, :disconnect, [pid]},
      {:call, :ftp, :send_bin, [pid, 'Woo dogs', 'filename.tmp']},
      {:call, :ftp, :pwd, [pid]}
    ])
  end

  def precondition(%{connected: true}, {:call, __MODULE__, :connect, []}), do: false
  def precondition(%{connected: false}, {:call, __MODULE__, :disconnect, _}), do: false
  def precondition(%{authenticated: authenticated}, {:call, :ftp, :user, _}), do: not authenticated
  def precondition(%{authenticated: false}, {:call, :ftp, _, _}), do: false
  def precondition(%{connected: false}, {:call, :ftp, _, _}), do: false
  def precondition(_, _), do: true

  def next_state(%{connected: true}, _, {:call, __MODULE__, :disconnect, _}), do: initial_state()

  def next_state(%{connected: false} = prev_state, pid, {:call, __MODULE__, :connect, []}) do
    %{prev_state | inets_pid: pid, connected: true}
  end

  def next_state(
        %{authenticated: false, inets_pid: pid} = prev_state,
        _,
        {:call, :ftp, :user, [pid, _, _]}
      ),
      do: %{prev_state | authenticated: true}

  def next_state(state, _, _), do: state

  def postcondition(%{connected: false}, {:call, __MODULE__, :connect, []}, {:error, _} = error) do
    IO.puts("inets failed to start protocol #{error}")
    false
  end

  def postcondition(
        _,
        {:call, :ftp, :send_bin, [_pid, _contents, _filename]},
        {:error, _} = error
      ) do
    IO.puts("Failed to send file #{inspect error}")
    false
  end

  def postcondition(_, {:call, :ftp, :send_bin, [_pid, contents, filename]}, :ok) do
    file_path = "#{@default_dir}/#{filename}"
    File.exists?(file_path) and File.read(file_path) == {:ok, contents}
  end

  def postcondition(%{connected: false}, {:call, __MODULE__, :connect, []}, pid) when is_pid(pid), do: true
  def postcondition(%{connected: true, inets_pid: pid}, {:call, __MODULE__, :disconnect, [pid]}, :ok), do: true

  def postcondition(
        %{connected: true, authenticated: true},
        {:call, :ftp, :pwd, _},
        {:error, _} = error
      ) do
    IO.puts("failed to get pwd #{inspect(error)}")
    false
  end

  def postcondition(%{connected: true, authenticated: true, pwd: pwd}, {:call, :ftp, :pwd, _}, {:ok, pwd}), do: true
  def postcondition(%{connected: true, authenticated: true, pwd: other_pwd}, {:call, :ftp, :pwd, _}, {:ok, pwd}) when other_pwd != pwd do
    IO.puts "Expected current directory to be #{other_pwd} but got #{pwd}"
    false
  end

  def postcondition(%{connected: true, authenticated: false}, {:call, :ftp, :user, _}, :ok), do: true
  def postcondition(%{connected: true, authenticated: false}, {:call, :ftp, :user, args}, {:error, _} = error) do
    IO.puts "Failed to login as #{inspect args} error: #{error}"
  end

  def postcondition(_previous_state, _commad, _result), do: false
end
