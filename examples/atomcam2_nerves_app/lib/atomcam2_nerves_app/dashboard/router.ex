defmodule Atomcam2NervesApp.Dashboard.Router do
  @moduledoc """
  httpd callback module routing the dashboard's three read-only routes.

  `GET /status.json` is the canonical API: the Collector's internal map
  encoded as JSON (OTP's `:json`). `GET /` renders the same map as HTML.
  Kept as a router (rather than a plain handler) because Phase 2 plans
  POST routes.
  """

  require Record

  Record.defrecordp(:httpd_mod, :mod, Record.extract(:mod, from_lib: "inets/include/httpd.hrl"))

  alias Atomcam2NervesApp.Dashboard.{Collector, View}

  # EWSAPI module callback.
  def unquote(:do)(mod_record) do
    method = httpd_mod(mod_record, :method)
    uri = mod_record |> httpd_mod(:request_uri) |> List.to_string() |> strip_query()

    respond(method, uri)
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
