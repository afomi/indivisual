defmodule Indivisual.Explain.Ollama do
  @moduledoc """
  Ollama explanation adapter — local, free, straight HTTP.

  Calls `POST {url}/api/generate` with `stream: false`. Any connection or
  protocol failure maps to `{:error, :unavailable}` so the page degrades to
  showing no explanation rather than an error.

  `think: false` matters for the qwen3 family: without it the model emits a
  reasoning block before the answer, which would be shown to the reader.
  """

  @behaviour Indivisual.Explain

  require Logger

  @impl true
  def explain(prompt, opts \\ []) do
    url = Indivisual.Explain.url() <> "/api/generate"
    model = Keyword.get(opts, :model, Indivisual.Explain.model())

    body = %{
      model: model,
      prompt: prompt,
      stream: false,
      think: false,
      options: %{temperature: 0.2}
    }

    case Req.post(url,
           json: body,
           receive_timeout: Keyword.get(opts, :timeout, 60_000),
           retry: false
         ) do
      {:ok, %Req.Response{status: 200, body: %{"response" => text}}} when is_binary(text) ->
        case clean(text) do
          "" -> {:error, :empty_response}
          cleaned -> {:ok, cleaned}
        end

      {:ok, %Req.Response{status: 404}} ->
        {:error, {:model_not_found, model}}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("Explain: ollama returned #{status}")
        {:error, {:http_error, status}}

      {:error, _reason} ->
        {:error, :unavailable}
    end
  end

  @doc """
  Installed models that can write, from `GET {url}/api/tags`.

  That endpoint lists everything pulled, including embedding models, which cannot
  generate text — and this app's own embedding model is one of them. It reports
  no capability, so embedding models are recognised by family (`bert`-derived)
  or by `embed` in the name. A heuristic, stated as one: a model it wrongly keeps
  fails on use with a clear error rather than silently.
  """
  @impl true
  def models do
    case Req.get(Indivisual.Explain.url() <> "/api/tags", receive_timeout: 5_000, retry: false) do
      {:ok, %Req.Response{status: 200, body: %{"models" => models}}} when is_list(models) ->
        {:ok,
         models
         |> Enum.reject(&embedding?/1)
         |> Enum.map(& &1["name"])
         |> Enum.filter(&is_binary/1)
         |> Enum.sort()}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("Explain: ollama /api/tags returned #{status}")
        {:error, {:http_error, status}}

      {:error, _reason} ->
        {:error, :unavailable}
    end
  end

  @doc false
  def embedding?(%{} = model) do
    name = to_string(model["name"])

    families =
      List.wrap(get_in(model, ["details", "families"])) ++ [get_in(model, ["details", "family"])]

    String.contains?(String.downcase(name), "embed") or
      Enum.any?(families, &(is_binary(&1) and String.contains?(String.downcase(&1), "bert")))
  end

  # Strip a reasoning block if the model emits one despite `think: false`.
  defp clean(text) do
    text
    |> String.replace(~r/<think>.*?<\/think>/s, "")
    |> String.trim()
  end
end
