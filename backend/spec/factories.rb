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
    sequence(:submit_job_id) { |n| 30000 + n }
    status { 'COMPLETED' }
    user { 'testuser' }
    start_time { Time.current }
    end_time { Time.current + 1.hour }
    
    # Set next_dataset_id manually since Job uses non-standard foreign key
    transient do
      data_set { nil }
    end
    
    after(:build) do |job, evaluator|
      if evaluator.data_set
        job.next_dataset_id = evaluator.data_set.id
      end
    end
  end

  factory :sushi_application do
    sequence(:class_name) { |n| "TestApp#{n}" }
    analysis_category { 'QC' }
    required_columns { [] }
    next_dataset_keys { [] }
  end
end 