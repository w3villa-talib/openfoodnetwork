class Shop::CheckoutController < Spree::CheckoutController
  layout 'darkswarm'

  prepend_before_filter :require_order_cycle
  prepend_before_filter :require_distributor_chosen
  skip_before_filter :check_registration

  include EnterprisesHelper
   
  def edit
  end

  def update
    if @order.update_attributes(params[:order])
      fire_event('spree.checkout.update')

      while @order.state != "complete"
        if @order.next
          state_callback(:after)
        else
          flash[:error] = t(:payment_processing_failed)
          render :edit
          return
        end
      end

      if @order.state == "complete" ||  @order.completed?
        flash.notice = t(:order_processed_successfully)
        flash[:commerce_tracking] = "nothing special"
        respond_with(@order, :location => order_path(@order))
      else
        render :edit
      end
    else
      render :edit
    end
  end

  private

  def skip_state_validation?
    true
  end

  def set_distributor
    unless @distributor = current_distributor 
      redirect_to main_app.root_path
    end
  end

  def require_order_cycle
    unless current_order_cycle
      redirect_to main_app.shop_path
    end
  end
  
  def load_order
    @order = current_order
    redirect_to main_app.shop_path and return unless @order and @order.checkout_allowed?
    raise_insufficient_quantity and return if @order.insufficient_stock_lines.present?
    redirect_to main_app.shop_path and return if @order.completed?
    before_address
    state_callback(:before)
  end

  def before_address
    associate_user
    last_used_bill_address, last_used_ship_address = find_last_used_addresses(@order.email)
    preferred_bill_address, preferred_ship_address = spree_current_user.bill_address, spree_current_user.ship_address if spree_current_user.respond_to?(:bill_address) && spree_current_user.respond_to?(:ship_address)
    @order.bill_address ||= preferred_bill_address || last_used_bill_address || Spree::Address.default
    @order.ship_address ||= preferred_ship_address || last_used_ship_address || Spree::Address.default 
  end

  # Overriding Spree's methods
  def raise_insufficient_quantity
    flash[:error] = t(:spree_inventory_error_flash_for_insufficient_quantity)
    redirect_to main_app.shop_path
  end

  # Overriding from github.com/spree/spree_paypal_express
  def redirect_to_paypal_express_form_if_needed
    return unless params[:order][:payments_attributes]

    payment_method = Spree::PaymentMethod.find(params[:order][:payments_attributes].first[:payment_method_id])
    return unless payment_method.kind_of?(Spree::BillingIntegration::PaypalExpress) || payment_method.kind_of?(Spree::BillingIntegration::PaypalExpressUk)

    update_params = object_params.dup
    update_params.delete(:payments_attributes)
    if @order.update_attributes(update_params)
      fire_event('spree.checkout.update')
      render :edit and return unless apply_coupon_code
    end

    load_order
    if not @order.errors.empty?
       render :edit and return
    end

    redirect_to(paypal_payment_order_checkout_url(@order, :payment_method_id => payment_method.id)) and return
  end
end
