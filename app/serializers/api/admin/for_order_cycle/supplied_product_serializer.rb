# frozen_string_literal: true

module Api
  module Admin
    module ForOrderCycle
      class SuppliedProductSerializer < ActiveModel::Serializer
        attributes :name, :supplier_name, :image_url, :master_id, :variants

        def supplier_name
          object.supplier&.name
        end

        def image_url
          object.images.first&.url(:mini)
        end

        def master_id
          object.master.id
        end

        def variants
          variants = if order_cycle.present? &&
                        order_cycle.prefers_product_selection_from_coordinator_inventory_only?
                       object.variants.visible_for(order_cycle.coordinator)
                     else
                       object.variants
                     end
          variants.map { |variant| { id: variant.id, label: variant.full_name } }
        end

        private

        def order_cycle
          options[:order_cycle]
        end
      end
    end
  end
end
