defmodule IndivisualWeb.UserSessionHTML do
  use IndivisualWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:indivisual, Indivisual.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
