defmodule DanteJournal do
  @moduledoc """
  A native reading journal for the Divine Comedy: dictated notes, transcribed
  on-device and anchored to the canto and tercet they talk about.
  """

  @doc "Starts the native window and its workers under one supervisor."
  def start(opts \\ []) do
    state = DanteJournal.State.initial(opts)

    runtime =
      {DanteJournal.Desktop,
       name: DanteJournal.Runtime,
       args: state,
       display_opts: [name: DanteJournal.Display, theme: state.theme]}

    Supervisor.start_link([runtime], strategy: :rest_for_one)
  end
end
