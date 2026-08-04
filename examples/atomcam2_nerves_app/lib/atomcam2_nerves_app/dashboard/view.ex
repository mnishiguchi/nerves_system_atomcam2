defmodule Atomcam2NervesApp.Dashboard.View do
  @moduledoc """
  Renders the Collector's internal map as a single self-contained HTML
  page: inline CSS only, no JavaScript, meta-refresh every 10 seconds.
  The JSON API (`/status.json`) is the canonical representation; this is
  just a human-friendly view of the same data.

  The tabs (映像 / 状態 / ログ / 操作) are pure CSS: `:target` selects the
  panel from the URL fragment, and the fragment survives the meta refresh
  so the chosen tab stays put. `:has()` shows the default (映像) tab when
  no fragment is set.
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
        body { font-family: sans-serif; margin: 0; background: #111; color: #ddd; }
        h1 { font-size: 1.1rem; margin: .6rem 1rem; }
        nav { display: flex; border-bottom: 1px solid #444; background: #1a1a1a;
              position: sticky; top: 0; }
        nav a { flex: 1; text-align: center; padding: .7rem .3rem; color: #9cf;
                text-decoration: none; border-right: 1px solid #333; }
        main { padding: 1rem; }
        .panel { display: none; }
        .panel:target { display: block; }
        /* Default tab (映像) when no fragment is selected. */
        body:not(:has(.panel:target)) #live { display: block; }
        /* Highlight the active tab (nav precedes the panels, so use :has). */
        body:has(#status:target) nav a[href="#status"],
        body:has(#logs:target) nav a[href="#logs"],
        body:has(#ops:target) nav a[href="#ops"] { background: #333; color: #fff; }
        body:has(#live:target) nav a[href="#live"],
        body:not(:has(.panel:target)) nav a[href="#live"] { background: #333; color: #fff; }
        table { border-collapse: collapse; margin-bottom: 1rem; width: 100%; max-width: 640px; }
        caption { text-align: left; font-weight: bold; padding: .3rem 0; color: #9cf; }
        td { border: 1px solid #444; padding: .25rem .6rem; font-size: .9rem; }
        td:first-child { color: #aaa; width: 40%; }
        .logs td { font-family: monospace; font-size: .75rem; }
        a { color: #9cf; }
        .ops form { display: inline; }
        .ops button { background: #333; color: #ddd; border: 1px solid #666;
                      padding: .45rem 1rem; margin: 0 .6rem .6rem 0; cursor: pointer; }
        .snap img { max-width: 100%; border: 1px solid #444; display: block; }
        .snap { margin-bottom: 1rem; }
        .rtsp { color: #aaa; font-size: .85rem; word-break: break-all; }
      </style>
    </head>
    <body>
      <nav>
        <a href="#live">映像</a>
        <a href="#status">状態</a>
        <a href="#logs">ログ</a>
        <a href="#ops">操作</a>
      </nav>
      <main>
        <section id="live"   class="panel">#{live_panel(data)}</section>
        <section id="status" class="panel">#{status_panel(data)}</section>
        <section id="logs"   class="panel">#{logs_panel(data)}</section>
        <section id="ops"    class="panel">#{ops_panel()}</section>
      </main>
    </body>
    </html>
    """
  end

  # -- panels ----------------------------------------------------------

  defp live_panel(data) do
    """
    <div class="snap">
      <img src="/snapshot.jpg?#{:erlang.system_time(:second)}" alt="snapshot">
    </div>
    <div class="ops">
      <form method="post" action="/night/on"><button type="submit">夜間 ON</button></form>
      <form method="post" action="/night/auto"><button type="submit">夜間 AUTO</button></form>
      <form method="post" action="/night/off"><button type="submit">夜間 OFF</button></form>
    </div>
    <p class="rtsp">RTSP: #{escape(rtsp_url(data))}</p>
    """
  end

  defp status_panel(data) do
    section("camera", data.camera) <>
      section("system", data.system) <>
      section("memory", data.memory) <>
      section("network", data.network) <>
      section("firmware", data.firmware) <>
      section("storage", data.storage) <>
      "<p><a href=\"/status.json\">status.json</a></p>"
  end

  defp logs_panel(data) do
    logs_section(data.logs) <> announce_history(data.rtsp)
  end

  defp ops_panel do
    """
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
    <p>操作は管理パスワード（利用者 admin）が必要です。</p>
    """
  end

  # -- helpers ---------------------------------------------------------

  defp rtsp_url(%{rtsp: %{url: url}}), do: url
  defp rtsp_url(_data), do: "unavailable"

  defp announce_history(%{announce_history: lines}) when is_list(lines) and lines != [] do
    rows = Enum.map_join(lines, "\n", &"<tr><td>#{escape(&1)}</td></tr>")
    "<table class=\"logs\"><caption>boot announce history</caption>#{rows}</table>"
  end

  defp announce_history(_rtsp), do: ""

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
