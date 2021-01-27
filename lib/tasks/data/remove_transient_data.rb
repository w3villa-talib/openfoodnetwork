# frozen_string_literal: true

class RemoveTransientData
  RETENTION_PERIOD = 6.months.ago.to_date

  # This model lets us operate on the sessions DB table using ActiveRecord's
  # methods within the scope of this service. This relies on the AR's
  # convention where a Session model maps to a sessions table.
  class Session < ActiveRecord::Base
  end

  def call
    Rails.logger.info("#{self.class.name}: processing")

    Spree::StateChange.where("created_at < ?", RETENTION_PERIOD).delete_all
    Spree::LogEntry.where("created_at < ?", RETENTION_PERIOD).delete_all
    Session.where("updated_at < ?", RETENTION_PERIOD).delete_all

    # Clear old carts and associated records
    old_carts = Spree::Order.where("state = 'cart' AND updated_at < ?", RETENTION_PERIOD)
    old_cart_line_items = Spree::LineItem.where(order_id: old_carts)
    old_cart_adjustments = Spree::Adjustment.where(order_id: old_carts)

    old_cart_adjustments.delete_all
    old_cart_line_items.delete_all
    old_carts.delete_all

    # Clear option values for deleted line items
    ActiveRecord::Base.connection.execute <<-SQL
      DELETE FROM spree_option_values_line_items
      WHERE line_item_id IN (
        SELECT line_item_id FROM spree_option_values_line_items
        LEFT OUTER JOIN spree_line_items
        ON spree_option_values_line_items.line_item_id = spree_line_items.id
        WHERE spree_line_items.id IS NULL
      );
    SQL
  end
end
