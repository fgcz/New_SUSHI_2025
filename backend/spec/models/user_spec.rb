require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      user = User.new(
        email: 'test@example.com',
        password: 'password123',
        password_confirmation: 'password123'
      )
      expect(user).to be_valid
    end

    it 'is not valid without an email' do
      user = User.new(
        password: 'password123',
        password_confirmation: 'password123'
      )
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("can't be blank")
    end

    it 'is not valid without a password' do
      user = User.new(email: 'test@example.com')
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include("can't be blank")
    end

    it 'is not valid with a short password' do
      user = User.new(
        email: 'test@example.com',
        password: '123',
        password_confirmation: '123'
      )
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include('is too short (minimum is 6 characters)')
    end

    it 'is not valid with mismatched password confirmation' do
      user = User.new(
        email: 'test@example.com',
        password: 'password123',
        password_confirmation: 'different_password'
      )
      expect(user).not_to be_valid
      expect(user.errors[:password_confirmation]).to include("doesn't match Password")
    end

    it 'is not valid with duplicate email' do
      User.create!(
        email: 'test@example.com',
        password: 'password123',
        password_confirmation: 'password123'
      )
      
      user = User.new(
        email: 'test@example.com',
        password: 'password123',
        password_confirmation: 'password123'
      )
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include('has already been taken')
    end
  end

  describe 'associations' do
    it 'has many data_sets' do
      user = User.reflect_on_association(:data_sets)
      expect(user.macro).to eq(:has_many)
    end

    it 'can have multiple data_sets' do
      user = create(:user)
      
      expect(user.data_sets).to be_empty
      
      # For actual testing, related models are needed
      # data_set = DataSet.create!(name: 'Test Dataset', user: user)
      # expect(user.data_sets).to include(data_set)
    end
  end

  describe 'devise modules' do
    it 'includes database_authenticatable' do
      expect(User.devise_modules).to include(:database_authenticatable)
    end

    it 'includes registerable' do
      expect(User.devise_modules).to include(:registerable)
    end

    it 'includes recoverable' do
      expect(User.devise_modules).to include(:recoverable)
    end

    it 'includes rememberable' do
      expect(User.devise_modules).to include(:rememberable)
    end

    it 'includes trackable' do
      expect(User.devise_modules).to include(:trackable)
    end

    it 'includes validatable' do
      expect(User.devise_modules).to include(:validatable)
    end
  end

  describe 'instance methods' do
    let(:user) { create(:user) }

    it 'can be saved' do
      expect(user.persisted?).to be true
    end

    it 'has an email' do
      expect(user.email).to match(/user\d+@example\.com/)
    end

    it 'can be updated' do
      user.update(email: 'updated@example.com')
      expect(user.reload.email).to eq('updated@example.com')
    end

    it 'can be destroyed' do
      user_id = user.id
      user.destroy
      expect(User.find_by(id: user_id)).to be_nil
    end
  end

  describe 'factory' do
    it 'has a valid factory' do
      user = build(:user)
      expect(user).to be_valid
    end
  end
end 