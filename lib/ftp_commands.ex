defmodule FtpCommands do
  @moduledoc """
  Documentation for Ftp.
  """
 
  @server_name __MODULE__
  @debug true
  require Logger
  use GenServer
  
  def start(id, starting_directory) do
    initial_state = %{id: id, root_directory: starting_directory, current_directory: "/", response: "", client_ip: nil, data_port: nil }
    id = String.to_atom(id)
    GenServer.start_link(__MODULE__, initial_state, name: @server_name)
  end

  def init(state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: ip, data_port: data_port}) do
    logger_debug id, "Session Started."
    {:ok, state}
  end

  def get_state() do
    GenServer.call __MODULE__, :get_state
  end

  def set_state(state) do
    GenServer.call __MODULE__, {:set_state, state}
  end

  def list_files() do
    GenServer.call __MODULE__, {:list_files, nil}
  end

  def list_files(path) do
    GenServer.call __MODULE__, {:list_files, path}
  end

  def current_directory() do
    GenServer.call __MODULE__, :current_directory
  end

  def change_working_directory(path) do
    GenServer.call __MODULE__, {:change_working_directory, path}
  end

  def make_directory(path) do
    GenServer.call __MODULE__, {:make_directory, path}
  end
  
  def remove_directory(path) do
    GenServer.call __MODULE__, {:remove_directory, path}
  end

  def remove_file(path) do
    GenServer.call __MODULE__, {:remove_file, path}
  end

  def system_type() do
    GenServer.call __MODULE__, :system_type
  end

  def feat() do
    GenServer.call __MODULE__, :feat
  end

  def type() do
    GenServer.call __MODULE__, :type
  end

  def pasv() do
    GenServer.call __MODULE__, :pasv
  end

  def port(new_ip, new_data_port) do
    GenServer.call __MODULE__, {:port, new_ip, new_data_port}
  end

  def quit() do
    GenServer.call __MODULE__, :quit
  end

  def handle_call(:get_state, _from, state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: ip, data_port: data_port}) do
    {:reply, state, state}
  end

  def handle_call({:set_state, new_state}, _from, state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: ip, data_port: data_port}) do
    {:reply, state, new_state}
  end

  def handle_call({:list_files, path}, _from, state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: ip, data_port: data_port}) do
    new_response = ""
    
    path = case path do
      nil -> cd
      "" -> cd
      _ -> path 
    end 

    path = Enum.join([root_directory, "/", String.trim_leading(path, "/")])

    new_response = case allowed_to_view(root_directory, path) do
      true ->
        logger_debug id, "Listing files in path '#{path}'"
        case File.ls(path) do
          {:ok, files} ->
            sorted_files = Enum.sort(files)
            files_as_string = Enum.join(sorted_files, " ")
            logger_debug id, "226 Files Found: #{files_as_string}\r\n"
            "#{files_as_string}\r\n"
          {:error, reason} ->
            logger_debug id, "550 ls command failed. Reason: #{inspect reason}\r\n"
            to_string(reason)
            "ls command failed. Reason: #{inspect reason}\r\n"
        end
      false ->
        logger_debug id, "You don't have permission to view this file/folder."
        "You don't have permission to view this file/folder.\r\n"
      end


    new_state=%{id: id, root_directory: root_directory, current_directory: cd, response: new_response, client_ip: ip, data_port: data_port}
    {:reply, state, new_state}
  end

  
  def handle_call(:current_directory, _from, state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: ip, data_port: data_port}) do
    logger_debug id, "257 cd: #{inspect cd}"
    user_dir = String.trim(cd, root_directory)
    new_response = "257 \"#{user_dir}\"\r\n"
    new_state=%{id: id, root_directory: root_directory, current_directory: cd, response: new_response, client_ip: ip, data_port: data_port}
    {:reply, state, new_state}
  end

  def handle_call({:change_working_directory, user_path}, _from, state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: ip, data_port: data_port}) do
    cd = 
    case cd do
      "/" -> ""
      _ -> cd
    end

    is_absolute_path =
    case ( user_path == String.trim_leading(user_path, "/") ) do
      true -> false
      false -> true
    end

    path = 
    case is_absolute_path do
      true -> Enum.join([root_directory, user_path])
      false -> Enum.join([root_directory, cd, "/", user_path])
    end

    path = Enum.join([root_directory, cd, "/",String.trim_leading(user_path, "/")])
    {response, new_path} = case File.dir?(path) do
      true ->
        logger_debug id, "250 Current Directory: #{path}"
        path = String.trim(path, root_directory) |> tidy_path |> String.trim_trailing("/")
        
        {"250 Current Directory: #{path}\r\n", path}
      false ->
        logger_debug id, "550 Current path '#{path}' does not exist."
        {"550 Current path '#{user_path}' does not exist\r\n", cd}
    end
    new_state = %{id: id, root_directory: root_directory, current_directory: new_path, response: response, client_ip: ip, data_port: data_port}
    {:reply, state, new_state}
  end

  def handle_call({:make_directory, path}, _from, state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: ip, data_port: data_port}) do
    case File.mkdir_p(path) do
      :ok ->
        logger_debug id, "257 Directory #{path} created."
        response = "257 Directory #{path} created\r\n"
      {:error, reason} ->
        logger_debug id, "550 Directory #{path} could not be created. Reason: #{inspect reason}"
        response = "550 Directory #{path} could not be created. Reason: #{inspect reason}\r\n"
    end
    new_state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: ip, data_port: data_port}
    {:reply, state, new_state}
  end

  def handle_call({:remove_directory, path}, _from, state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: ip, data_port: data_port}) do
    case File.rmdir(path) do
      :ok ->
        logger_debug id, "200 Directory '#{path}' removed."
        response = "200 Directory '#{path}' removed\r\n"
      {:error, reason} ->
        logger_debug id, "550 Error removing directory '#{path}'. Reason: #{inspect reason}"
        response = "550 Error removing directory '#{path}'. Reason: #{inspect reason}\r\n"
    end
    new_state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: ip, data_port: data_port}
    {:reply, state, new_state}
  end

  def handle_call({:remove_file, path}, _from, state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: ip, data_port: data_port}) do
    
    case File.rm(path) do
      :ok->
        logger_debug id, "200 File '#{path}' removed."
        response = "200 File '#{path}' removed\r\n"
      {:error, reason} ->
        logger_debug id, "550 Error removing file '#{path}'. Reason: #{inspect reason}"
        response = "550 Error removing file '#{path}'. Reason: #{inspect reason}\r\n"
    end
    new_state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: ip, data_port: data_port}
    {:reply, state, new_state}
  end

  def handle_call(:system_type, _from, state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: ip, data_port: data_port}) do
    logger_debug id, "215 UNIX Type: L8\r\n"
    new_response = "215 UNIX Type: L8\r\n"
    new_state=%{id: id, root_directory: root_directory, current_directory: cd, response: new_response, client_ip: ip, data_port: data_port}
    {:reply, state, new_state}
  end

  def handle_call(:feat, _from, state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: ip, data_port: data_port}) do
    logger_debug id, "211 no-features\r\n"
    new_response = "211 no-features\r\n"
    new_state=%{id: id, root_directory: root_directory, current_directory: cd, response: new_response, client_ip: ip, data_port: data_port}
    {:reply, state, new_state}
  end

  def handle_call(:type, _from, state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: ip, data_port: data_port}) do
    logger_debug id, "200 ASCII Non-print"
    new_response = "200 ASCII Non-print\r\n"
    new_state=%{id: id, root_directory: root_directory, current_directory: cd, response: new_response, client_ip: ip, data_port: data_port}
    {:reply, state, new_state}
  end

  def handle_call(:pasv, _from, state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: ip, data_port: data_port}) do
    logger_debug id, "227 Entering Passive Mode"
    new_response = "227 Entering Passive Mode\r\n"
    new_state=%{id: id, root_directory: root_directory, current_directory: cd, response: new_response, client_ip: ip, data_port: data_port}
    {:reply, state, new_state}
  end

  def handle_call({:port, new_ip, new_data_port}, _from, state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: ip, data_port: data_port}) do
    logger_debug id, "200 Okay. This is client ip and data_port: IP=#{inspect new_ip} PORT=#{inspect new_data_port}"
    new_response = "200 Okay\r\n"
    new_state=%{id: id, root_directory: root_directory, current_directory: cd, response: new_response, client_ip: new_ip, data_port: new_data_port}
    {:reply, state, new_state}
  end

  def handle_call(:quit, _from, state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: ip, data_port: data_port}) do
    logger_debug id, "221 Session Ended"
    new_response = "221 Session Ended\r\n"
    new_state=%{id: id, root_directory: root_directory, current_directory: cd, response: new_response, client_ip: ip, data_port: data_port}
    {:reply, state, new_state}
  end

  @doc """
  Simple module to check if the user can view a file/folder. Function attempts to 
  perform a `String.trim_leading` call on the `current_path`. If `current_path` is 
  part of the `root_path`, the `String.trim_leading` call will be able to remove the 
  `root_path` string from the `current_path` string. If not, it will simply return 
  the original `current_path`
  """
  def allowed_to_view(root_dir, current_path) do
    case (current_path == root_dir) do
      true ->
        true
      false ->
        case (current_path == String.trim_leading(current_path, root_dir)) do
          true ->
            #logger_debug id, "#{current_path} is not on #{root_dir}"
            false
          false ->
            #logger_debug id, "#{current_path} is on #{root_dir}"
            true
        end
      end
  end


  defp logger_debug(id, message) do
    message = Enum.join(["FTP SERVER #{id}: ", message])
    case @debug do
      true -> Logger.debug(message)
      false -> :ok
    end
  end

  def determine_path(root_dir, current_dir, user_dir) do
    cd =
    case current_dir do
      "/" -> ""
      _ -> ""
    end

    path =
    case is_absolute_path(user_dir) do
      true ->
        user_dir = tidy_path(user_dir)
        server_dir = Enum.join([root_dir, user_dir])
        client_dir = String.trim(server_dir, root_dir)
        %{root_dir: root_dir, current_dir: client_dir, user_dir: user_dir, server_dir: server_dir}
      false ->
        user_dir = tidy_path(user_dir)
        cd = tidy_path(cd)
        server_dir = Enum.join([root_dir, cd, "/" ,user_dir])
        client_dir = String.trim(server_dir, root_dir)
        %{root_dir: root_dir, current_dir: client_dir, user_dir: user_dir, server_dir: server_dir}
    end



  end

  defp tidy_path(path) do
    path = case String.contains?(path, "/../") do
      true ->    
        list = String.trim_trailing(path, "/../") |> String.split("/")
        size = Enum.count(list)
        {_, new_list} = List.pop_at(list, size-1)
        Enum.join(new_list, "/")
      false ->
        path
    end
    
    path = case String.contains?(path, "/..") do
      true ->    
        list = String.trim_trailing(path, "/..") |> String.split("/")
        size = Enum.count(list)
        {_, new_list} = List.pop_at(list, size-1)
        Enum.join(new_list, "/")
      false ->
        path
    end

    ## trim trailing "/"
    String.trim_trailing(path, "/")
  end

  defp is_absolute_path(path) do
    case ( path == String.trim_leading(path, "/") ) do
      true -> false
      false -> true
    end
  end

end
