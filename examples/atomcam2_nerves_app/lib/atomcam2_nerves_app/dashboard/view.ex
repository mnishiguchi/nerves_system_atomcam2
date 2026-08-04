defmodule Atomcam2NervesApp.Dashboard.View do
  @moduledoc """
  Renders the Collector's internal map as a single self-contained HTML
  page: inline CSS only, no JavaScript, meta-refresh every 10 seconds.
  The JSON API (`/status.json`) is the canonical representation; this is
  just a human-friendly view of the same data.
  """

  @spec page(map()) :: String.t()
  def page(data) do
    """
    <!DOCTYPE html>
    <html lang="ja">
    <head>
      <meta charset="utf-8">
      <meta http-equiv="refresh" content="10">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>atomcam2</title>
      <style>
        body { font-family: sans-serif; margin: 1rem; background: #111; color: #ddd; }
        h1 { font-size: 1.2rem; }
        table { border-collapse: collapse; margin-bottom: 1rem; }
        caption { text-align: left; font-weight: bold; padding: .3rem 0; color: #9cf; }
        td { border: 1px solid #444; padding: .25rem .6rem; font-size: .9rem; }
        td:first-child { color: #aaa; }
        .logs td { font-family: monospace; font-size: .75rem; }
        a { color: #9cf; }
        .ops { margin: 1rem 0; }
        .ops form { display: inline; }
        .ops button { background: #333; color: #ddd; border: 1px solid #666;
                      padding: .35rem .9rem; margin-right: .6rem; cursor: pointer; }
      </style>
    </head>
    <body>
      <h1>atomcam2 status</h1>
      #{section("camera", data.camera)}
      #{section("rtsp", data.rtsp)}
      #{section("system", data.system)}
      #{section("memory", data.memory)}
      #{section("network", data.network)}
      #{section("firmware", data.firmware)}
      #{section("storage", data.storage)}
      #{logs_section(data.logs)}
      <div class="ops">
        <form method="post" action="/announce"
              onsubmit="return confirm('テスト発声を再生しますか?')">
          <button type="submit">テスト発声</button>
        </form>
        <form method="post" action="/reboot"
              onsubmit="return confirm('本当に再起動しますか?')">
          <button type="submit">再起動</button>
        </form>
      </div>
      <p><a href="/status.json">status.json</a></p>
    </body>
    </html>
    """
  end

  defp section(title, %{} = fields) do
    rows =
      Enum.map_join(fields, "\n", fn {key, value} ->
        "<tr><td>#{escape(key)}</td><td>#{escape(value)}</td></tr>"
      end)

    "<table><caption>#{title}</caption>#{rows}</table>"
  end

  defp section(title, other) do
    "<table><caption>#{title}</caption><tr><td>#{escape(other)}</td></tr></table>"
  end

  defp logs_section(%{tail: lines}) do
    rows = Enum.map_join(lines, "\n", &"<tr><td>#{escape(&1)}</td></tr>")
    "<table class=\"logs\"><caption>logs</caption>#{rows}</table>"
  end

  defp logs_section(other), do: section("logs", other)

  defp escape(value) when is_list(value), do: value |> Enum.map_join(", ", &escape/1)

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  rescue
    _exception -> inspect(value)
  end
end
