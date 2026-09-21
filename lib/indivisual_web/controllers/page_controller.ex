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

  @doc "/atlas/about — the ideas behind Atlas, at a high level. Static prose."
  def atlas_about(conn, _params) do
    render(conn, :atlas_about, page_title: "About Atlas")
  end
end
