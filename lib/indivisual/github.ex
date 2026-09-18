defmodule Indivisual.GitHub do
  @moduledoc """
  Persists a user's work to their own GitHub repository.

  This is the durability story for indivisual: the database holds working
  state, but the user's files live in a repo *they* own. If this app goes away,
  their work does not. That inverts the usual SaaS arrangement, and it is the
  reason sign-in is GitHub-only — the login and the storage are the same grant.

  Writes go through the Git Data API (blobs → tree → commit → ref) rather than
  the simpler Contents API, because that commits N files as ONE commit. The
  Contents API would produce one commit per file, which turns a single save of
  a multi-file visual into a noisy pile of commits.

  Adapted from the pattern proven in `Qart.Sites.GitHubDeployer`.
  """

  require Logger

  @api "https://api.github.com"
  @default_branch "main"

  @doc """
  Commits `files` to `repo` as a single commit on `branch`.

  `files` is a list of `{path, content}` tuples. Content is sent base64-encoded,
  so binary payloads (PNG exports, say) are safe alongside text.

  Returns `{:ok, %{commit_sha: sha, url: html_url}}` or `{:error, reason}`.
  """
  def put_files(token, repo, files, opts \\ [])

  def put_files(token, repo, files, opts)
      when is_binary(token) and token != "" and is_list(files) and files != [] do
    branch = Keyword.get(opts, :branch, @default_branch)
    message = Keyword.get(opts, :message, "Update from indivisual")

    with {:ok, blobs} <- create_blobs(token, repo, files),
         {:ok, base_sha} <- branch_sha(token, repo, branch),
         {:ok, tree_sha} <- create_tree(token, repo, blobs, base_sha),
         {:ok, commit_sha} <- create_commit(token, repo, tree_sha, base_sha, message),
         {:ok, _ref} <- update_ref(token, repo, branch, commit_sha) do
      {:ok,
       %{
         commit_sha: commit_sha,
         url: "https://github.com/#{repo}/commit/#{commit_sha}"
       }}
    end
  end

  def put_files(token, _repo, _files, _opts) when not is_binary(token) or token == "" do
    {:error, :no_github_token}
  end

  def put_files(_token, _repo, [], _opts), do: {:error, :no_files}

  @doc "Returns the authenticated user's GitHub login."
  def whoami(token) do
    case get(token, "/user") do
      {:ok, %{"login" => login}} -> {:ok, login}
      other -> normalize_error(other)
    end
  end

  @doc """
  Ensures `repo` exists for the authenticated user, creating it if absent.

  `private?` defaults to true — a user's working files are their own until they
  decide otherwise.
  """
  def ensure_repo(token, name, opts \\ []) do
    private? = Keyword.get(opts, :private, true)

    case get(token, "/repos/#{name}") do
      {:ok, repo} ->
        {:ok, repo}

      {:error, :not_found} ->
        post(token, "/user/repos", %{
          name: name |> String.split("/") |> List.last(),
          private: private?,
          auto_init: true,
          description: "Files persisted from indivisual.app"
        })

      other ->
        other
    end
  end

  # ── Git Data API steps ──────────────────────────────────────────────────────

  defp create_blobs(token, repo, files) do
    Enum.reduce_while(files, {:ok, []}, fn {path, content}, {:ok, acc} ->
      payload = %{content: Base.encode64(content), encoding: "base64"}

      case post(token, "/repos/#{repo}/git/blobs", payload) do
        {:ok, %{"sha" => sha}} ->
          {:cont, {:ok, [%{path: path, mode: "100644", type: "blob", sha: sha} | acc]}}

        error ->
          {:halt, normalize_error(error)}
      end
    end)
  end

  # Returns {:ok, sha} for an existing branch, or {:ok, nil} for an empty repo
  # where there is no base commit to parent onto.
  defp branch_sha(token, repo, branch) do
    case get(token, "/repos/#{repo}/git/ref/heads/#{branch}") do
      {:ok, %{"object" => %{"sha" => sha}}} -> {:ok, sha}
      {:error, :not_found} -> {:ok, nil}
      other -> normalize_error(other)
    end
  end

  defp create_tree(token, repo, blobs, base_sha) do
    payload =
      if base_sha,
        do: %{base_tree: base_sha, tree: blobs},
        else: %{tree: blobs}

    case post(token, "/repos/#{repo}/git/trees", payload) do
      {:ok, %{"sha" => sha}} -> {:ok, sha}
      other -> normalize_error(other)
    end
  end

  defp create_commit(token, repo, tree_sha, base_sha, message) do
    payload = %{message: message, tree: tree_sha}
    payload = if base_sha, do: Map.put(payload, :parents, [base_sha]), else: payload

    case post(token, "/repos/#{repo}/git/commits", payload) do
      {:ok, %{"sha" => sha}} -> {:ok, sha}
      other -> normalize_error(other)
    end
  end

  defp update_ref(token, repo, branch, commit_sha) do
    # force: false — a non-fast-forward means someone else moved the branch,
    # and silently clobbering the user's own repo history is not ours to do.
    case patch(token, "/repos/#{repo}/git/refs/heads/#{branch}", %{
           sha: commit_sha,
           force: false
         }) do
      {:ok, ref} ->
        {:ok, ref}

      {:error, :not_found} ->
        post(token, "/repos/#{repo}/git/refs", %{
          ref: "refs/heads/#{branch}",
          sha: commit_sha
        })

      other ->
        normalize_error(other)
    end
  end

  # ── HTTP ────────────────────────────────────────────────────────────────────

  defp get(token, path), do: request(:get, token, path, nil)
  defp post(token, path, body), do: request(:post, token, path, body)
  defp patch(token, path, body), do: request(:patch, token, path, body)

  defp request(method, token, path, body) do
    opts = [
      method: method,
      url: @api <> path,
      headers: headers(token),
      receive_timeout: 30_000
    ]

    opts = if body, do: Keyword.put(opts, :json, body), else: opts

    case Req.request(opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("GitHub API #{method} #{path} failed: #{status}")
        {:error, {:http_error, status, github_message(body)}}

      {:error, reason} ->
        Logger.warning("GitHub API #{method} #{path} transport error")
        {:error, {:transport, reason}}
    end
  end

  defp headers(token) do
    [
      {"authorization", "Bearer #{token}"},
      {"accept", "application/vnd.github+json"},
      {"x-github-api-version", "2022-11-28"},
      {"user-agent", "indivisual"}
    ]
  end

  defp github_message(%{"message" => m}), do: m
  defp github_message(_), do: "unknown error"

  defp normalize_error({:ok, _} = ok), do: ok
  defp normalize_error({:error, _} = err), do: err
  defp normalize_error(other), do: {:error, other}
end
