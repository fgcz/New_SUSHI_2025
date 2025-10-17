FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { 'password123' }
    password_confirmation { 'password123' }
  end

  factory :project do
    sequence(:number) { |n| 10000 + n }
  end

  factory :data_set do
    sequence(:name) { |n| "Test Dataset #{n}" }
    association :project
    association :user
    parent_id { nil }  # Set parent_id to nil to avoid self-reference validation
  end

  factory :sample do
    association :data_set
  end

  factory :job do
    association :data_set
  end

  factory :sushi_application do
    sequence(:class_name) { |n| "TestApp#{n}" }
    analysis_category { 'QC' }
    required_columns { [] }
    next_dataset_keys { [] }
  end
end 