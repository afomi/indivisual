defmodule IndivisualWeb.AtlasFilterDismissTest do
  @moduledoc """
  A filter is dismissed from the row that names it, and a dismissal is a view
  change like any other — so a tab showing the timeline in its own window has
  to hear it. The dismissal goes through the same patch as every other change,
  which is what makes that true rather than a second path to keep in step.
  """
  use IndivisualWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias IndivisualWeb.AtlasLive.ViewSync

  describe "dismissing from column 1" do
    test "every applied filter carries a ✕", %{conn: conn} do
      {:ok, view, _} =
        live(conn, ~p"/atlas?from=1&to=3&truth=observed&speech=verb&entity=plan:eltsp")

      for id <- ~w(range truth speech entity) do
        assert has_element?(view, "#atlas-applied-#{id}-clear"),
               "#{id} should be dismissible where it is named"
      end
    end

    test "a range dismissal clears both bounds", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=3")

      view |> element("#atlas-applied-range-clear") |> render_click()

      path = assert_patch(view)
      refute path =~ "from="
      refute path =~ "to="
    end

    test "an outside-range reads as dismissible too", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas?from=1&to=3&out=1")

      assert view |> element("#atlas-applied-range") |> render() =~ "Outside"
      assert has_element?(view, "#atlas-applied-range-clear")
    end

    test "the ✕ sits outside the chip, to its left", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/atlas?from=1&to=3")

      # The chip names a filter; the button removes it. Keeping the button out
      # of the chip leaves the chip's border unbroken and says which acts on
      # which.
      refute has_element?(view, "#atlas-applied-range #atlas-applied-range-clear")

      assert has_element?(view, ".atlas-chipgroup #atlas-applied-range-clear")
      assert has_element?(view, ".atlas-chipgroup #atlas-applied-range")

      at = fn id -> html |> :binary.match(~s(id="#{id}")) |> elem(0) end
      assert at.("atlas-applied-range-clear") < at.("atlas-applied-range")
    end

    test "nothing applied means nothing to dismiss", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/atlas")

      refute has_element?(view, "#atlas-applied .atlas-entitychip")
      refute has_element?(view, "#atlas-applied-range-clear")
    end
  end

  describe "a detached pane hears it" do
    test "the range is shared state, so it reaches a linked tab" do
      # from/to are shared keys: a tab showing only the timeline adopts them.
      assert "from" in ViewSync.shared_keys()
      assert "to" in ViewSync.shared_keys()
    end

    test "dismissing broadcasts to the view's linked tabs", %{conn: conn} do
      token = "abcdefgh1234"
      Phoenix.PubSub.subscribe(Indivisual.PubSub, ViewSync.topic(token))

      {:ok, view, _} = live(conn, ~p"/atlas?v=#{token}&from=1&to=3")

      view |> element("#atlas-applied-range-clear") |> render_click()
      assert_patch(view)

      assert_receive {:view_state, _from, shared}, 500

      refute Map.has_key?(shared, "from"),
             "a detached timeline must learn the range is gone"

      refute Map.has_key?(shared, "to")
    end

    test "dismissing another filter broadcasts too", %{conn: conn} do
      token = "hgfedcba4321"
      Phoenix.PubSub.subscribe(Indivisual.PubSub, ViewSync.topic(token))

      {:ok, view, _} = live(conn, ~p"/atlas?v=#{token}&truth=observed")

      view |> element("#atlas-applied-truth-clear") |> render_click()
      assert_patch(view)

      assert_receive {:view_state, _from, shared}, 500
      refute Map.has_key?(shared, "truth")
    end
  end
end
