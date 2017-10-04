defmodule Ftp do
    
        ## Uncomment the lines below to run this as an application from running
        ## `iex -S mix`
    
        #use Application
        # def start(_type, _args)  do
        #     port = 2121
        #     root_directory = "/home/user"
        #     username = "apc2"
        #     password = "apc2"
        #     ip = "127.0.0.1"
        #     start_server(:myftp1, "127.0.0.1", 2121, /home/user, "apc1", "apc1")
        #     #start_server(:myftp2, ip, 2122, root_directory, "apc2", "apc2")
        #     #start_server(:myftp3, ip, 2123, root_directory, "apc3", "apc3")
        #     #start_server(:myftp4, ip, 2124, root_directory, "apc4", "apc4")
        # end
    
        
        @doc """
        Function to start the server.
        `id`: An `atom` to identify the server
        `ip`: An ip address as `String`
        `port:` The port number server will run on
        `root_directory`: The root directory the server will run from and display to user.
        `username`: The username needed to log into the server. Is \"apc\" by default.
        `password`: The password needed to log into the server. Is \"apc\" by default.
         """
        def start_server(id, ip, port, root_directory, username \\ "apc", password \\ "apc") do
            ip = process_ip(ip)
            server_id = to_string(id)
            :ranch.start_listener(id, 10, :ranch_tcp, [port: port, ip: ip], FtpProtocol, [%{id: server_id, directory: root_directory, username: username, password: password}])
        end
    
        def start_dummy() do
            start_server(:myftp1, "127.0.0.1", 2121, "/home/alan/var/system")
        end
    
        defp process_ip(ip) do
            [h1,h2,h3,h4] = String.split(ip, ".")
            {String.to_integer(h1), String.to_integer(h2), String.to_integer(h3), String.to_integer(h4)}
        end
    
    end