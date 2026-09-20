defmodule Indivisual.Explain.Fake do
  @moduledoc """
  Deterministic explanation adapter for tests.

  Echoes a fixed sentence plus the first line of the record, so a test can
  assert the prompt reached the adapter without a model running.
  """

  @behaviour Indivisual.Explain

  @impl true
  def explain(prompt, _opts \\ []) do
    title =
      case Regex.run(~r/^Title: (.+)$/m, prompt) do
        [_, t] -> t
        _ -> "an event"
      end

    {:ok, "This record describes #{title}."}
  end
end
