defmodule Atomcam2NervesApp.NasExporter.Config do
  @moduledoc false

  @default_port 22
  @default_poll_interval_seconds 60
  @default_retention_days 20
  @default_max_spool_bytes 512 * 1024 * 1024

  @allowed_keys ~w(
    enabled
    host
    port
    user
    user_dir
    remote_directory
    poll_interval_seconds
    retention_days
    max_spool_bytes
  )

  @enforce_keys [:enabled]
  defstruct enabled: false,
            host: nil,
            port: @default_port,
            user: nil,
            user_dir: nil,
            remote_directory: nil,
            poll_interval_ms: @default_poll_interval_seconds * 1_000,
            retention_days: @default_retention_days,
            max_spool_bytes: @default_max_spool_bytes

  @type t :: %__MODULE__{
          enabled: boolean(),
          host: String.t() | nil,
          port: pos_integer(),
          user: String.t() | nil,
          user_dir: String.t() | nil,
          remote_directory: String.t() | nil,
          poll_interval_ms: pos_integer(),
          retention_days: pos_integer(),
          max_spool_bytes: pos_integer()
        }

  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, values} <- parse(contents) do
      build(values)
    end
  end

  @doc false
  @spec parse(String.t()) :: {:ok, map()} | {:error, term()}
  def parse(contents) when is_binary(contents) do
    contents
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, %{}}, &parse_line/2)
  end

  @doc false
  @spec build(map()) :: {:ok, t()} | {:error, term()}
  def build(values) when is_map(values) do
    with {:ok, enabled} <- required_boolean(values, "enabled"),
         {:ok, poll_interval_seconds} <-
           optional_integer(
             values,
             "poll_interval_seconds",
             @default_poll_interval_seconds,
             60..3_600
           ),
         {:ok, retention_days} <-
           optional_integer(values, "retention_days", @default_retention_days, 1..3_650),
         {:ok, max_spool_bytes} <-
           optional_integer(
             values,
             "max_spool_bytes",
             @default_max_spool_bytes,
             1..9_223_372_036_854_775_807
           ) do
      config = %__MODULE__{
        enabled: enabled,
        poll_interval_ms: poll_interval_seconds * 1_000,
        retention_days: retention_days,
        max_spool_bytes: max_spool_bytes
      }

      if enabled do
        build_enabled(config, values)
      else
        {:ok, config}
      end
    end
  end

  defp build_enabled(config, values) do
    with {:ok, host} <- required_text(values, "host"),
         {:ok, port} <- optional_integer(values, "port", @default_port, 1..65_535),
         {:ok, user} <- required_text(values, "user"),
         {:ok, user_dir} <- required_absolute_path(values, "user_dir"),
         {:ok, remote_directory} <- required_remote_directory(values) do
      {:ok,
       %{
         config
         | host: host,
           port: port,
           user: user,
           user_dir: user_dir,
           remote_directory: remote_directory
       }}
    end
  end

  defp parse_line({line, line_number}, {:ok, values}) do
    line = String.trim(line)

    cond do
      line == "" or String.starts_with?(line, "#") ->
        {:cont, {:ok, values}}

      true ->
        case String.split(line, "=", parts: 2) do
          [key, value] ->
            key = String.trim(key)
            value = String.trim(value)

            cond do
              key not in @allowed_keys ->
                {:halt, {:error, {:unknown_key, line_number, key}}}

              value == "" ->
                {:halt, {:error, {:empty_value, line_number, key}}}

              Map.has_key?(values, key) ->
                {:halt, {:error, {:duplicate_key, line_number, key}}}

              true ->
                {:cont, {:ok, Map.put(values, key, value)}}
            end

          _other ->
            {:halt, {:error, {:invalid_line, line_number}}}
        end
    end
  end

  defp required_boolean(values, key) do
    case Map.fetch(values, key) do
      {:ok, "true"} -> {:ok, true}
      {:ok, "false"} -> {:ok, false}
      {:ok, _value} -> {:error, {:invalid_boolean, key}}
      :error -> {:error, {:missing_key, key}}
    end
  end

  defp required_text(values, key) do
    case Map.fetch(values, key) do
      {:ok, value} when value != "" -> {:ok, value}
      {:ok, _value} -> {:error, {:empty_value, key}}
      :error -> {:error, {:missing_key, key}}
    end
  end

  defp optional_integer(values, key, default, range) do
    case Map.fetch(values, key) do
      {:ok, value} ->
        case Integer.parse(value) do
          {integer, ""} ->
            if integer >= range.first and integer <= range.last do
              {:ok, integer}
            else
              {:error, {:invalid_integer, key}}
            end

          _other ->
            {:error, {:invalid_integer, key}}
        end

      :error ->
        {:ok, default}
    end
  end

  defp required_absolute_path(values, key) do
    with {:ok, path} <- required_text(values, key),
         true <- Path.type(path) == :absolute do
      {:ok, Path.expand(path)}
    else
      false -> {:error, {:path_must_be_absolute, key}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp required_remote_directory(values) do
    with {:ok, directory} <- required_text(values, "remote_directory"),
         {:ok, normalized} <- normalize_remote_directory(directory) do
      {:ok, normalized}
    end
  end

  defp normalize_remote_directory(directory) do
    normalized = String.trim_trailing(directory, "/")

    components =
      normalized
      |> String.split("/", trim: true)

    cond do
      normalized in ["", "/"] ->
        {:error, {:unsafe_remote_directory, "remote_directory"}}

      normalized == "." ->
        {:ok, normalized}

      Enum.any?(components, &(&1 in [".", ".."])) ->
        {:error, {:unsafe_remote_directory, "remote_directory"}}

      String.contains?(normalized, <<0>>) ->
        {:error, {:unsafe_remote_directory, "remote_directory"}}

      true ->
        {:ok, normalized}
    end
  end
end
