class AddCapabilitiesToApiTokens < ActiveRecord::Migration[8.0]
  # Per-token write authority, so authorization is not project-scope alone.
  #
  # Until now a token's authority was entirely "which projects", with no read vs
  # write distinction, and the /v1 endpoint allowlist restricted only USER
  # principals while static principals passed unconditionally. That inverts the
  # accountability: a static service credential (fixed scope, attributed as
  # "apitoken:<name>", long-lived) had MORE authority than a person's token.
  #
  # It only stayed safe on the production node because that instance runs
  # server-side read-only. The moment SUSHI_WRITE_POLICY moves to `additive` for
  # the write-path cutover, every in-scope token — including the read-only MCP
  # credential — becomes able to submit real production jobs. This column is what
  # keeps that policy flip from being a privilege escalation.
  #
  # Additive: new nullable column on a New-SUSHI-owned table, no legacy table
  # touched. NULL means read-only (fail-closed), so existing tokens do not gain
  # write authority from this migration; grant it explicitly with
  # `rake api_token:grant_write ID=<id>`.
  def change
    add_column :api_tokens, :capabilities, :text
  end
end
