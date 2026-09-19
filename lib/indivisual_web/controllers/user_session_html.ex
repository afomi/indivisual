defmodule IndivisualWeb.UserSessionHTML do
  use IndivisualWeb, :html

  embed_templates "user_session_html/*"

  # Two conditions, not one. The adapter check alone is not enough: prod
  # inherits Swoosh.Adapters.Local from config/config.exs whenever the runtime
  # mailer config is missing, which is exactly how the dev mailbox link ended up
  # advertised to real users on the login page. :dev_routes is compile-time and
  # false in prod, so /dev/mailbox cannot be linked where it does not route.
  defp local_mail_adapter? do
    Application.get_env(:indivisual, :dev_routes, false) and
      Application.get_env(:indivisual, Indivisual.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
