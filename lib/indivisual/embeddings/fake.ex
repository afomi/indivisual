defmodule Indivisual.Embeddings.Fake do
  @moduledoc """
  Deterministic test adapter (FC2.8): each text maps to a stable pseudo-random
  unit vector, so semantic-axis math is testable without any backend. Similar
  texts do NOT get similar vectors — identity only.

  Tests needing controlled geometry can register exact vectors:

      Indivisual.Embeddings.Fake.put("verbose text", [1.0, 0.0, 0.0])
  """

  @behaviour Indivisual.Embeddings

  @dimensions 8

  @impl true
  def embed(texts, _opts \\ []) do
    {:ok, Enum.map(texts, &vector_for/1)}
  end

  @doc "Register an exact vector for a text (per-process, for tests)."
  def put(text, vector) do
    Process.put({__MODULE__, text}, vector)
    :ok
  end

  defp vector_for(text) do
    case Process.get({__MODULE__, text}) do
      nil -> deterministic_vector(text)
      vector -> vector
    end
  end

  defp deterministic_vector(text) do
    raw =
      for i <- 1..@dimensions do
        h = :erlang.phash2({text, i}, 10_000)
        h / 5_000 - 1.0
      end

    Indivisual.Semantic.VectorMath.normalize(raw)
  end
end
