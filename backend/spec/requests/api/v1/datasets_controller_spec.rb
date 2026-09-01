require 'rails_helper'

RSpec.describe 'Api::V1::Datasets', type: :request do
  let(:user) { create(:user, login: 'testuser') }
  let(:project) { create(:project, number: 1001) }

  # Reading a dataset is authorized by PROJECT MEMBERSHIP, not by ownership.
  #
  # Every other example in this file creates its dataset with `user: user`, i.e.
  # owned by whoever is signed in, so the ownership scoping that used to be here
  # passed all of them. Production does not look like that: measured on 082,
  # dataset 113260 in project 35611 has a NULL `user_id`, and 9 of the 19 datasets
  # in that project belong to somebody else. The first authenticated session on
  # that node got "Dataset not found" for 98% of the database.
  describe 'reading a dataset the signed-in user does not OWN' do
    let(:someone_else) { create(:user, login: 'colleague') }
    let(:foreign_dataset) { create(:data_set, name: 'Not mine', project: project, user: someone_else) }
    let(:ownerless_dataset) { create(:data_set, name: 'No owner', project: project, user: nil) }

    # LDAP has to be ON for membership to come from LDAP at all: with it off the
    # resolver falls back to "every project that exists", which is the behaviour the
    # project and gStore surfaces already have and is why the rest of this file
    # passes without stubbing FGCZ. Worth knowing on its own — a node with
    # SUSHI_REQUIRE_AUTH=1 and no LDAP grants every signed-in user everything.
    before do
      mock_authentication_skipped(false)
      mock_ldap_auth_enabled(true)
    end

    context 'and IS a member of its project' do
      before { allow(FGCZ).to receive(:get_user_projects2).and_return(['p1001']) }

      it 'serves it' do
        get "/api/v1/datasets/#{foreign_dataset.id}", headers: jwt_headers_for(user)

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)['name']).to eq('Not mine')
      end

      it 'serves one with no owner at all, as production has' do
        get "/api/v1/datasets/#{ownerless_dataset.id}", headers: jwt_headers_for(user)

        expect(response).to have_http_status(:success)
      end

      it 'serves its tree and its sample rows too, not just the show payload' do
        get "/api/v1/datasets/#{foreign_dataset.id}/tree", headers: jwt_headers_for(user)
        expect(response).to have_http_status(:success)

        get "/api/v1/datasets/#{foreign_dataset.id}/samples", headers: jwt_headers_for(user)
        expect(response).to have_http_status(:success)
      end
    end

    context 'and is NOT a member of its project' do
      before { allow(FGCZ).to receive(:get_user_projects2).and_return(['p9999']) }

      it 'is refused — the loosened lookup must not authorize everything' do
        get "/api/v1/datasets/#{foreign_dataset.id}", headers: jwt_headers_for(user)

        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)['error']).to eq('Forbidden')
      end

      it 'is refused even for a dataset the user DOES own' do
        mine = create(:data_set, name: 'Mine', project: project, user: user)

        get "/api/v1/datasets/#{mine.id}", headers: jwt_headers_for(user)

        expect(response).to have_http_status(:forbidden)
      end
    end

    it 'still answers 404 for an id that does not exist' do
      allow(FGCZ).to receive(:get_user_projects2).and_return(['p1001'])

      get '/api/v1/datasets/99999999', headers: jwt_headers_for(user)

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)['error']).to eq('Dataset not found')
    end
  end


  describe 'GET /api/v1/datasets/:id/tree' do
    context 'when authentication is skipped' do
      before { mock_authentication_skipped(true) }

      it 'returns tree with ancestors and descendants' do
        # Create a tree: grandparent -> parent -> dataset -> child1, child2
        grandparent = create(:data_set, name: 'Grandparent', project: project, user: user, comment: 'Root dataset')
        parent = create(:data_set, name: 'Parent', project: project, user: user, parent_id: grandparent.id)
        dataset = create(:data_set, name: 'Current', project: project, user: user, parent_id: parent.id)
        child1 = create(:data_set, name: 'Child1', project: project, user: user, parent_id: dataset.id)
        child2 = create(:data_set, name: 'Child2', project: project, user: user, parent_id: dataset.id)

        get "/api/v1/datasets/#{dataset.id}/tree"
        expect(response).to have_http_status(:success)
        
        body = JSON.parse(response.body)
        expect(body).to be_an(Array)
        expect(body.size).to eq(5)
        
        # Verify structure
        grandparent_node = body.find { |n| n['id'] == grandparent.id }
        expect(grandparent_node['parent']).to eq('#')
        expect(grandparent_node['comment']).to eq('Root dataset')
        
        parent_node = body.find { |n| n['id'] == parent.id }
        expect(parent_node['parent']).to eq(grandparent.id)
        
        current_node = body.find { |n| n['id'] == dataset.id }
        expect(current_node['parent']).to eq(parent.id)
        
        child1_node = body.find { |n| n['id'] == child1.id }
        expect(child1_node['parent']).to eq(dataset.id)
      end

      it 'returns only dataset when no parents or children' do
        dataset = create(:data_set, name: 'Standalone', project: project, user: user)
        
        get "/api/v1/datasets/#{dataset.id}/tree"
        expect(response).to have_http_status(:success)
        
        body = JSON.parse(response.body)
        expect(body.size).to eq(1)
        expect(body.first['id']).to eq(dataset.id)
        expect(body.first['parent']).to eq('#')
      end

      it 'returns 404 for non-existent dataset' do
        get '/api/v1/datasets/99999/tree'
        expect(response).to have_http_status(:not_found)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('Dataset not found')
      end
    end

    context 'when JWT authentication is required' do
      before { mock_authentication_skipped(false) }

      it 'returns unauthorized without token' do
        dataset = create(:data_set, name: 'Test', project: project, user: user)
        get "/api/v1/datasets/#{dataset.id}/tree"
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns tree for authenticated user' do
        dataset = create(:data_set, name: 'Test', project: project, user: user)
        
        get "/api/v1/datasets/#{dataset.id}/tree", headers: jwt_headers_for(user)
        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body)
        expect(body).to be_an(Array)
      end
    end
  end

  describe 'GET /api/v1/datasets/:id/runnable_apps' do
    let!(:sushi_app1) do
      create(:sushi_application, 
        class_name: 'FastqcApp', 
        analysis_category: 'QC',
        required_columns: ['Read1']
      )
    end
    let!(:sushi_app2) do
      create(:sushi_application, 
        class_name: 'BwaApp', 
        analysis_category: 'Mapping',
        required_columns: ['Read1']
      )
    end

    context 'when authentication is skipped' do
      before { mock_authentication_skipped(true) }

      it 'returns runnable applications grouped by category' do
        dataset = create(:data_set, name: 'Test', project: project, user: user)
        sample = create(:sample, data_set: dataset, key_value: "{'Name' => 'Sample1', 'Read1' => 'file.fastq'}")
        
        get "/api/v1/datasets/#{dataset.id}/runnable_apps"
        expect(response).to have_http_status(:success)
        
        body = JSON.parse(response.body)
        expect(body).to be_an(Array)
        
        # Find the categories
        qc_category = body.find { |c| c['category'] == 'QC' }
        mapping_category = body.find { |c| c['category'] == 'Mapping' }
        
        expect(qc_category['applications']).to include('Fastqc')
        expect(mapping_category['applications']).to include('Bwa')
      end

      it 'returns empty array when no apps match' do
        dataset = create(:data_set, name: 'Test', project: project, user: user)
        sample = create(:sample, data_set: dataset, key_value: "{'Name' => 'Sample1'}")
        
        get "/api/v1/datasets/#{dataset.id}/runnable_apps"
        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body)
        expect(body).to eq([])
      end

      it 'returns 404 for non-existent dataset' do
        get '/api/v1/datasets/99999/runnable_apps'
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when JWT authentication is required' do
      before { mock_authentication_skipped(false) }

      it 'returns unauthorized without token' do
        dataset = create(:data_set, name: 'Test', project: project, user: user)
        get "/api/v1/datasets/#{dataset.id}/runnable_apps"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/datasets/:id/samples' do
    context 'when authentication is skipped' do
      before { mock_authentication_skipped(true) }

      it 'returns all samples for the dataset' do
        dataset = create(:data_set, name: 'Test', project: project, user: user)
        sample1 = create(:sample, data_set: dataset, key_value: "{'Name' => 'Sample1', 'Concentration' => '100'}")
        sample2 = create(:sample, data_set: dataset, key_value: "{'Name' => 'Sample2', 'Concentration' => '200'}")
        
        get "/api/v1/datasets/#{dataset.id}/samples"
        expect(response).to have_http_status(:success)
        
        body = JSON.parse(response.body)
        expect(body).to be_an(Array)
        expect(body.size).to eq(2)
        
        names = body.map { |s| s['Name'] }
        expect(names).to match_array(['Sample1', 'Sample2'])
      end

      it 'returns empty array when dataset has no samples' do
        dataset = create(:data_set, name: 'Test', project: project, user: user)
        
        get "/api/v1/datasets/#{dataset.id}/samples"
        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body)
        expect(body).to eq([])
      end

      it 'handles samples with different columns' do
        dataset = create(:data_set, name: 'Test', project: project, user: user)
        sample1 = create(:sample, data_set: dataset, key_value: "{'Name' => 'S1', 'ColA' => 'valA'}")
        sample2 = create(:sample, data_set: dataset, key_value: "{'Name' => 'S2', 'ColB' => 'valB'}")
        
        get "/api/v1/datasets/#{dataset.id}/samples"
        expect(response).to have_http_status(:success)
        
        body = JSON.parse(response.body)
        expect(body.size).to eq(2)
        
        s1 = body.find { |s| s['Name'] == 'S1' }
        s2 = body.find { |s| s['Name'] == 'S2' }
        
        expect(s1['ColA']).to eq('valA')
        expect(s2['ColB']).to eq('valB')
      end

      it 'returns 404 for non-existent dataset' do
        get '/api/v1/datasets/99999/samples'
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when JWT authentication is required' do
      before { mock_authentication_skipped(false) }

      it 'returns unauthorized without token' do
        dataset = create(:data_set, name: 'Test', project: project, user: user)
        get "/api/v1/datasets/#{dataset.id}/samples"
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns samples for authenticated user' do
        dataset = create(:data_set, name: 'Test', project: project, user: user)
        sample = create(:sample, data_set: dataset, key_value: "{'Name' => 'Sample1'}")
        
        get "/api/v1/datasets/#{dataset.id}/samples", headers: jwt_headers_for(user)
        expect(response).to have_http_status(:success)
        body = JSON.parse(response.body)
        expect(body.size).to eq(1)
      end
    end
  end
end

