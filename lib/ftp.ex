defmodule Ftp do
    use Application
    def start(_type, _args)  do
        port = 2121
        root_directory = "/home/user"
        username = "apc2"
        password = "apc2"
        ip = "127.0.0.1"
        start_server(ip, port, root_directory, username, password)
    end

    def start_server(ip, port, root_directory, username, password) do
        ip = process_ip(ip)
        :ranch.start_listener(:my_ftp, 10, :ranch_tcp, [port: port, ip: ip], RanchFtpProtocol, [%{directory: root_directory, username: username, password: password}])
    end

    defp process_ip(ip) do
        [h1,h2,h3,h4] = String.split(ip, ".")
        {String.to_integer(h1), String.to_integer(h2), String.to_integer(h3), String.to_integer(h4)}
    end

end