defmodule IndivisualWeb.PageController do
  use IndivisualWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  @doc """
  Liveness probe for the ALB target group. Deliberately trivial: it answers
  whether this node is up and serving, not whether downstream deps are healthy,
  so a transient DB blip doesn't pull every instance out of service.
  """
  def healthz(conn, _params) do
    send_resp(conn, 200, "ok")
  end

  @doc """
  /topo — 3D semantic-axis space. Records from a space (default muni-codes)
  positioned by their scores on three semantic axes; the client renders a
  Three.js scatter with per-city toggles and axis remapping.
  """
  def topo(conn, params) do
    space =
      Indivisual.Spaces.get_space_by_slug(
        params["space_slug"] || Indivisual.MuniCodes.space_slug()
      )

    axes = Indivisual.Semantic.list_axes(computed_only: true)

    {records, models} =
      case space do
        nil ->
          {[], []}

        space ->
          scores = Indivisual.Semantic.node_scores_for_space(space)

          records =
            for node <- Indivisual.Spaces.list_nodes_for_space(space),
                node_scores = Map.get(scores, node.id, %{}),
                map_size(node_scores) > 0 do
              %{
                id: node.id,
                name: node.name,
                city: node.metadata["city"],
                chapter: node.metadata["chapter"],
                section_count: node.metadata["section_count"],
                earliest_year: node.metadata["earliest_year"],
                latest_year: node.metadata["latest_year"],
                # Keyed by embedding model: %{model => %{axis_id => score}}.
                scores: node_scores
              }
            end

          {records, Indivisual.Semantic.score_models_for_space(space)}
      end

    cities =
      records
      |> Enum.map(& &1.city)
      |> Enum.uniq()
      |> Enum.map(fn city ->
        coords = Indivisual.MuniCodes.city_coordinates()[city] || %{lat: nil, lng: nil}
        %{city: city, lat: coords.lat, lng: coords.lng}
      end)

    topics =
      case space do
        nil ->
          %{}

        space ->
          space
          |> Indivisual.Semantic.topic_models_for_space()
          |> Map.new(fn tm ->
            {tm.model, %{k: tm.k, topics: tm.topics, placements: tm.placements}}
          end)
      end

    render(conn, :topo,
      view: "muni",
      cocktails_json: "null",
      records_json: Jason.encode!(records),
      cities_json: Jason.encode!(cities),
      models_json: Jason.encode!(models),
      topics_json: Jason.encode!(topics),
      axes_json:
        Jason.encode!(
          Enum.map(axes, fn a ->
            %{
              id: a.id,
              name: a.name,
              negative_pole: a.negative_pole,
              positive_pole: a.positive_pole
            }
          end)
        )
    )
  end
end
