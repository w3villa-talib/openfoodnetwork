# frozen_string_literal: true

module Spree
  class UsersController < ::BaseController
    include Spree::Core::ControllerHelpers
    include I18nHelper
    include CablecarResponses
    require 'faraday'

    layout 'darkswarm'

    skip_before_action :set_current_order, only: :show
    prepend_before_action :load_object, only: [:show, :edit, :update]
    prepend_before_action :authorize_actions, only: :new

    before_action :set_locale

    def show
      @payments_requiring_action = PaymentsRequiringAction.new(spree_current_user).query
      @orders = orders_collection.includes(:line_items)

      customers = spree_current_user.customers
      @shops = Enterprise
        .where(id: @orders.pluck(:distributor_id).uniq | customers.pluck(:enterprise_id))

      @unconfirmed_email = spree_current_user.unconfirmed_email
    end

    # Endpoint for queries to check if a user is already registered
    def registered_email
      registered = Spree::User.find_by(email: params[:email]).present?

      if registered
        render status: :ok, operations: cable_car.
          inner_html(
            "#login-feedback",
            partial("layouts/alert", locals: { type: "alert", message: t('devise.failure.already_registered') })
          ).
          dispatch_event(name: "login:modal:open")
      else
        head :not_found
      end
    end

    def create user_params
      @user = Spree::User.find_by_email(user_params[:email])
      if @user
        bypass_sign_in(@user)
        redirect_to main_app.root_path
      else
        @user = Spree::User.new(user_params)
        @user.skip_confirmation!
        if @user.save(validate: false)
        @user.confirm
        bypass_sign_in(@user)
        redirect_to main_app.root_path
        else
          render :new
        end
      end
    end

    def update
      if @user.update(user_params)
        if params[:user][:password].present?
          # this logic needed b/c devise wants to log us out after password changes
          Spree::User.reset_password_by_token(params[:user])
          bypass_sign_in(@user)
        end
        redirect_to spree.account_url, notice: Spree.t(:account_updated)
      else
        render :edit
      end
    end

    private

    def orders_collection
      CompleteOrdersWithBalance.new(@user).query
    end

    def load_object
      @user ||= spree_current_user
      if @user
        authorize! params[:action].to_sym, @user
      else
        # redirect_to main_app.login_path
        # faraday get request with headers
        response = Faraday.get 'http://localhost:3000/api/v1/profile',{userId: params[:user_id]},{token: params[:secret_key]}
        response = JSON.parse(response.body)
        # create params for user email
        user_params = {email: response['data']['email']}
        # create user
        if response['auth'] == true
         create(user_params)
        else
          #  redirect to localhost:3000/login
          redirect_to 'http://localhost:3000/login'
        end 
      
      end
    end

    def authorize_actions
      # authorize! params[:action].to_sym, Spree::User.new
    end

    def accurate_title
      Spree.t(:my_account)
    end

    def user_params
      ::PermittedAttributes::User.new(params).call
    end
  end
end
