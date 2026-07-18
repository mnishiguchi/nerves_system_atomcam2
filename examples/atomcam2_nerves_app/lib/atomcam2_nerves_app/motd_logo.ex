defmodule Atomcam2NervesApp.MOTDLogo do
  @moduledoc false

  @width 40
  @height 30
  @label "ATOM CAM 2"

  # Geometry

  @lens_center {20, 13}
  @lens_highlight {18, 11}
  @camera_holes [{20, 5}, {20, 21}]

  @camera_outer {8, 1, 32, 25}
  @camera_inner {9, 2, 31, 24}
  @camera_corner_radius 3

  @leg {9, 26, 31, 29}

  @body_shadow_start_y 22
  @leg_seam_y 26
  @leg_shadow_y 29

  # Palette

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
  @lens_center_color 153

  @reset "\e[0m"

  @spec render() :: IO.ANSI.ansidata()
  def render do
    [
      render_camera(),
      @reset,
      "\n",
      foreground(@white),
      centered_label(),
      @reset,
      "\n"
    ]
  end

  defp render_camera do
    0..(@height - 1)
    |> Enum.map(&render_source_row/1)
    |> Enum.chunk_every(2)
    |> Enum.map(fn [upper_row, lower_row] ->
      render_terminal_row(upper_row, lower_row)
    end)
    |> Enum.intersperse("\n")
  end

  defp render_source_row(y) do
    for x <- 0..(@width - 1) do
      pixel_at(x, y)
    end
  end

  defp render_terminal_row(upper_row, lower_row) do
    upper_row
    |> Enum.zip(lower_row)
    |> Enum.chunk_by(& &1)
    |> Enum.map(fn pixel_run ->
      {upper_color, lower_color} = hd(pixel_run)

      [
        ansi_half_block(upper_color, lower_color),
        List.duplicate("▀", length(pixel_run))
      ]
    end)
  end

  defp centered_label do
    padding = div(@width - String.length(@label), 2)

    [
      String.duplicate(" ", padding),
      @label
    ]
  end

  defp foreground(color) do
    [
      "\e[38;5;",
      Integer.to_string(color),
      "m"
    ]
  end

  defp ansi_half_block(upper_color, lower_color) do
    [
      "\e[38;5;",
      Integer.to_string(upper_color),
      ";48;5;",
      Integer.to_string(lower_color),
      "m"
    ]
  end

  defp pixel_at(x, y) do
    lens_distance = squared_distance_from(x, y, @lens_center)
    {lens_x, lens_y} = offset_from(x, y, @lens_center)

    cond do
      inside_circle?(x, y, @lens_highlight, 1) ->
        @white

      lens_distance <= 1 ->
        @lens_center_color

      lens_distance <= 3 ->
        @lens_dark

      lens_distance <= 8 ->
        lens_color(lens_x, lens_y)

      lens_distance <= 12 ->
        @ring_inner

      lens_distance <= 18 ->
        @ring_dark

      lens_distance <= 23 ->
        @ring_mid

      lens_distance <= 29 ->
        @ring_dark

      lens_distance <= 34 ->
        @black

      camera_hole?(x, y) ->
        @black

      lens_distance <= 98 ->
        @disc

      inside_rounded_rectangle?(
        x,
        y,
        @camera_inner,
        @camera_corner_radius
      ) ->
        body_color(y)

      inside_rounded_rectangle?(
        x,
        y,
        @camera_outer,
        @camera_corner_radius
      ) ->
        @white

      inside_rectangle?(x, y, @leg) ->
        leg_color(y)

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

  defp camera_hole?(x, y) do
    Enum.any?(@camera_holes, fn center ->
      inside_circle?(x, y, center, 1)
    end)
  end

  defp body_color(y) when y >= @body_shadow_start_y, do: @body_shadow
  defp body_color(_y), do: @body

  defp leg_color(@leg_seam_y), do: @body_shadow
  defp leg_color(@leg_shadow_y), do: @silver
  defp leg_color(_y), do: @white

  defp inside_circle?(x, y, center, radius) do
    squared_distance_from(x, y, center) <= radius * radius
  end

  defp squared_distance_from(x, y, {center_x, center_y}) do
    squared_distance(x - center_x, y - center_y)
  end

  defp offset_from(x, y, {center_x, center_y}) do
    {x - center_x, y - center_y}
  end

  defp squared_distance(x, y) do
    x * x + y * y
  end

  defp inside_rectangle?(x, y, {left, top, right, bottom}) do
    x >= left and
      x <= right and
      y >= top and
      y <= bottom
  end

  defp inside_rounded_rectangle?(
         x,
         y,
         {left, top, right, bottom} = rectangle,
         radius
       ) do
    if inside_rectangle?(x, y, rectangle) do
      nearest_x = clamp(x, left + radius, right - radius)
      nearest_y = clamp(y, top + radius, bottom - radius)

      squared_distance(x - nearest_x, y - nearest_y) <=
        radius * radius
    else
      false
    end
  end

  defp clamp(value, minimum, maximum) do
    value
    |> max(minimum)
    |> min(maximum)
  end
end
