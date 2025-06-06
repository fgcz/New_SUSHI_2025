module JsonHelpers
  def json_response
    @json_response ||= JSON.parse(response.body)
  end

  def json_response_symbolized
    @json_response_symbolized ||= JSON.parse(response.body, symbolize_names: true)
  end

  def expect_json_response_to_have_keys(*keys)
    keys.each do |key|
      expect(json_response).to have_key(key.to_s)
    end
  end

  def expect_json_response_structure(expected_structure)
    expect(json_response.keys.sort).to eq(expected_structure.map(&:to_s).sort)
  end
end

RSpec.configure do |config|
  config.include JsonHelpers, type: :request
  config.include JsonHelpers, type: :controller
end 