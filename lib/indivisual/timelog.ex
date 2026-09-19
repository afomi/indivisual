defmodule Indivisual.Timelog do
  @moduledoc """
  A person's timelog: owned intervals, and the queries that make views of them.

  Every read takes an `Indivisual.Accounts.Scope` as its FIRST argument, and
  there is no clause that accepts `nil`. A timelog has no public tier, so a
  forgotten filter should not be possible to write: omitting the scope is an
  arity error the compiler catches, not a query that quietly returns another
  person's rows. This is the enforcement mechanism USER_SCOPING.md specifies,
  applied here first because this is the app's first user-owned data.

  Entries are intervals. `valid_to == nil` means "still true", so `at/2` — the
  predicate behind every time-based view — is one indexed range check rather
  than a fold over history.

  Writes broadcast on a PER-USER topic. Deliberately not the Atlas feed: that
  is a public, curated instrument whose single process holds the whole stream
  in memory and broadcasts to one global topic. Private, geo-stamped, per-user
  data must not ride that path, even though it shares the vocabulary.
  """

  import Ecto.Query, warn: false

  alias Indivisual.Accounts.Scope
  alias Indivisual.Accounts.User
  alias Indivisual.Repo
  alias Indivisual.Timelog.Entry
  alias Indivisual.Timelog.Line

  @doc "PubSub topic carrying one person's timelog changes."
  def topic(%Scope{user: %User{id: uid}}), do: "timelog:#{uid}"

  @doc "Subscribes the caller to their own timelog changes."
  def subscribe(%Scope{} = scope) do
    Phoenix.PubSub.subscribe(Indivisual.PubSub, topic(scope))
  end

  # --- reads ---

  @doc """
  Entries for this person, newest first.

  Options: `:kind`, `:from`, `:to`, `:limit`.
  """
  def list_entries(scope, opts \\ [])

  def list_entries(%Scope{user: %User{id: uid}}, opts) do
    Entry
    |> where([e], e.user_id == ^uid)
    |> filter_kind(opts[:kind])
    |> filter_window(opts[:from], opts[:to])
    |> order_by([e], desc: e.valid_from, desc: e.id)
    |> maybe_limit(opts[:limit])
    |> Repo.all()
  end

  @doc """
  Entries that were true at `t` — the predicate every time-based view uses.

  An entry with no `valid_to` is still true, so it matches every instant after
  it began. That is the long-showing default doing its job.
  """
  def at(%Scope{user: %User{id: uid}}, %DateTime{} = t) do
    Entry
    |> where([e], e.user_id == ^uid)
    |> where([e], e.valid_from <= ^t)
    |> where([e], is_nil(e.valid_to) or e.valid_to > ^t)
    |> order_by([e], asc: e.valid_from, asc: e.id)
    |> Repo.all()
  end

  @doc "Entries still open (no end), newest first."
  def list_open(%Scope{user: %User{id: uid}}) do
    Entry
    |> where([e], e.user_id == ^uid and is_nil(e.valid_to))
    |> order_by([e], desc: e.valid_from, desc: e.id)
    |> Repo.all()
  end

  @doc "One entry by id, or nil when it is missing OR belongs to someone else."
  def get_entry(%Scope{user: %User{id: uid}}, id) do
    Repo.one(from e in Entry, where: e.id == ^id and e.user_id == ^uid)
  end

  @doc "Entries carrying coordinates, for a map view."
  def list_located(%Scope{user: %User{id: uid}}, opts \\ []) do
    Entry
    |> where([e], e.user_id == ^uid and not is_nil(e.geo))
    |> filter_window(opts[:from], opts[:to])
    |> order_by([e], desc: e.valid_from)
    |> Repo.all()
  end

  @doc "How many entries this person has, optionally of one kind."
  def count_entries(%Scope{user: %User{id: uid}}, opts \\ []) do
    Entry
    |> where([e], e.user_id == ^uid)
    |> filter_kind(opts[:kind])
    |> Repo.aggregate(:count)
  end

  # --- writes ---

  @doc """
  Creates an entry owned by the scope's user.

  `user_id` is applied to the struct rather than cast from attrs, so params
  cannot assign an entry to another person.
  """
  def create_entry(%Scope{user: %User{id: uid}} = scope, attrs) do
    %Entry{user_id: uid}
    |> Entry.changeset(attrs)
    |> Repo.insert()
    |> broadcast(scope, :created)
  end

  @doc """
  Creates an entry from a written line, the way it would be typed in a notes
  file: `worked on trail easement 9-10:30`.

  `notes` is stored as prose. It is not parsed here — capture should never wait
  on understanding — and a later job can structure it without blocking a write.
  """
  def capture(%Scope{} = scope, line, opts \\ []) do
    now = Keyword.get(opts, :now, now())
    notes = Keyword.get(opts, :notes)

    case Line.parse(line, now, notes) do
      {:error, :blank} ->
        {:error, :blank}

      {:ok, parsed} ->
        payload =
          %{"source_line" => String.trim(line)}
          |> maybe_put_note(parsed.notes)

        create_entry(scope, %{
          "kind" => parsed.kind,
          "title" => parsed.title,
          "valid_from" => parsed.valid_from,
          "valid_to" => parsed.valid_to,
          "payload" => payload
        })
    end
  end

  defp maybe_put_note(payload, nil), do: payload
  defp maybe_put_note(payload, notes), do: Map.put(payload, "notes", notes)

  @doc "Starts an open-ended entry: begins now, no end until closed."
  def start_entry(%Scope{} = scope, kind, title, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.merge(%{
        "kind" => kind,
        "title" => title,
        "valid_from" => Map.get(attrs, "valid_from") || Map.get(attrs, :valid_from) || now()
      })

    create_entry(scope, attrs)
  end

  @doc "Closes an open entry at `at` (default now)."
  def close_entry(%Scope{} = scope, %Entry{} = entry, at \\ nil) do
    entry
    |> Entry.close_changeset(at || now())
    |> Repo.update()
    |> broadcast(scope, :updated)
  end

  @doc "Updates an entry the scope's user owns."
  def update_entry(%Scope{} = scope, %Entry{} = entry, attrs) do
    entry
    |> Entry.changeset(attrs)
    |> Repo.update()
    |> broadcast(scope, :updated)
  end

  @doc "Deletes an entry the scope's user owns."
  def delete_entry(%Scope{} = scope, %Entry{} = entry) do
    entry
    |> Repo.delete()
    |> broadcast(scope, :deleted)
  end

  @doc "A blank changeset, for forms."
  def change_entry(%Entry{} = entry, attrs \\ %{}), do: Entry.changeset(entry, attrs)

  # --- query helpers ---

  defp filter_kind(query, nil), do: query
  defp filter_kind(query, kind) when is_binary(kind), do: where(query, [e], e.kind == ^kind)

  defp filter_kind(query, kinds) when is_list(kinds) and kinds != [],
    do: where(query, [e], e.kind in ^kinds)

  defp filter_kind(query, _), do: query

  # A window selects entries that OVERLAP it, not only those contained by it:
  # an entry that began before the window and is still open belongs in it.
  defp filter_window(query, nil, nil), do: query

  defp filter_window(query, from, nil),
    do: where(query, [e], is_nil(e.valid_to) or e.valid_to > ^from)

  defp filter_window(query, nil, to), do: where(query, [e], e.valid_from < ^to)

  defp filter_window(query, from, to) do
    query
    |> where([e], e.valid_from < ^to)
    |> where([e], is_nil(e.valid_to) or e.valid_to > ^from)
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, n) when is_integer(n) and n > 0, do: limit(query, ^n)
  defp maybe_limit(query, _), do: query

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp broadcast({:ok, %Entry{} = entry} = ok, %Scope{} = scope, event) do
    Phoenix.PubSub.broadcast(Indivisual.PubSub, topic(scope), {:timelog, event, entry})
    ok
  end

  defp broadcast(other, _scope, _event), do: other
end
