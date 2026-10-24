defmodule DanteJournal do
  @moduledoc """
  A native reading journal for the Divine Comedy: dictated notes, transcribed
  on-device and anchored to the canto and tercet they talk about.
  """

  @doc "Starts the note store, the transcription helper and the window under one supervisor."
  def start(opts \\ []) do
    notes_dir = Keyword.get(opts, :notes_dir, DanteJournal.Notes.default_dir())

    opts =
      DanteJournal.Preferences.restore(
        opts,
        opts[:preferences_path] || DanteJournal.Preferences.path()
      )

    # The servers don't exist yet, so the window starts without notes and is
    # told to read them once everything is up.
    state = %{
      DanteJournal.State.initial(opts)
      | notes: DanteJournal.Notes,
        recorder: DanteJournal.Recorder
    }

    children = [
      {DanteJournal.Notes, name: DanteJournal.Notes, dir: notes_dir},
      {DanteJournal.Desktop,
       name: DanteJournal.Runtime,
       args: state,
       display_opts: [name: DanteJournal.Display, theme: state.theme]},
      {DanteJournal.Recorder,
       name: DanteJournal.Recorder,
       sink: {:runtime, DanteJournal.Runtime},
       hotkey: if(state.hotkey == DanteJournal.Keys.off(), do: nil, else: state.hotkey),
       silence_ms: state.pause_ms}
    ]

    with {:ok, supervisor} <- Supervisor.start_link(children, strategy: :rest_for_one) do
      # The store started before the window; now the window can read it.
      GPUI.Runtime.send_view(DanteJournal.Runtime, 1, :refresh_notes)
      {:ok, supervisor}
    end
  end
end
