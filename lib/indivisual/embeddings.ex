defmodule Indivisual.Embeddings do
  @moduledoc """
  Text embeddings behind a swappable adapter (FC2.8).

  Configured via:

      config :indivisual, Indivisual.Embeddings,
        adapter: Indivisual.Embeddings.Ollama,
        url: "http://localhost:11434",
        model: "nomic-embed-text"

  The app must work fully without an embedding backend: adapters return
  `{:error, :unavailable}` rather than raising, and callers surface that.
  """

  @callback embed(texts :: [String.t()], opts :: keyword()) ::
              {:ok, [[float()]]} | {:error, term()}

  @doc """
  Embeds a list of texts. Returns `{:ok, vectors}` (one vector per text,
  in order) or `{:error, reason}` — `:unavailable` when the backend is down.
  """
  def embed(texts, opts \\ [])
  def embed([], _opts), do: {:ok, []}
  def embed(texts, opts) when is_list(texts), do: adapter().embed(texts, opts)

  @doc "The configured adapter module."
  def adapter, do: Keyword.get(config(), :adapter, Indivisual.Embeddings.Ollama)

  @doc "The configured embedding model name (recorded on axes and scores)."
  def model, do: Keyword.get(config(), :model, "nomic-embed-text")

  @doc "Base URL of the embedding backend."
  def url, do: Keyword.get(config(), :url, "http://localhost:11434")

  defp config, do: Application.get_env(:indivisual, __MODULE__, [])
end
