defmodule Ftp do
    use Application
    def start(_type, _args)  do
        :ranch.start_listener(:my_ftp, 10, :ranch_tcp, [port: 2121], RanchFtpProtocol, [])
    end
end