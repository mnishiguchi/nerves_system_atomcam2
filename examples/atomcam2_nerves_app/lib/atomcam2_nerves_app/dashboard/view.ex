defmodule Atomcam2NervesApp.Dashboard.View do
  @moduledoc """
  Renders the Collector's internal map as a single self-contained HTML
  page. The JSON API (`/status.json`) is the canonical representation;
  this is just a human-friendly view of the same data.

  Tabs (映像 / 状態 / ログ / 操作) sit in a left sidebar and are pure CSS
  via `:target` on the URL fragment. The default tab (映像) is rendered
  last so a following-sibling rule can show it when no fragment is set —
  this avoids `:has()`, which older browsers lack.

  Updates happen in place with no page reload, so there is no flicker and
  the chosen tab stays put: a little vanilla JS swaps the live image's
  `src` every second and re-fetches only the 状態/ログ panels every two
  seconds (the snapshot is rate-limited server-side, so this cannot
  overload the camera).
  """

  @spec page(map()) :: String.t()
  def page(data) do
    """
    <!DOCTYPE html>
    <html lang="ja">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>atomcam2</title>
      <style>
        body { font-family: sans-serif; margin: 0; background: #111; color: #ddd;
               display: flex; min-height: 100vh; }
        nav { display: flex; flex-direction: column; background: #1a1a1a;
              border-right: 1px solid #444; min-width: 6rem; }
        nav .brand { padding: .8rem .6rem; font-weight: bold; color: #ddd;
                     border-bottom: 1px solid #333; }
        nav a { padding: .8rem .6rem; color: #9cf; text-decoration: none;
                border-bottom: 1px solid #262626; }
        nav a:hover { background: #262626; }
        main { padding: 1rem; flex: 1; }
        .panel { display: none; }
        .panel:target { display: block; }
        /* Default tab: 映像 is rendered last, shown by default and hidden
           only when another panel is targeted (following-sibling rule, so
           no :has() needed). */
        #live { display: block; }
        #status:target ~ #live,
        #logs:target ~ #live,
        #ops:target ~ #live,
        #hwtest:target ~ #live { display: none; }
        table { border-collapse: collapse; margin-bottom: 1rem; width: 100%; max-width: 640px; }
        caption { text-align: left; font-weight: bold; padding: .3rem 0; color: #9cf; }
        td { border: 1px solid #444; padding: .25rem .6rem; font-size: .9rem; }
        td:first-child { color: #aaa; width: 40%; }
        .logs td { font-family: monospace; font-size: .75rem; }
        a { color: #9cf; }
        .ops form { display: inline; }
        .ops button { background: #333; color: #ddd; border: 1px solid #666;
                      padding: .45rem 1rem; margin: 0 .6rem .6rem 0; cursor: pointer; }
        .snap img { width: 80%; max-width: 100%; border: 1px solid #444; display: block; }
        .snap { margin-bottom: 1rem; }
        .rtsp { color: #aaa; font-size: .85rem; word-break: break-all; }
      </style>
    </head>
    <body>
      <nav>
        <span class="brand">atomcam2</span>
        <a href="#live">映像</a>
        <a href="#status">状態</a>
        <a href="#logs">ログ</a>
        <a href="#ops">操作</a>
        <a href="#hwtest">動作確認</a>
      </nav>
      <main>
        <section id="status" class="panel">#{status_panel(data)}</section>
        <section id="logs"   class="panel">#{logs_panel(data)}</section>
        <section id="ops"    class="panel">#{ops_panel()}</section>
        <section id="hwtest" class="panel">#{hwtest_panel()}</section>
        <section id="live"   class="panel">#{live_panel(data)}</section>
      </main>
      <script>
        // Remember the selected tab across manual refreshes.
        (function () {
          try {
            if (location.hash) {
              localStorage.setItem('tab', location.hash);
            } else {
              var saved = localStorage.getItem('tab');
              if (saved) { location.replace(saved); }
            }
          } catch (e) {}
        })();
        window.addEventListener('hashchange', function () {
          try { localStorage.setItem('tab', location.hash || ''); } catch (e) {}
        });
        // Refresh the live image every second without reloading (no flicker),
        // only while the 映像 tab is visible.
        setInterval(function () {
          var img = document.getElementById('snap');
          var live = document.getElementById('live');
          if (img && live && live.offsetParent !== null) {
            img.src = '/snapshot.jpg?' + Date.now();
          }
        }, 1000);
        // Refresh the 状態/ログ tables in place every 2 s — no reload, tab kept.
        setInterval(function () {
          fetch('/').then(function (r) { return r.text(); }).then(function (html) {
            var doc = new DOMParser().parseFromString(html, 'text/html');
            ['status', 'logs'].forEach(function (id) {
              var cur = document.getElementById(id), next = doc.getElementById(id);
              if (cur && next) { cur.innerHTML = next.innerHTML; }
            });
          }).catch(function () {});
        }, 2000);
      </script>
    </body>
    </html>
    """
  end

  # -- panels ----------------------------------------------------------

  defp live_panel(data) do
    """
    <div class="snap">
      <img id="snap" src="/snapshot.jpg?#{:erlang.system_time(:second)}" alt="snapshot">
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

  defp hwtest_panel do
    """
    <div class="ops">
      <form method="post" action="/test/blue"><button type="submit">青 LED 点滅</button></form>
      <form method="post" action="/test/yellow"><button type="submit">黄 LED 点滅</button></form>
      <form method="post" action="/test/ir_led"><button type="submit">IR LED 点滅</button></form>
      <form method="post" action="/test/speaker"><button type="submit">スピーカー(発声)</button></form>
      <form method="post" action="/test/mic"><button type="submit">マイク(5秒録音→再生)</button></form>
      <form method="post" action="/test/ircut/on"><button type="submit">IR-cut ON</button></form>
      <form method="post" action="/test/ircut/off"><button type="submit">IR-cut OFF</button></form>
    </div>
    <table>
      <caption>GPIO / 周辺機器</caption>
      <tr><td>青 LED</td><td>GPIO 39 (active-low)</td></tr>
      <tr><td>黄 LED</td><td>GPIO 38 (active-low)</td></tr>
      <tr><td>IR LED</td><td>GPIO 26（肉眼不可・スマホカメラで確認）</td></tr>
      <tr><td>スピーカー</td><td>アンプ GPIO 63・「起動しました」を再生</td></tr>
      <tr><td>マイク</td><td>IMP_AI(8kHz/16bit/mono)で 5 秒録音 → 再生</td></tr>
      <tr><td>IR-cut フィルタ</td><td>GPIO 53/52 Hブリッジ・ON=昼(IR遮断) / OFF=夜(IR透過)</td></tr>
    </table>
    <p>各テストは管理パスワード（利用者 admin）が必要です。IR-cut・夜間 ISP は
    RTSP を止める恐れがあるため動作確認には含めません。</p>
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
