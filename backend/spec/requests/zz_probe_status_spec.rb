require 'rails_helper'
require 'rake'

# Provisioning contract for the ENV-provisioned credentials (`rake
# api_token:env_token`, WRITE=1 for the separate write credential).
#
# Worth pinning because the cutover runbook pastes this task's output straight
# into a node's launch script: if the task ever printed the READ variable names
# while provisioning a WRITE credential, the operator would silently replace the
# read credential's digest with the write one's — turning the credential an agent
# reads production with into a writer, which is the exact failure the two-credential
# design exists to prevent.
#
# The task deliberately has NO :environment prerequisite (it must run where
# DATABASE_URL is unreachable), so these examples exercise it without a database.
#
# NOTE ON THE FILENAME: this file started life as a throwaway probe and the harness
# in this project denies `rm`, `mv` and `git clean`, so it could not be renamed.
# It should be `spec/tasks/env_token_provisioning_spec.rb` — please `git mv` it.
RSpec.describe 'rake api_token:env_token' do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?('api_token:env_token')
  end

  def run_task(env)
    saved = env.keys.to_h { |k| [k, ENV[k]] }
    env.each { |k, v| ENV[k] = v }
    Rake::Task['api_token:env_token'].reenable
    out = StringIO.new
    original = $stdout
    $stdout = out
    begin
      Rake::Task['api_token:env_token'].invoke
    ensure
      $stdout = original
      saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end
    out.string
  end

  describe 'the read credential (default)' do
    subject(:output) { run_task('NAME' => 'chain-082', 'SCOPE' => '35611', 'WRITE' => nil) }

    it 'prints the READ variables and none of the WRITE ones' do
      expect(output).to include("export #{EnvApiToken::DIGEST_VAR}=")
      expect(output).to include("export #{EnvApiToken::SCOPE_VAR}=35611")
      expect(output).to include("export #{EnvApiToken::NAME_VAR}=chain-082")

      EnvApiToken::WRITE_VARS.each { |v| expect(output).not_to include("export #{v}=") }
    end

    it 'says it is read-only and points at WRITE=1 rather than at reuse' do
      expect(output).to match(/READ-ONLY by construction/)
      expect(output).to match(/WRITE=1/)
      expect(output).to match(/never reuse this bearer value/i)
    end
  end

  describe 'the write credential (WRITE=1)' do
    subject(:output) { run_task('NAME' => 'cutover-082', 'SCOPE' => '35611', 'WRITE' => '1') }

    it 'prints the WRITE variables and none of the READ ones' do
      expect(output).to include("export #{EnvApiToken::WRITE_DIGEST_VAR}=")
      expect(output).to include("export #{EnvApiToken::WRITE_SCOPE_VAR}=35611")
      expect(output).to include("export #{EnvApiToken::WRITE_NAME_VAR}=cutover-082")

      EnvApiToken::READ_VARS.each { |v| expect(output).not_to include("export #{v}=") }
    end

    it 'warns that the Rack policy is a separate gate and that the name is the audit trail' do
      expect(output).to match(/SUSHI_WRITE_POLICY must also/)
      expect(output).to match(/apitoken:cutover-082/)
    end
  end

  describe 'the digest it prints' do
    it 'is the unsalted SHA-256 of the raw token the server will recompute' do
      output = run_task('NAME' => 'x', 'SCOPE' => '1', 'WRITE' => nil)
      raw    = output.lines[1].strip
      digest = output[/export #{EnvApiToken::DIGEST_VAR}=(\h{64})/, 1]

      expect(digest).to eq(EnvApiToken.digest_of(raw))
      # Deliberately NOT the secret_key_base-salted ApiToken.digest: the ENV
      # credential must survive a secret rotation.
      expect(digest).not_to eq(ApiToken.digest(raw))
    end
  end

  describe 'input validation, matching what the server accepts at boot' do
    it 'refuses a name the server would reject, so a paste cannot fail at boot' do
      expect { run_task('NAME' => 'two words', 'SCOPE' => '1', 'WRITE' => '1') }
        .to raise_error(SystemExit)
    end

    it 'refuses a non-numeric scope' do
      expect { run_task('NAME' => 'ok', 'SCOPE' => 'p35611', 'WRITE' => '1') }
        .to raise_error(SystemExit)
    end
  end
end
