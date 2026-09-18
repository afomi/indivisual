defmodule Indivisual.Embeddings.Ollama do
  @moduledoc """
  Ollama embedding adapter (FC2.8) — local, free, straight HTTP.

  Calls `POST {url}/api/embed` with `{"model": ..., "input": [texts]}`;
  Ollama returns `{"embeddings": [[...], ...]}`. Requires a running Ollama
  with the configured model pulled (see `config :indivisual, Indivisual.Embeddings`).
  Any connection or protocol failure maps to `{:error, :unavailable}` so the
  app degrades gracefully when Ollama is down.
  """

  @behaviour Indivisual.Embeddings

  @impl true
  def embed(texts, opts \\ []) do
    url = Indivisual.Embeddings.url() <> "/api/embed"
    model = Keyword.get(opts, :model, Indivisual.Embeddings.model())

    case Req.post(url,
           json: %{model: model, input: texts},
           receive_timeout: Keyword.get(opts, :timeout, 120_000),
           retry: false
         ) do
      {:ok, %Req.Response{status: 200, body: %{"embeddings" => embeddings}}}
      when length(embeddings) == length(texts) ->
        {:ok, embeddings}

      {:ok, %Req.Response{status: 200, body: body}} ->
        {:error, {:unexpected_response, body}}

      {:ok, %Req.Response{status: 404}} ->
        {:error, {:model_not_found, model}}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, _reason} ->
        {:error, :unavailable}
    end
  end
end
