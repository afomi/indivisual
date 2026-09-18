defmodule Indivisual.Workers.EmbedNodeWorker do
  @moduledoc """
  Oban worker that embeds one node's text (FC2.10). Enqueued on node save
  when text-bearing fields change; unique-per-node within a short window so
  rapid edits collapse into one job. Fails (and retries) when the embedding
  backend is unavailable; a deleted node is a no-op.
  """

  use Oban.Worker,
    queue: :embeddings,
    max_attempts: 3,
    unique: [period: 30, keys: [:node_id]]

  alias Indivisual.Repo
  alias Indivisual.Semantic
  alias Indivisual.Visual.Node

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"node_id" => node_id}}) do
    case Repo.get(Node, node_id) do
      nil ->
        :ok

      node ->
        case Semantic.embed_node(node) do
          {:ok, _node} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
