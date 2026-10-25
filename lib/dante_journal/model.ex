defmodule DanteJournal.Model do
  @moduledoc """
  Runs the on-device model off the view's process and delivers results back
  as `{:fm, event}` messages, so the window never waits on it:

      {:fm, {:available, boolean}}
      {:fm, {:classified, form_id, %{type:, title:, tags:}}}
      {:fm, {:located, form_id, %Anchor{} | nil}}
      {:fm, {:classified_note, note_id, %{title:, tags:}}}
      {:fm, {:located_note, note_id, %Anchor{}}}
      {:fm, {:answer, question, text, cited}} | {:fm, {:answer_failed, question, reason}}
  """
  alias DanteJournal.FM

  def supervisor, do: DanteJournal.Tasks

  def check_availability(sink), do: run(sink, fn -> {:available, FM.available?()} end)

  def classify_form(sink, form_id, text) do
    run(sink, fn ->
      case FM.classify(text) do
        {:ok, result} -> {:classified, form_id, result}
        {:error, reason} -> {:failed, form_id, :classify, reason}
      end
    end)
  end

  def locate_form(sink, form_id, text, current) do
    run(sink, fn ->
      case FM.locate(text, current) do
        {:ok, anchor} -> {:located, form_id, anchor}
        {:error, reason} -> {:failed, form_id, :locate, reason}
      end
    end)
  end

  def classify_note(sink, note_id, text) do
    run(sink, fn ->
      case FM.classify(text) do
        {:ok, result} -> {:classified_note, note_id, Map.take(result, [:title, :tags])}
        {:error, _} -> :noop
      end
    end)
  end

  def locate_note(sink, note_id, text, current) do
    run(sink, fn ->
      case FM.locate(text, current) do
        {:ok, %{} = anchor} -> {:located_note, note_id, anchor}
        _ -> :noop
      end
    end)
  end

  def ask(sink, question, notes) do
    run(sink, fn ->
      case FM.ask(question, notes) do
        {:ok, text} -> {:answer, question, text, Enum.map(notes, &elem(&1, 0))}
        {:error, reason} -> {:answer_failed, question, reason}
      end
    end)
  end

  defp run(sink, fun) do
    Task.Supervisor.start_child(supervisor(), fn ->
      case fun.() do
        :noop -> :ok
        event -> deliver(sink, {:fm, event})
      end
    end)

    :ok
  end

  defp deliver({:runtime, runtime}, message), do: GPUI.Runtime.send_view(runtime, 1, message)
  defp deliver({:pid, pid}, message), do: send(pid, message)
end
