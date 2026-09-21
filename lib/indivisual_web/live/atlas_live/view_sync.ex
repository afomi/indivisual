defmodule IndivisualWeb.AtlasLive.ViewSync do
  @moduledoc """
  Two (or more) `/atlas` tabs as ONE view: the rules for what they share.

  Every piece of `/atlas` view state is already a URL parameter, so linking tabs
  is a matter of passing a small map between them. Tabs opened with the same
  `?v=<token>` subscribe to one PubSub topic; when a tab's parameters change it
  broadcasts the SHARED ones, and the others patch themselves to match. That is
  what lets the timeline detach into a tab of its own and still drive the view.

  ## Shared, and local

  What is shared is **what is being read**: the filters, the date range and the
  selected record. What stays local to a tab is **how that tab shows it**: which
  pane it is, the Spacetime layout, folded panels, the WebGL fallback. Two tabs
  on one view should agree about the record and are free to disagree about the
  furniture — a timeline tab and a canvas tab are the obvious case.

  ## Trust

  The token is a bearer secret: anyone holding a link with it can steer the
  view. That is acceptable while `/atlas` is public and unowned; when views
  belong to users (`USER_SCOPING.md`) the topic must be scoped to the user as
  well. "Share this view" therefore never includes the token — a shared link is
  a copy of the view, not a seat at it.
  """

  @shared ~w(event entity sources truth speech from to all out fit connected)
  @local ~w(v pane scene axes lanes band tl sc)
  @panes ~w(timeline view)

  @doc "Parameters that tabs on one view keep in common."
  def shared_keys, do: @shared

  @doc "Parameters that belong to one tab."
  def local_keys, do: @local

  @doc "The panes a tab can be, besides the whole page (nil)."
  def panes, do: @panes

  @doc "A fresh view token: 16 URL-safe characters."
  def token, do: 12 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  @doc """
  The token from a parameter, or nil. Anything that does not look like one of
  ours is refused, so a topic name is never built from arbitrary input.
  """
  def parse_token(token) when is_binary(token) do
    if token =~ ~r/\A[A-Za-z0-9_-]{8,64}\z/, do: token
  end

  def parse_token(_), do: nil

  @doc "The pane from a parameter, or nil for the whole page."
  def parse_pane(pane) when pane in @panes, do: pane
  def parse_pane(_), do: nil

  @doc "PubSub topic for a view token."
  def topic(token) when is_binary(token), do: "atlas:view:#{token}"

  @doc "The shared part of a tab's raw (string-keyed) parameters, blanks dropped."
  def shared(params) when is_map(params) do
    params
    |> Map.take(@shared)
    |> Map.reject(fn {_key, value} -> value in [nil, ""] end)
  end

  @doc """
  The parameters a tab should move to on hearing `shared` from another tab: the
  other tab's shared state, and this tab's own local state untouched.
  """
  def adopt(own_params, shared) when is_map(own_params) and is_map(shared) do
    own_params
    |> Map.take(@local)
    |> Map.merge(shared(shared))
  end
end
