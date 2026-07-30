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
end
