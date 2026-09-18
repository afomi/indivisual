defmodule Indivisual.Atlas do
  @moduledoc """
  Atlas: a composable interface for making a shared model of reality legible from an
  append-only public event stream.

      append-only source events
              ↓ normalize + preserve provenance   (Indivisual.Atlas.Source)
      canonical event stream                      (Indivisual.Atlas.Stream / Feed)
              ↓ project                           (Indivisual.Atlas.Projections / Topology)
      read models: activity, entity, topology, provenance
              ↓
      people inspect, compare, annotate, and share a projection  (IndivisualWeb.AtlasLive)

  This module is the facade the web layer uses; the modules above hold the logic.
  """

  alias Indivisual.Atlas.Event
  alias Indivisual.Atlas.Feed
  alias Indivisual.Atlas.Projections

  @doc "Projection definitions."
  defdelegate projections, to: Projections, as: :list

  @doc "Truth states in order of settledness."
  defdelegate truth_states, to: Event

  @doc """
  Reads the feed and materializes a projection in one call.

  Options: `:sources` (filter), `:entity` (focus), `:until` (selected event window).
  Returns `{events, read_model}` so callers can show the source events alongside
  the projection and prove the projection did not alter them.
  """
  def read(projection_id, opts \\ []) do
    events = Feed.events(Feed, sources: opts[:sources])
    {events, Projections.materialize(projection_id, events, opts)}
  end

  @doc "Registered sources keyed by id, each with its adapter info."
  defdelegate sources, to: Feed

  @doc "Annotate an event. See `Indivisual.Atlas.Feed.annotate/3`."
  def annotate(about_id, attrs), do: Feed.annotate(Feed, about_id, attrs)
end
