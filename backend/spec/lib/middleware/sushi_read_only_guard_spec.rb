require 'rails_helper'
require Rails.root.join('lib', 'middleware', 'sushi_read_only_guard').to_s

# Server-side read-only write gate (design v3, multi-LLM R2): a Rack middleware so
# EVERY controller hierarchy (/api/v1 via ApplicationController, /v1 + /internal via
# ActionController::Base, auth controllers) is covered uniformly — a per-controller
# before_action would miss the ActionController::Base surfaces.
RSpec.describe Middleware::SushiReadOnlyGuard do
  let(:downstream) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['ok']] } }
  subject(:mw) { described_class.new(downstream) }

  def env_for(method, path)
    { 'REQUEST_METHOD' => method, 'PATH_INFO' => path }
  end

  after { ENV.delete('SUSHI_READ_ONLY'); ENV.delete('SUSHI_WRITE_POLICY') }

  context 'when SUSHI_READ_ONLY is unset' do
    it 'passes mutating requests through untouched' do
      expect(mw.call(env_for('POST', '/api/v1/jobs'))[0]).to eq 200
    end
  end

  context 'when SUSHI_WRITE_POLICY=additive' do
    before { ENV['SUSHI_WRITE_POLICY'] = 'additive' }

    it 'allows safe (GET) requests' do
      expect(mw.call(env_for('GET', '/api/v1/projects/35611/datasets'))[0]).to eq 200
    end

    it 'allows additive create-only routes (job submit, dataset import)' do
      expect(mw.call(env_for('POST', '/api/v1/jobs'))[0]).to eq 200
      expect(mw.call(env_for('POST', '/v1/datasets/register'))[0]).to eq 200
      expect(mw.call(env_for('POST', '/api/v1/datasets/from_tsv'))[0]).to eq 200
      expect(mw.call(env_for('POST', '/v1/datasets/validate'))[0]).to eq 200 # dry-run
    end

    it 'exempts the internal machine bridge (job_manager state updates)' do
      expect(mw.call(env_for('PATCH', '/internal/legacy/jobs/1'))[0]).to eq 200
      expect(mw.call(env_for('GET',   '/internal/legacy/jobs'))[0]).to eq 200
    end

    it 'blocks destructive/rewrite user ops with 403 additive' do
      status, _h, body = mw.call(env_for('DELETE', '/v1/datasets/1'))
      expect(status).to eq 403
      expect(JSON.parse(body.join)['error']).to eq 'additive'
    end

    # A PUT by verb, but set-once by behaviour: DatasetRegistrationService.set_bfabric_id
    # fills the field only when NULL and answers 409 for a different value, so it never
    # rewrites. Denying it left a dataset New SUSHI created on a production DB with no way
    # to record its B-Fabric id at all.
    it 'allows the set-once B-Fabric id link (id segment, pattern-matched)' do
      expect(mw.call(env_for('PUT', '/v1/datasets/1/bfabric-id'))[0]).to eq 200
      expect(mw.call(env_for('PUT', '/v1/datasets/12345/bfabric-id'))[0]).to eq 200
    end

    it 'does not let the bfabric-id pattern widen into neighbouring routes' do
      expect(mw.call(env_for('PUT',    '/v1/datasets/1/bfabric-id/extra'))[0]).to eq 403
      expect(mw.call(env_for('PUT',    '/v1/datasets/abc/bfabric-id'))[0]).to eq 403
      expect(mw.call(env_for('DELETE', '/v1/datasets/1/bfabric-id'))[0]).to eq 403
      expect(mw.call(env_for('PUT',    '/v1/datasets/1'))[0]).to eq 403
    end

    it 'blocks a non-allowlisted mutating POST' do
      expect(mw.call(env_for('POST', '/api/v1/datasets/1/rename'))[0]).to eq 403
    end
  end

  context 'when SUSHI_WRITE_POLICY=read_only overrides' do
    before { ENV['SUSHI_WRITE_POLICY'] = 'read_only' }

    it 'blocks additive routes too (stricter than additive)' do
      expect(mw.call(env_for('POST', '/api/v1/jobs'))[0]).to eq 403
      expect(mw.call(env_for('PATCH', '/internal/legacy/jobs/1'))[0]).to eq 403
    end
  end

  context 'when SUSHI_READ_ONLY=1' do
    before { ENV['SUSHI_READ_ONLY'] = '1' }

    it 'allows safe (GET) requests' do
      expect(mw.call(env_for('GET', '/api/v1/projects/35611/datasets'))[0]).to eq 200
    end

    it 'blocks POST /api/v1/jobs with 403 read_only' do
      status, _headers, body = mw.call(env_for('POST', '/api/v1/jobs'))
      expect(status).to eq 403
      expect(JSON.parse(body.join)['error']).to eq 'read_only'
    end

    it 'blocks mutating verbs on /v1 (ActionController::Base surface)' do
      expect(mw.call(env_for('PUT',    '/v1/datasets/1/bfabric-id'))[0]).to eq 403
      expect(mw.call(env_for('DELETE', '/v1/datasets/1'))[0]).to eq 403
    end

    it 'blocks PATCH on the /internal machine bridge' do
      expect(mw.call(env_for('PATCH', '/internal/legacy/jobs/1'))[0]).to eq 403
    end

    it 'allows the non-mutating validate allowlist POST' do
      expect(mw.call(env_for('POST', '/v1/datasets/validate'))[0]).to eq 200
    end

    it 'allows allowlisted path variants (trailing slash, .format suffix)' do
      expect(mw.call(env_for('POST', '/v1/datasets/validate/'))[0]).to eq 200
      expect(mw.call(env_for('POST', '/v1/datasets/validate.json'))[0]).to eq 200
    end

    it 'returns a lowercase content-type header (Rack 3 spec)' do
      _status, headers, _body = mw.call(env_for('POST', '/api/v1/jobs'))
      expect(headers).to have_key('content-type')
    end
  end

  # submit_only exists so that a backend sharing a database with the live legacy production
  # system exposes exactly ONE way to write: submitting a job. Every other write route —
  # dataset import, the set-once B-Fabric link, and the whole internal bridge — is closed, so
  # a new app or an AI agent calling an individual endpoint cannot reach the database through
  # it. The routes it closes have no live producer today; see L2
  # new_sushi_deferred_write_surface_and_bfabric_rework_after_normal_operation.
  context 'when SUSHI_WRITE_POLICY=submit_only' do
    before { ENV['SUSHI_WRITE_POLICY'] = 'submit_only' }

    it 'allows safe (GET) requests' do
      expect(mw.call(env_for('GET', '/api/v1/projects/35611/datasets'))[0]).to eq 200
    end

    it 'allows the non-mutating validate allowlist POST, which writes nothing by design' do
      expect(mw.call(env_for('POST', '/v1/datasets/validate'))[0]).to eq 200
    end

    it 'allows job submission — the one write this policy exists to permit' do
      expect(mw.call(env_for('POST', '/api/v1/jobs'))[0]).to eq 200
    end

    it 'allows the job route in its normalized variants, as the other policies do' do
      expect(mw.call(env_for('POST', '/api/v1/jobs/'))[0]).to eq 200
      expect(mw.call(env_for('POST', '/api/v1/jobs.json'))[0]).to eq 200
    end

    it 'closes the two dataset import routes that additive allows' do
      expect(mw.call(env_for('POST', '/v1/datasets/register'))[0]).to eq 403
      expect(mw.call(env_for('POST', '/api/v1/datasets/from_tsv'))[0]).to eq 403
    end

    it 'closes the set-once B-Fabric id link' do
      # Nothing in this backend registers anything in B-Fabric, so no caller produces an id
      # for this route to record. It reopens with the B-Fabric rework, not before.
      expect(mw.call(env_for('PUT', '/v1/datasets/1/bfabric-id'))[0]).to eq 403
    end

    it 'closes the internal bridge — the additive exemption does NOT apply here' do
      # This is the only surface the write policy did not previously cover at all: under
      # additive, /internal/ passes for EVERY verb. The daemon reads MySQL directly and had
      # no caller on these routes as of 2026-08-07, so closing them costs nothing.
      expect(mw.call(env_for('PATCH', '/internal/legacy/jobs/1'))[0]).to eq 403
      expect(mw.call(env_for('POST',  '/internal/legacy/datasets/register'))[0]).to eq 403
    end

    it 'closes DELETE and mutating PUT/PATCH generally' do
      expect(mw.call(env_for('DELETE', '/v1/datasets/1'))[0]).to eq 403
      expect(mw.call(env_for('PUT',    '/v1/datasets/1'))[0]).to eq 403
      expect(mw.call(env_for('PATCH',  '/api/v1/datasets/1'))[0]).to eq 403
    end

    it 'names itself in the denial, so an operator can tell WHICH gate refused' do
      status, _headers, body = mw.call(env_for('POST', '/v1/datasets/register'))
      expect(status).to eq 403
      expect(JSON.parse(body.join)['error']).to eq 'submit_only'
    end

    # The allowed route is matched EXACTLY, not by prefix. A prefix match would silently open
    # every route living under the job path.
    it 'matches the job route exactly and does not open its neighbours' do
      expect(mw.call(env_for('POST', '/api/v1/jobs/123/cancel'))[0]).to eq 403
      expect(mw.call(env_for('POST', '/api/v1/jobsomething'))[0]).to eq 403
      expect(mw.call(env_for('POST', '/api/v1/jobs/123'))[0]).to eq 403
    end

    it 'allows only POST on the job route, not other verbs' do
      expect(mw.call(env_for('DELETE', '/api/v1/jobs'))[0]).to eq 403
      expect(mw.call(env_for('PUT',    '/api/v1/jobs'))[0]).to eq 403
    end
  end

  # Adding a policy value edits the one line every posture resolves through, so the other
  # three are pinned here rather than trusted to the 543-example baseline.
  context 'policy resolution' do
    it 'leaves the historical default alone: unset means full, and full writes everything' do
      expect(mw.call(env_for('POST',   '/api/v1/jobs'))[0]).to eq 200
      expect(mw.call(env_for('DELETE', '/v1/datasets/1'))[0]).to eq 200
      expect(mw.call(env_for('PATCH',  '/internal/legacy/jobs/1'))[0]).to eq 200
    end

    it 'honours an explicit full exactly as an unset variable does' do
      ENV['SUSHI_WRITE_POLICY'] = 'full'
      expect(mw.call(env_for('DELETE', '/v1/datasets/1'))[0]).to eq 200
    end

    it 'keeps read_only stricter than submit_only: even job submission is refused' do
      ENV['SUSHI_WRITE_POLICY'] = 'read_only'
      expect(mw.call(env_for('POST', '/api/v1/jobs'))[0]).to eq 403
    end

    it 'still lets a valid explicit policy win over SUSHI_READ_ONLY=1' do
      ENV['SUSHI_READ_ONLY'] = '1'
      ENV['SUSHI_WRITE_POLICY'] = 'submit_only'
      expect(mw.call(env_for('POST', '/api/v1/jobs'))[0]).to eq 200
    end

    # A misconfiguration must not be read as a request for `full`. This database is shared
    # with the live legacy production system, so a typo that silently granted every write
    # would be the worst possible reading of an operator's intent. An UNSET variable is not a
    # typo and keeps the historical default, which the example above pins.
    it 'fails CLOSED on a non-empty value it does not recognize' do
      ['submitonly', 'submit-only', 'additivee', 'SUBMIT_ONLY_PLEASE', 'yes'].each do |bad|
        ENV['SUSHI_WRITE_POLICY'] = bad
        status, _headers, body = mw.call(env_for('POST', '/api/v1/jobs'))
        expect(status).to eq(403), "expected #{bad.inspect} to fail closed, got #{status}"
        expect(JSON.parse(body.join)['error']).to eq 'read_only'
      end
    end

    it 'accepts a valid policy irrespective of surrounding whitespace and case' do
      ENV['SUSHI_WRITE_POLICY'] = '  Submit_Only  '
      expect(mw.call(env_for('POST', '/api/v1/jobs'))[0]).to eq 200
      expect(mw.call(env_for('POST', '/v1/datasets/register'))[0]).to eq 403
    end
  end
end
