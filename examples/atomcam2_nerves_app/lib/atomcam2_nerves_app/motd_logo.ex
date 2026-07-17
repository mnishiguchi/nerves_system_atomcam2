defmodule Atomcam2NervesApp.MOTDLogo do
  @moduledoc false

  @width 48
  @height 44

  @background 234
  @white 255
  @silver 250
  @body 239
  @body_shadow 238
  @disc 233
  @black 16

  @ring_dark 237
  @ring_mid 243
  @ring_inner 247

  @magenta 201
  @violet 129
  @cyan 45
  @green 82
  @yellow 226

  @lens_dark 234
  @lens_center 153

  @reset "\e[0m"

  @spec render() :: String.t()
  def render do
    camera =
      0..(@height - 1)
      |> Enum.map(fn y ->
        for x <- 0..(@width - 1) do
          pixel_at(x, y)
        end
      end)
      |> Enum.chunk_every(2)
      |> Enum.map_join("\n", fn [upper_row, lower_row] ->
        render_pixel_row(upper_row, lower_row)
      end)

    """
    #{camera}#{@reset}
    \e[38;5;255m                   ATOM CAM 2#{@reset}
    """
  end

  defp render_pixel_row(upper_row, lower_row) do
    upper_row
    |> Enum.zip(lower_row)
    |> Enum.chunk_by(& &1)
    |> Enum.map_join(fn pixel_run ->
      {upper_color, lower_color} = hd(pixel_run)

      ansi_pixel(upper_color, lower_color) <>
        String.duplicate("▀", length(pixel_run))
    end)
  end

  defp ansi_pixel(upper_color, lower_color) do
    "\e[38;5;#{upper_color};48;5;#{lower_color}m"
  end

  defp pixel_at(x, y) do
    lens_x = x - 24
    lens_y = y - 17
    lens_distance = squared_distance(lens_x, lens_y)

    cond do
      lens_highlight?(x, y) ->
        @white

      lens_distance <= 1 ->
        @lens_center

      lens_distance <= 4 ->
        @lens_dark

      lens_distance <= 12 ->
        lens_color(lens_x, lens_y)

      lens_distance <= 18 ->
        @ring_inner

      lens_distance <= 27 ->
        @ring_dark

      lens_distance <= 36 ->
        @ring_mid

      lens_distance <= 45 ->
        @ring_dark

      lens_distance <= 52 ->
        @black

      camera_hole?(x, y) ->
        @black

      lens_distance <= 150 ->
        @disc

      inside_rounded_rectangle?(x, y, 8, 2, 39, 33, 4) ->
        body_color(y)

      inside_rounded_rectangle?(x, y, 7, 1, 40, 34, 4) ->
        @white

      inside_rounded_rectangle?(x, y, 9, 36, 38, 43, 2) ->
        stand_color(y)

      true ->
        @background
    end
  end

  defp lens_color(x, y) do
    cond do
      y < 0 and x < -1 -> @magenta
      y < 0 and x <= 1 -> @violet
      y < 0 -> @cyan
      x > 0 -> @green
      y > 0 -> @yellow
      true -> @magenta
    end
  end

  defp lens_highlight?(x, y) do
    squared_distance(x - 22, y - 15) <= 1
  end

  defp camera_hole?(x, y) do
    squared_distance(x - 24, y - 7) <= 1 or
      squared_distance(x - 24, y - 27) <= 1
  end

  defp body_color(y) when y >= 31, do: @body_shadow
  defp body_color(_y), do: @body

  defp stand_color(y) when y >= 42, do: @silver
  defp stand_color(_y), do: @white

  defp squared_distance(x, y), do: x * x + y * y

  defp inside_rounded_rectangle?(
         x,
         y,
         left,
         top,
         right,
         bottom,
         radius
       ) do
    cond do
      x < left or x > right or y < top or y > bottom ->
        false

      x in (left + radius)..(right - radius) ->
        true

      y in (top + radius)..(bottom - radius) ->
        true

      true ->
        corner_x =
          if x < left + radius do
            left + radius
          else
            right - radius
          end

        corner_y =
          if y < top + radius do
            top + radius
          else
            bottom - radius
          end

        squared_distance(x - corner_x, y - corner_y) <=
          radius * radius
    end
  end
end
