class AuthenticationController < ApplicationController
  if respond_to?(:authenticate_user!)
    before_action :authenticate_user!, except: [:login_options, :wallet_auth]
  end
  
  # Return available authentication methods
  def login_options
    render json: {
      standard_login: AuthenticationHelper.standard_login_enabled?,
      oauth2_login: AuthenticationHelper.oauth2_login_enabled?,
      two_factor_auth: AuthenticationHelper.two_factor_auth_enabled?,
      ldap_auth: AuthenticationHelper.ldap_auth_enabled?,
      wallet_auth: AuthenticationHelper.wallet_auth_enabled?,
      enabled_methods: AuthenticationHelper.enabled_auth_methods,
      authentication_skipped: AuthenticationHelper.authentication_skipped?,
      current_user: current_user&.login
    }
  end
  
  # OAuth2 callback
  def oauth_callback
    auth = request.env['omniauth.auth']
    user = User.from_omniauth(auth)
    
    if user.persisted?
      sign_in_and_redirect user, event: :authentication
    else
      redirect_to new_user_registration_url, alert: 'OAuth authentication failed'
    end
  end
  
  # OAuth2 failure handling
  def oauth_failure
    redirect_to new_user_session_path, alert: 'OAuth authentication failed'
  end
  
  # Two-factor authentication setup
  def setup_two_factor
    if AuthenticationHelper.two_factor_auth_enabled?
      current_user.otp_secret_key = User.generate_otp_secret_key
      current_user.save!
      
      qr_code = RQRCode::QRCode.new(current_user.otp_provisioning_uri(
        current_user.email, 
        issuer: 'Sushi App'
      ))
      
      render json: {
        secret: current_user.otp_secret_key,
        qr_code: qr_code.as_svg
      }
    else
      render json: { error: 'Two-factor authentication is not enabled' }, status: :forbidden
    end
  end
  
  # Enable two-factor authentication
  def enable_two_factor
    if AuthenticationHelper.two_factor_auth_enabled?
      if current_user.authenticate_otp(params[:code])
        current_user.update!(otp_required_for_login: true)
        render json: { message: 'Two-factor authentication enabled' }
      else
        render json: { error: 'Invalid code' }, status: :unprocessable_entity
      end
    else
      render json: { error: 'Two-factor authentication is not enabled' }, status: :forbidden
    end
  end
  
  # Wallet authentication
  def wallet_auth
    if AuthenticationHelper.wallet_auth_enabled?
      address = params[:address]
      signature = params[:signature]
      
      # Verify signature
      if verify_wallet_signature(address, signature)
        user = User.find_by(wallet_connection: { address: address })
        
        if user
          sign_in user
          render json: { message: 'Wallet authentication successful' }
        else
          # Create new wallet connection
          user = User.create!(
            login: "wallet_#{address[0..8]}",
            email: "#{address[0..8]}@wallet.local",
            password: Devise.friendly_token[0, 20]
          )
          user.connect_wallet(address, signature)
          sign_in user
          render json: { message: 'New wallet user created and authenticated' }
        end
      else
        render json: { error: 'Invalid signature' }, status: :unprocessable_entity
      end
    else
      render json: { error: 'Wallet authentication is not enabled' }, status: :forbidden
    end
  end
  
  private
  
  def verify_wallet_signature(address, signature)
    # In actual implementation, implement signature verification logic
    # This is a simplified implementation
    signature.present? && address.present?
  end
end 