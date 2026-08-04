defmodule Atomcam2NervesApp.Dashboard.Router do
  @moduledoc """
  httpd callback module routing the dashboard's three read-only routes.

  `GET /status.json` is the canonical API: the Collector's internal map
  encoded as JSON (OTP's `:json`). `GET /` renders the same map as HTML.

  Reads are anonymous. The POST operations (`/announce`, `/reboot`)
  require HTTP Basic auth — user `admin`, password set via
  `Dashboard.set_password/1` — and are rejected while no password is
  configured. CSRF protection is intentionally absent: reads have no
  side effects and writes are authenticated; the HTML buttons add a
  confirm dialog against accidental clicks.
  """

  require Record
  require Logger

  Record.defrecordp(:httpd_mod, :mod, Record.extract(:mod, from_lib: "inets/include/httpd.hrl"))

  alias Atomcam2NervesApp.Dashboard.{Collector, Server, View}

  @announce_command "/usr/bin/atomcam2-boot-announce"

  # EWSAPI module callback.
  def unquote(:do)(mod_record) do
    method = httpd_mod(mod_record, :method)
    uri = mod_record |> httpd_mod(:request_uri) |> List.to_string() |> strip_query()

    case method do
      ~c"POST" -> authorized(mod_record, fn -> operate(uri) end)
      _other -> respond(method, uri)
    end
  end

  defp respond(~c"GET", "/status.json") do
    body = Collector.collect() |> jsonable() |> :json.encode() |> IO.iodata_to_binary()
    reply(200, "application/json", body)
  end

  defp respond(~c"GET", "/") do
    reply(200, "text/html; charset=utf-8", View.page(Collector.collect()))
  end

  defp respond(~c"GET", "/healthz") do
    reply(200, "text/plain", "ok")
  end

  defp respond(_method, _uri) do
    reply(404, "text/plain", "not found")
  end

  # -- Phase 2: authenticated operations ------------------------------

  defp operate("/announce") do
    {:ok, _pid} = Task.start(fn -> System.cmd(@announce_command, [], stderr_to_stdout: true) end)
    Logger.info("Dashboard: announce requested")
    redirect_home("announce started")
  end

  defp operate("/reboot") do
    Logger.warning("Dashboard: reboot requested")

    {:ok, _pid} =
      Task.start(fn ->
        # Let the response reach the client first.
        Process.sleep(1_000)
        Nerves.Runtime.reboot()
      end)

    reply(200, "text/plain", "rebooting")
  end

  defp operate(_uri), do: reply(404, "text/plain", "not found")

  defp authorized(mod_record, on_authorized) do
    header = mod_record |> httpd_mod(:parsed_header) |> List.keyfind(~c"authorization", 0)

    with {_key, ~c"Basic " ++ encoded} <- header,
         {:ok, decoded} <- Base.decode64(List.to_string(encoded)),
         ["admin", password] <- String.split(decoded, ":", parts: 2),
         true <- Server.password_valid?(password) do
      on_authorized.()
    else
      _no_or_bad_credentials ->
        {:proceed,
         [
           response:
             {:response,
              [
                code: 401,
                content_type: ~c"text/plain",
                content_length: ~c"12",
                www_authenticate: ~c"Basic realm=\"atomcam2\""
              ], ~c"unauthorized"}
         ]}
    end
  end

  # The HTML form lands here after the POST; send the browser back to
  # the dashboard rather than showing a bare text page.
  defp redirect_home(message) do
    body = "#{message} - <a href=\"/\">back</a>"

    {:proceed,
     [
       response:
         {:response,
          [
            code: 200,
            content_type: ~c"text/html",
            content_length: body |> byte_size() |> Integer.to_charlist()
          ], :binary.bin_to_list(body)}
     ]}
  end

  defp reply(code, content_type, body) when is_binary(body) do
    head = [
      code: code,
      content_type: String.to_charlist(content_type),
      content_length: body |> byte_size() |> Integer.to_charlist()
    ]

    {:proceed, [response: {:response, head, :binary.bin_to_list(body)}]}
  end

  defp strip_query(uri), do: uri |> String.split("?", parts: 2) |> hd()

  # OTP's :json encodes the atom nil as the string "nil"; JSON null is
  # the atom :null. Normalizing here keeps the Collector encoding-agnostic.
  defp jsonable(nil), do: :null
  defp jsonable(%{} = map), do: Map.new(map, fn {key, value} -> {key, jsonable(value)} end)
  defp jsonable(list) when is_list(list), do: Enum.map(list, &jsonable/1)
  defp jsonable(other), do: other
end
