defmodule Atomcam2NervesApp.Discovery do
  @moduledoc false

  @service_id :nerves_device

  def advertise do
    MdnsLite.add_mdns_service(%{
      id: @service_id,
      protocol: "nerves-device",
      transport: "tcp",
      port: 0,
      txt_payload: [
        "serial=#{Nerves.Runtime.serial_number()}",
        "version=#{application_version()}",
        "product=atomcam2_nerves_app",
        "description=Atom Cam 2 Nerves application",
        "platform=atomcam2",
        "architecture=#{architecture()}"
      ]
    })
  end

  defp application_version do
    :atomcam2_nerves_app
    |> Application.spec(:vsn)
    |> to_string()
  end

  defp architecture do
    :system_architecture
    |> :erlang.system_info()
    |> to_string()
    |> String.split("-", parts: 2)
    |> hd()
  end
end
