require 'rails_helper'

RSpec.describe 'Api::V1::Rankings', type: :request do
  before { mock_authentication_skipped(true) }

  let(:project) { create(:project, number: 1001) }
  # One owner for every fixture dataset: users.login is unique and the factory
  # does not sequence it.
  let(:owner) { create(:user) }

  def job_for(login, created_at:)
    dataset = create(:data_set, project: project, user: owner)
    create(:job, data_set: dataset, user: login, created_at: created_at)
  end

  it 'counts submissions per user, this month and in total' do
    job_for('alice', created_at: Time.current)
    job_for('alice', created_at: Time.current)
    job_for('alice', created_at: 3.months.ago)
    job_for('bob', created_at: Time.current)

    get '/api/v1/rankings'

    expect(response).to have_http_status(:ok)
    rankings = JSON.parse(response.body)['rankings']
    alice = rankings.find { |r| r['username'] == 'alice' }
    bob = rankings.find { |r| r['username'] == 'bob' }
    expect(alice['jobsThisMonth']).to eq(2)
    expect(alice['totalSubmissions']).to eq(3)
    expect(bob['jobsThisMonth']).to eq(1)
  end

  it 'ranks by this month first' do
    job_for('alice', created_at: 3.months.ago)
    job_for('alice', created_at: 3.months.ago)
    job_for('alice', created_at: 3.months.ago)
    job_for('bob', created_at: Time.current)

    get '/api/v1/rankings'

    expect(JSON.parse(response.body)['rankings'].first['username']).to eq('bob')
  end

  it 'counts a job once even when its input and output are both in scope' do
    input = create(:data_set, project: project, user: owner)
    output = create(:data_set, project: project, user: owner)
    create(:job, data_set: output, input_dataset_id: input.id, user: 'alice')

    get '/api/v1/rankings'

    expect(JSON.parse(response.body)['rankings'].first['totalSubmissions']).to eq(1)
  end

  it 'leaves out projects the caller is not authorized for' do
    job_for('alice', created_at: Time.current)
    other = create(:project, number: 2220)
    create(:job, data_set: create(:data_set, project: other, user: owner), user: 'stranger')

    allow_any_instance_of(Api::V1::RankingsController)
      .to receive(:authorized_project_numbers).and_return([1001])

    get '/api/v1/rankings'

    logins = JSON.parse(response.body)['rankings'].map { |r| r['username'] }
    expect(logins).to include('alice')
    expect(logins).not_to include('stranger')
  end

  it 'is an empty list when the caller has no projects' do
    allow_any_instance_of(Api::V1::RankingsController)
      .to receive(:authorized_project_numbers).and_return([])

    get '/api/v1/rankings'

    expect(JSON.parse(response.body)['rankings']).to eq([])
  end
end
