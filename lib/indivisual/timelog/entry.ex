defmodule Indivisual.Timelog.Entry do
  @moduledoc """
  One interval in a person's timelog.

  An entry is a span, not an instant: `valid_from` always set, `valid_to` null
  while the entry is still true. That default — "long-showing unless something
  says otherwise" — is what makes a single indexed predicate answer "what was
  true at T", and it is why starting a log takes one action and closing it is a
  separate, optional one.

  `kind` discriminates the log types and `payload` carries whatever that kind
  needs, following the `nodes.kind` + `nodes.metadata` precedent.

  `private_metadata` (ip, precise geolocation, device) is deliberately its own
  column rather than a key inside `payload`. Nothing shared may select it, and
  making that a property of the schema means a future query cannot leak it by
  forgetting a convention.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(reading exercise work event)

  schema "timelog_entries" do
    field :kind, :string
    field :title, :string

    field :valid_from, :utc_datetime
    field :valid_to, :utc_datetime

    field :payload, :map, default: %{}
    field :geo, :map
    field :private_metadata, :map, default: %{}

    field :source_ref, :string

    belongs_to :user, Indivisual.Accounts.User, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc "The log kinds an entry may take."
  def kinds, do: @kinds

  @doc """
  Changeset for creating or updating an entry.

  `user_id` is NOT cast — it is set explicitly from the caller's scope, so a
  crafted param cannot reassign an entry to another person.
  """
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :kind,
      :title,
      :valid_from,
      :valid_to,
      :payload,
      :geo,
      :private_metadata,
      :source_ref
    ])
    |> validate_required([:kind, :title, :valid_from])
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:title, min: 1, max: 500)
    |> validate_interval()
    |> validate_geo()
    |> unique_constraint([:user_id, :source_ref],
      name: :timelog_entries_user_source_ref_index,
      message: "already synced"
    )
    |> check_constraint(:valid_to,
      name: :timelog_entries_valid_interval,
      message: "must be at or after the start"
    )
    |> foreign_key_constraint(:user_id)
  end

  @doc "Closes an open entry at `at`."
  def close_changeset(entry, at) do
    entry
    |> change(valid_to: at)
    |> validate_interval()
    |> check_constraint(:valid_to,
      name: :timelog_entries_valid_interval,
      message: "must be at or after the start"
    )
  end

  defp validate_interval(changeset) do
    from = get_field(changeset, :valid_from)
    to = get_field(changeset, :valid_to)

    if from && to && DateTime.compare(to, from) == :lt do
      add_error(changeset, :valid_to, "must be at or after the start")
    else
      changeset
    end
  end

  # Coordinates reach the canvas as-is, so they are checked on the way in
  # rather than trusted at render time.
  defp validate_geo(changeset) do
    case get_field(changeset, :geo) do
      nil ->
        changeset

      %{} = geo ->
        lat = geo["lat"] || geo[:lat]
        lng = geo["lng"] || geo[:lng]

        cond do
          not is_number(lat) or not is_number(lng) ->
            add_error(changeset, :geo, ~s(needs numeric "lat" and "lng"))

          lat < -90 or lat > 90 ->
            add_error(changeset, :geo, "lat must be between -90 and 90")

          lng < -180 or lng > 180 ->
            add_error(changeset, :geo, "lng must be between -180 and 180")

          true ->
            put_change(changeset, :geo, %{"lat" => lat / 1, "lng" => lng / 1})
        end

      _ ->
        add_error(changeset, :geo, "must be a map")
    end
  end
end
