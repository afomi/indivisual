defmodule IndivisualWeb.TopoDataTest do
  @moduledoc """
  /topo is only useful if it ships real data to the client. The viewer needs
  records carrying scores on >= 3 computed axes; short of that it renders its
  "Nothing to plot yet" empty state. These assert the data actually reaches
  the page's data-* attributes.
  """
  use IndivisualWeb.ConnCase, async: true

  alias Indivisual.Repo
  alias Indivisual.Semantic.{Axis, NodeAxisScore}
  alias Indivisual.Space
  alias Indivisual.Visual.Node

  defp seed_plottable_space do
    space = Repo.insert!(%Space{name: "T", slug: "t-#{System.unique_integer([:positive])}"})

    axes =
      for {name, i} <- Enum.with_index(["Permissiveness", "Substance", "Verbosity"]) do
        Repo.insert!(%Axis{
          name: "#{name}-#{System.unique_integer([:positive])}",
          positive_pole: "p",
          negative_pole: "n",
          axis_vector: Enum.map(0..2, &if(&1 == i, do: 1.0, else: 0.0)),
          model: "demo"
        })
      end

    node =
      Repo.insert!(%Node{
        name: "Section 1",
        hash: "h-#{System.unique_integer([:positive])}",
        space_id: space.id,
        metadata: %{"city" => "vacaville", "chapter" => "8"}
      })

    for {axis, score} <- Enum.zip(axes, [-0.7, 0.55, 0.2]) do
      Repo.insert!(%NodeAxisScore{
        node_id: node.id,
        semantic_axis_id: axis.id,
        score: score,
        model: "demo"
      })
    end

    space
  end

  test "ships records, axes and cities to the client", %{conn: conn} do
    space = seed_plottable_space()

    html = conn |> get(~p"/topo/#{space.slug}") |> html_response(200)

    # The node made it into data-records with its city metadata.
    assert html =~ "Section 1"
    assert html =~ "vacaville"

    # Three computed axes reached data-axes — below three, topo won't plot.
    assert html =~ "Permissiveness"
    assert html =~ "Substance"
    assert html =~ "Verbosity"

    # The model appears in data-models, which drives the model selector.
    assert html =~ "demo"

    # And it is NOT the empty state.
    refute html =~ ~s(data-records="[]")
  end

  test "a space with no scored nodes ships empty records", %{conn: conn} do
    space =
      Repo.insert!(%Space{name: "Empty", slug: "empty-#{System.unique_integer([:positive])}"})

    html = conn |> get(~p"/topo/#{space.slug}") |> html_response(200)

    assert html =~ ~s(data-records="[]")
  end

  test "/topo with no slug falls back to a space that has data", %{conn: conn} do
    seed_plottable_space()

    # No slug given — the controller should still find plottable data rather
    # than defaulting to an empty muni-codes space.
    html = conn |> get(~p"/topo") |> html_response(200)

    refute html =~ ~s(data-records="[]")
    assert html =~ "Section 1"
  end
end
