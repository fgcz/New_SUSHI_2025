class WalletConnection < ActiveRecord::Base
  belongs_to :user
  
  validates :address, presence: true, uniqueness: true
  validates :network, presence: true
  
  before_validation :normalize_address
  
  private
  
  def normalize_address
    self.address = address.downcase if address.present?
  end
end 