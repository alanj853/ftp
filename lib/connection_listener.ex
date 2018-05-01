defmodule ConnectionListener do
  use GenServer

  def start_link({:name, name}) do
    gen_server_name = String.to_atom(to_string(name) <> "_connection_listener")
    GenServer.start_link(__MODULE__, {:name, name}, name: gen_server_name)
  end

  def init({:name, name}) do
    name = String.to_atom(to_string(name) <> "_ranch_listener")

    res =
      :ranch.start_listener(
        name,
        10,
        :ranch_tcp,
        [port: 2121, ip: {0, 0, 0, 0}, connection_type: :supervisor],
        ConnectionSupervisor,
        []
      )

    IO.puts("Started this server #{inspect(res)}")
    {:ok, %{}}
  end
end
