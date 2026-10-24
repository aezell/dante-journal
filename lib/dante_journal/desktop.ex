defmodule DanteJournal.Desktop do
  @moduledoc "The application's single window and its keyboard commands."
  use GPUI.Application

  @impl true
  def identity,
    do: GPUI.Application.Identity.new!(id: "com.alexezell.dante-journal", name: "Dante Journal")

  @impl true
  def mount(state) do
    {:ok,
     [
       window "Dante Journal" do
         size(1200, 780)
         min_size(900, 600)
         chrome(:content)
         shortcut("toggle-theme", "primary-shift-l")
         shortcut("toggle-italian", "primary-i")
         shortcut("next-canto", "primary-shift-n")
         shortcut("previous-canto", "primary-shift-p")
         root(DanteJournal.View, state)
       end
     ]}
  end
end
