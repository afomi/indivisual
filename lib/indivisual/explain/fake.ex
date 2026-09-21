defmodule Indivisual.Explain.Fake do
  @moduledoc """
  Deterministic explanation adapter for tests.

  Echoes a fixed sentence plus the first line of the record, so a test can
  assert the prompt reached the adapter without a model running.
  """

  @behaviour Indivisual.Explain

  @models ["fake-small", "fake-large"]

  @impl true
  def models, do: {:ok, @models}

  # The model is named in the answer, so a test can tell whose words it is reading.
  @impl true
  def explain(prompt, opts \\ []) do
    by =
      case Keyword.get(opts, :model) do
        model when model in @models -> " (#{model})"
        _ -> ""
      end

    title =
      case Regex.run(~r/^Title: (.+)$/m, prompt) do
        [_, t] -> t
        _ -> "an event"
      end

    {:ok, "This record describes #{title}.#{by}"}
  end
end
