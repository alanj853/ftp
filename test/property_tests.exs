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

  defstruct file_locations: [], authenticated: false, inets_pid: :disconnected

  def initial_state, do: %__MODULE__{}

  def connect do
    {:ok, pid} = with {:error, _} <-:inets.start(:ftpc, [host: 'localhost', port: 2121]), do: {:ok, nil}
    pid
  end

  def disconnect(pid) do
    :inets.stop(:ftpc, pid)
  end

  def command(%{inets_pid: :disconnected}) do
    {:call, __MODULE__, :connect, []}
  end

  def command(%{authenticated: false, inets_pid: pid}) do
    oneof([
      {:call, :ftp, :user, [pid, 'user', 'pass']},
      {:call, __MODULE__, :disconnect, [pid]}
    ])
  end

  def command(%{authenticated: true, inets_pid: pid}) do
    {:call, __MODULE__, :disconnect, [pid]}
  end

  def precondition(%{inets_pid: pid}, {:call, __MODULE__, :connect, []}) when pid != :disconnected, do: false
  def precondition(%{inets_pid: :disconnected}, {:call, __MODULE__, :disconnect, _}), do: false
  def precondition(%{inets_pid: :disconnected}, {:call, :ftp, _, _}), do: false
  def precondition(_, _), do: true

  def next_state(_, :ok, {:call, __MODULE__, :disconnect, _}), do: initial_state()

  def next_state(%{inets_pid: :disconnected} = prev_state, result, {:call, __MODULE__, :connect, []}) do
    %{prev_state | inets_pid: result}
  end

  def next_state(%{inets_pid: pid} = prev_state, :ok, {:call, :ftp, :user, [pid, _, _]}), do: %{prev_state | authenticated: true}

  def next_state(state, _, _), do: state

  def postcondition(%{inets_pid: :disconnected}, {:call, __MODULE__, :connect, []}, {:ok, _}) do
    [{_ref, info}] = :ranch.info()
    Keyword.get(info, :all_connections) == 1
    #:inets.services_info()
    #|> Enum.any?(fn
      #{:ftpc, ^pid, _} ->
        #true
      #_ ->
        #false
    #end)
  end

  def postcondition(%{inets_pid: pid}, {:call, __MODULE__, :disconnect, [pid]}, :ok) do
    [{_ref, info}] = :ranch.info()
    Keyword.get(info, :all_connections) == 0
    #:inets.services_info()
    #|> Enum.any?(fn
      #{:ftpc, ^pid, _} ->
        #false
      #_ ->
        #true
    #end)
  end

  def postcondition(_previous_state, _commad, _result), do: true
end
