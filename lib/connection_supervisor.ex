defmodule ConnectionSupervisor do
  use Supervisor
  require Logger

  def start_link(ref, socket, transport, options) do
    # pid  = :proc_lib.spawn_link(__MODULE__, :init, [ref, socket, transport, []])
    {:ok, sup_pid} = start_link([ref, socket, transport, options])
    pid = GenServer.whereis(CommandAcceptor.name(socket)) |> IO.inspect()
    {:ok, sup_pid, pid}
  end

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args)
  end

  def init(args = [_ref, socket, _transport, _options]) do
    children = [
      {ConnectionRouter, [socket]},
      {CommandAcceptor, [self() | args]}
    ]

    IO.puts("I am starting")
    options = [strategy: :one_for_one]
    Supervisor.init(children, options)
  end
end
