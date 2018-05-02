defmodule PropertyTests do
  use PropCheck.StateM
  use PropCheck
  use ExUnit.Case, async: false

  require Logger
  @moduletag capture_log: true

  property "ftp connections" do
    numtests(30, trap_exit(forall cmds in commands(__MODULE__) do
      Application.ensure_all_started(:ftp)

      {history, state, result} = run_commands(__MODULE__, cmds)

      Application.stop(:ftp)

      (result == :ok)
      |> when_fail(
        IO.puts """
        History: #{inspect history, pretty: true}
        State: #{inspect state, pretty: true}
        Result: #{inspect result, pretty: true}
        RanchInfo: #{inspect :ranch.info(), pretty: true}
        """)
        |> aggregate(command_names cmds)
    end))
  end

  defstruct connected: false, authenticated: false, inets_pid: :disconnected

  def initial_state, do: %__MODULE__{}

  def connect do
    {:ok, pid} = with {:error, _} <-:inets.start(:ftpc, [host: 'localhost', port: 2121]) do
      {:ok, :error}
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
    {:call, __MODULE__, :disconnect, [pid]}
  end

  def precondition(%{connected: true}, {:call, __MODULE__, :connect, []}), do: false
  def precondition(%{connected: false}, {:call, __MODULE__, :disconnect, _}), do: false
  def precondition(%{connected: false}, {:call, :ftp, _, _}), do: false
  def precondition(%{authenticated: true}, {:call, :ftp, :user, _}), do: false
  def precondition(_, _), do: true

  def next_state(%{connected: true}, _, {:call, __MODULE__, :disconnect, _}), do: initial_state()

  def next_state(%{connected: false} = prev_state, :error, {:call, __MODULE__, :connect, []}) do
    IO.puts "error setting up connections"
    %{prev_state | inets_pid: :disconnected, connected: false}
  end
  def next_state(%{connected: false} = prev_state, pid, {:call, __MODULE__, :connect, []}) do
    %{prev_state | inets_pid: pid, connected: true}
  end

  def next_state(%{authenticated: false, inets_pid: pid} = prev_state, _, {:call, :ftp, :user, [pid, _, _]}), do: %{prev_state | authenticated: true}

  def next_state(state, _, _), do: state

  def postcondition(%{connected: false}, {:call, __MODULE__, :connect, []}, :error) do
    IO.puts "inets failed to start protocol"
    false
  end

  def postcondition(%{connected: false}, {:call, __MODULE__, :connect, []}, pid) when is_pid(pid) do
    [{_ref, info}] = :ranch.info()
    if Keyword.get(info, :all_connections) == 1 do
      true
    else
      IO.puts "failed connection"
      false
    end
  end

  def postcondition(%{connected: true, inets_pid: pid}, {:call, __MODULE__, :disconnect, [pid]}, :ok) do
    Process.sleep(200)
    [{_ref, info}] = :ranch.info()
    if Keyword.get(info, :all_connections) == 0 do
      true
    else
      IO.puts "failed disconnection"
      false
    end
  end

  def postcondition(_previous_state, _commad, _result), do: true
end
