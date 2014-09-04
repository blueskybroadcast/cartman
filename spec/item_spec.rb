require 'spec_helper'

describe Cartman do
  describe Cartman::Item do
    let(:cart) { Cartman::Cart.new(1) }
    let(:item) { cart.add_item(id: 17, type: "Bottle", name: "Bordeux", unit_cost: 92.12, quantity: 2) }
 
    describe "data getters and setters" do
      it "should let me get data stored for the item" do
        item.id.should eq("17")
        item.type.should eq("Bottle")
        item.cost.should eq(184.24)
      end

      it "should let me modify data stored for the item" do
        item.quantity.should eq("2")
        item.quantity = 3
        item.quantity.should eq("3")
      end

      it "should immediately save data back to redis" do
        item.quantity.should eq("2")
        item.quantity = 3
        new_item = cart.send(:get_item, item._id)
        new_item.quantity.should eq("3")
      end

      it "should touch the item and cart" do
        expect{item.quantity = 4}.to change{item._version}.by(1)
      end
    end

    describe "#cost" do
      it "should be equal to the unit_cost multiplied by the quantity" do
        item.cost.should eq(184.24)
        item.quantity = 3
        item.cost.should eq(276.36)
      end
    end

    describe "#destroy" do
      it "should remove the item from the cart" do
        item_id = item._id
        item.destroy
        Cartman.config.redis.sismember(cart.send(:key), item_id).should be_falsey
        Cartman.config.redis.exists("cartman:line_item:#{item_id}").should be_falsey
      end
    end

    describe "#touch" do
      it "should record that the record was changed" do
        item.touch
        item._version.should eq(1)
      end
    end

    describe "#cache_key" do
      it "should return item/{id}-{version}" do
        item.cache_key.should eq("item/#{item._id}-#{item._version}")
      end
    end
  end
end
