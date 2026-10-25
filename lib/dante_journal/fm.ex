defmodule DanteJournal.FM do
  @moduledoc """
  Apple's on-device Foundation Model through the `fm` command (macOS 27).
  Three jobs: classify a note, read a loosely spoken place in the poem, and
  answer a question over the reader's notes. Everything runs locally; the
  model's window is about 8k tokens, so callers keep prompts short.

  `fm` refuses every call until `sudo fm license` has been accepted once;
  `available?/0` reports that, and every other function returns
  `{:error, reason}` rather than raising when the model can't be used.
  """
  alias DanteJournal.{Anchor, Classifier, Tercet, Text}

  @timeout 25_000

  def binary, do: Application.get_env(:dante_journal, :fm_binary, "/usr/bin/fm")

  @doc "Whether the model can be used right now (binary present, licence accepted, model available)."
  def available? do
    File.exists?(binary()) and
      match?({_, 0}, System.cmd(binary(), ["available"], stderr_to_stdout: true))
  rescue
    _ -> false
  end

  # -- Classification ----------------------------------------------------------

  @classification_schema %{
    "title" => "NoteClassification",
    "type" => "object",
    "additionalProperties" => false,
    "x-order" => ["type", "title", "tags"],
    "required" => ["type", "title", "tags"],
    "properties" => %{
      "type" => %{
        "type" => "string",
        "enum" => Enum.map(Classifier.types(), &Atom.to_string/1),
        "description" =>
          "question asks something; insight is the reader's own interpretation; reference points to another text, author or passage; summary restates what happens; quote admires particular words; todo is something to look up or do later; note is anything else"
      },
      "title" => %{"type" => "string", "description" => "A title of at most eight words"},
      "tags" => %{
        "type" => "array",
        "items" => %{"type" => "string"},
        "description" => "One to three lowercase topical tags"
      }
    }
  }

  @doc "The model's reading of a note: `%{type:, title:, tags:}`."
  def classify(text) when is_binary(text) do
    instructions =
      "You classify notes a reader dictates while reading Dante's Divine Comedy. " <>
        "A place reference at the start of a note (canto, stanza, line) is not part of its content."

    with {:ok, map} <-
           respond("Note: '#{String.trim(text)}'",
             instructions: instructions,
             schema: @classification_schema
           ) do
      type = Enum.find(Classifier.types(), :note, &(Atom.to_string(&1) == map["type"]))

      tags =
        map["tags"]
        |> List.wrap()
        |> Enum.filter(&is_binary/1)
        |> Enum.map(&String.downcase/1)
        |> Enum.take(3)

      {:ok, %{type: type, title: String.trim(to_string(map["title"] || "")), tags: tags}}
    end
  end

  # -- Places ------------------------------------------------------------------

  @place_schema %{
    "title" => "PlaceInPoem",
    "type" => "object",
    "additionalProperties" => false,
    "x-order" => ["cantica", "canto", "unit", "from", "to"],
    "required" => ["cantica", "canto", "unit", "from", "to"],
    "properties" => %{
      "cantica" => %{
        "type" => "string",
        "enum" => ["inferno", "purgatorio", "paradiso", "unknown"],
        "description" => "Which cantica the note names, or unknown"
      },
      "canto" => %{"type" => "integer", "description" => "The canto number named, or 0 if none"},
      "unit" => %{
        "type" => "string",
        "enum" => ["line", "stanza", "none"],
        "description" => "Whether the note names lines, a stanza (tercet), or neither"
      },
      "from" => %{"type" => "integer", "description" => "First line or stanza number named, or 0"},
      "to" => %{
        "type" => "integer",
        "description" => "Last line or stanza number named, or the same as from"
      }
    }
  }

  @doc """
  Where a loosely phrased note points, as an anchor with lines, or nil when
  the note names no lines. `current` supplies the cantica and canto when the
  note names only a stanza or lines. Numbers outside the poem are dropped.
  """
  def locate(text, %{cantica: cantica, canto: canto}) when is_binary(text) do
    instructions =
      "You read the opening of a note dictated while reading Dante's Divine Comedy and report where in the poem it points. " <>
        "Only report what the note itself says; use unknown, 0 or none when it doesn't say."

    with {:ok, map} <-
           respond("Note: '#{String.trim(text)}'",
             instructions: instructions,
             schema: @place_schema
           ) do
      {:ok, anchor_from(map, cantica, canto)}
    end
  end

  defp anchor_from(map, current_cantica, current_canto) do
    cantica = Tercet.cantica_from_word(to_string(map["cantica"] || "")) || current_cantica

    canto =
      if is_integer(map["canto"]) and map["canto"] in 1..Text.canto_count(cantica),
        do: map["canto"],
        else: current_canto

    line_count = Text.line_count(:petrocchi, cantica, canto)
    from = map["from"]
    to = if is_integer(map["to"]) and map["to"] > 0, do: map["to"], else: from

    tercets = Tercet.count(line_count)

    case map["unit"] do
      "stanza" when is_integer(from) and from >= 1 and from <= tercets ->
        {a, _} = Tercet.range(from, line_count)
        {_, b} = Tercet.range(min(max(to, from), tercets), line_count)
        %Anchor{cantica: cantica, canto: canto, from_line: a, to_line: b}

      "line" when is_integer(from) and from >= 1 and from <= line_count ->
        %Anchor{
          cantica: cantica,
          canto: canto,
          from_line: from,
          to_line: min(max(to, from), line_count)
        }

      _ ->
        nil
    end
  end

  # -- Questions ---------------------------------------------------------------

  @doc """
  Answers a question from numbered notes. `notes` are `{number, label, type, text, lines}`;
  the answer cites them as `[n]`.
  """
  def ask(question, notes) when is_binary(question) and is_list(notes) do
    instructions =
      "You answer questions about a reader's own notes on Dante's Divine Comedy. " <>
        "Use only the notes and lines given. Cite notes by their number in square brackets, like [2]. " <>
        "Be brief and concrete; if the notes don't answer the question, say so."

    body =
      Enum.map_join(notes, "\n", fn {n, label, type, text, lines} ->
        quoted = if lines == [], do: "", else: "\n    Lines: " <> Enum.join(lines, " / ")
        "[#{n}] #{label} (#{type}): #{text}#{quoted}"
      end)

    respond("Notes:\n#{body}\n\nQuestion: #{String.trim(question)}", instructions: instructions)
  end

  # -- The command -------------------------------------------------------------

  @doc "Runs `fm respond`; with a schema the decoded JSON object is returned."
  def respond(prompt, opts \\ []) do
    schema = Keyword.get(opts, :schema)
    timeout = Keyword.get(opts, :timeout, @timeout)

    with {:ok, schema_path} <- write_schema(schema),
         args =
           ["respond", "--no-stream", "-g"] ++
             instructions_args(opts[:instructions]) ++ schema_args(schema_path) ++ [prompt],
         {:ok, out} <- run(args, timeout) do
      text = out |> strip_ansi() |> String.trim()

      if schema_path, do: File.rm(schema_path)

      cond do
        schema == nil -> {:ok, text}
        true -> decode_object(text)
      end
    end
  end

  defp instructions_args(nil), do: []
  defp instructions_args(text), do: ["-i", text]
  defp schema_args(nil), do: []
  defp schema_args(path), do: ["--schema", path]

  defp write_schema(nil), do: {:ok, nil}

  defp write_schema(schema) do
    path = Path.join(System.tmp_dir!(), "dante-fm-#{System.unique_integer([:positive])}.json")

    case File.write(path, JSON.encode!(schema)) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, "couldn't write schema: #{inspect(reason)}"}
    end
  end

  defp decode_object(text) do
    # The model sometimes wraps JSON in prose or fences; take the outermost object.
    with start when is_integer(start) <- :binary.match(text, "{") |> elem_or_nil(0),
         finish when is_integer(finish) <- last_brace(text),
         {:ok, map} when is_map(map) <- JSON.decode(binary_part(text, start, finish - start + 1)) do
      {:ok, map}
    else
      _ -> {:error, "model returned no JSON object: #{String.slice(text, 0, 120)}"}
    end
  end

  defp elem_or_nil(:nomatch, _), do: nil
  defp elem_or_nil(tuple, i), do: elem(tuple, i)

  defp last_brace(text) do
    case :binary.matches(text, "}") do
      [] -> nil
      matches -> matches |> List.last() |> elem(0)
    end
  end

  defp run(args, timeout) do
    binary = binary()

    if File.exists?(binary) do
      port =
        Port.open({:spawn_executable, binary}, [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          args: args
        ])

      collect(port, "", timeout)
    else
      {:error, "fm is not installed at #{binary}"}
    end
  end

  defp collect(port, acc, timeout) do
    receive do
      {^port, {:data, data}} ->
        collect(port, acc <> data, timeout)

      {^port, {:exit_status, 0}} ->
        {:ok, acc}

      {^port, {:exit_status, status}} ->
        {:error,
         "fm exited #{status}: #{acc |> strip_ansi() |> String.trim() |> String.slice(0, 200)}"}
    after
      timeout ->
        case Port.info(port, :os_pid) do
          {:os_pid, pid} -> System.cmd("kill", [Integer.to_string(pid)])
          _ -> :ok
        end

        {:error, "fm took longer than #{div(timeout, 1000)} s"}
    end
  end

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*[A-Za-z]/, text, "")
end
