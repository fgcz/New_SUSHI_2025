require 'rails_helper'

# Who may submit a job from an INTERACTIVE (JWT) session.
#
# This surface had no authorization of its own. Only the bearer-token branch was
# ever checked, and the two other cutover gates — `ApiToken#can_write?` and the
# absent `capabilities` column — guard that same bearer surface. So the moment the
# Rack write policy permits POST /api/v1/jobs, a signed-in user is checked by
# nothing at all. Both gates below exist because of that.
RSpec.describe 'Api::V1::Jobs submission authorization', type: :request do
  let(:user) { create(:user, login: 'testuser') }
  let(:project) { create(:project, number: 1001) }
  let(:other_project) { create(:project, number: 9999) }
  let(:dataset) { create(:data_set, project: project, user: user) }
  let(:foreign_dataset) { create(:data_set, project: other_project, user: user) }

  before do
    create(:sample, data_set: dataset, key_value: "{'Name' => 'S1', 'Read1' => '/p/f.fastq'}")
    create(:sample, data_set: foreign_dataset, key_value: "{'Name' => 'S1', 'Read1' => '/p/f.fastq'}")

    mock_authentication_skipped(false)
    mock_ldap_auth_enabled(true)
    allow(FGCZ).to receive(:get_user_projects2).and_return(['p1001'])
  end

  def submit(dataset_id)
    post '/api/v1/jobs',
         params: {
           job: {
             dataset_id: dataset_id,
             app_name: 'FastqcApp',
             next_dataset_name: 'Output',
             parameters: {}
           }
         },
         headers: jwt_headers_for(user)
  end

  describe 'the project gate' do
    before { allow(FGCZ).to receive(:employee?).and_return(true) }

    it 'refuses a dataset in a project the user is not a member of' do
      expect { submit(foreign_dataset.id) }.not_to change(Job, :count)

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('Forbidden')
    end

    it 'refuses a dataset id that does not exist' do
      expect { submit(99_999_999) }.not_to change(Job, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end

  # INTERIM. Legacy SUSHI does not restrict submission to employees — any signed-in
  # user may submit into their own projects — so this is deliberately stricter than
  # parity while the New SUSHI submit path earns confidence on production.
  describe 'the employee gate' do
    it 'refuses a non-employee and says why, since they cannot fix it' do
      allow(FGCZ).to receive(:employee?).with('testuser').and_return(false)

      expect { submit(dataset.id) }.not_to change(Job, :count)

      expect(response).to have_http_status(:forbidden)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('not_an_employee')
      expect(body['message']).to match(/FGCZ employees/)
    end

    it 'asks the directory about the signed-in user, not somebody else' do
      allow(FGCZ).to receive(:employee?).and_return(false)

      submit(dataset.id)

      expect(FGCZ).to have_received(:employee?).with('testuser')
    end

    # FGCZ.employee? returns false on any error — library missing, directory
    # unreachable. That must deny, never admit.
    it 'denies when the directory cannot be consulted' do
      allow(FGCZ).to receive(:employee?).and_return(false)

      expect { submit(dataset.id) }.not_to change(Job, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it 'lets an employee through to the submission itself' do
      allow(FGCZ).to receive(:employee?).with('testuser').and_return(true)

      submit(dataset.id)

      # Not asserting success: whether the run can actually be built depends on the
      # app and the sample columns. What matters here is that neither gate refused.
      expect(response).not_to have_http_status(:forbidden)
    end
  end

  # The gates must not fire where they never applied, or every headless caller and
  # every dev node breaks.
  describe 'surfaces the gates deliberately leave alone' do
    it 'does not consult the directory when authentication is skipped' do
      mock_authentication_skipped(true)
      allow(FGCZ).to receive(:employee?)

      submit(dataset.id)

      expect(FGCZ).not_to have_received(:employee?)
    end
  end
end
